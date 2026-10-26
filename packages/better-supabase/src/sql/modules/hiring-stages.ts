import type { BlockSqlContext } from "../context.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, quotedTable, triggerGrant } from "../shared.ts";

const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/;

const OUTCOMES = ["hired", "rejected", "withdrawn"] as const;

type Outcome = (typeof OUTCOMES)[number];

interface StageMarker {
  readonly column: string;
  readonly value?: string;
}

export interface JobStages {
  readonly table: string;
  readonly id: string;
  readonly job: string;
  readonly rank: string;
  readonly archivedAt?: string;
  readonly markers: Readonly<Partial<Record<Outcome, StageMarker>>>;
}

function columnOf(where: string, value: unknown): string {
  if (typeof value !== "string" || !COLUMN.test(value)) {
    throw new TypeError(`${where} must be a column name`);
  }

  return sqlIdent(value);
}

function markerOf(where: string, value: unknown): StageMarker | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value === "string") {
    return { column: columnOf(where, value) };
  }

  if (
    !isRecord(value) ||
    typeof value["value"] !== "string" ||
    value["value"] === ""
  ) {
    throw new TypeError(
      `${where} must be a boolean column or { column, value }`,
    );
  }

  return {
    column: columnOf(`${where}.column`, value["column"]),
    value: value["value"],
  };
}

export function jobStages(ctx: BlockSqlContext): JobStages | undefined {
  const raw = ctx.option("stages");
  const where = `blocks.${ctx.instance}.options.stages`;

  if (raw === undefined || raw === "pipelines") {
    return undefined;
  }

  if (!isRecord(raw) || typeof raw["table"] !== "string") {
    throw new TypeError(
      `${where} must be "pipelines" or { table, job, rank, hired?, rejected?, withdrawn? }`,
    );
  }

  const known = new Set([
    "table",
    "id",
    "job",
    "rank",
    "archivedAt",
    ...OUTCOMES,
  ]);

  const unknown = Object.keys(raw).find((key) => !known.has(key));

  if (unknown !== undefined) {
    throw new TypeError(`${where}: unknown key "${unknown}"`);
  }

  const markers: Partial<Record<Outcome, StageMarker>> = {};

  for (const outcome of OUTCOMES) {
    const marker = markerOf(`${where}.${outcome}`, raw[outcome]);

    if (marker !== undefined) {
      markers[outcome] = marker;
    }
  }

  return {
    table: quotedTable(raw["table"]),
    id: columnOf(`${where}.id`, raw["id"] ?? "id"),
    job: columnOf(`${where}.job`, raw["job"]),
    rank: columnOf(`${where}.rank`, raw["rank"]),
    ...(raw["archivedAt"] !== undefined && {
      archivedAt: columnOf(`${where}.archivedAt`, raw["archivedAt"]),
    }),
    markers,
  };
}

function marks(marker: StageMarker, alias: string): string {
  return marker.value === undefined
    ? `coalesce(${alias}.${marker.column}, false)`
    : `coalesce(${alias}.${marker.column}::text = ${sqlString(marker.value)}, false)`;
}

function active(stages: JobStages, alias: string): string {
  return stages.archivedAt === undefined
    ? ""
    : ` and ${alias}.${stages.archivedAt} is null`;
}

function outcomeOf(stages: JobStages, alias: string): string {
  const cases = OUTCOMES.flatMap((outcome) => {
    const marker = stages.markers[outcome];

    return marker === undefined
      ? []
      : [`when ${marks(marker, alias)} then ${sqlString(outcome)}`];
  });

  return cases.length === 0
    ? "'active'"
    : `case ${cases.join(" ")} else 'active' end`;
}

export function closeInStages(
  ctx: BlockSqlContext,
  stages: JobStages | undefined,
  outcome: Outcome,
): string {
  const a = (column: string): string => ctx.col("applications", column);
  const marker = stages?.markers[outcome];

  const move =
    stages === undefined || marker === undefined
      ? ""
      : `
      select x.${stages.id} into v_stage from ${stages.table} x
      where x.${stages.job} = v_row.${a("job")}${active(stages, "x")} and ${marks(marker, "x")}
      order by x.${stages.rank}, x.${stages.id} limit 1;
      if v_stage is not null then
        update ${ctx.table("applications")} x set ${a("stage")} = v_stage where x.${a("id")} = v_row.${a("id")};
      end if;`;

  return `${move}
      update ${ctx.table("applications")} x set ${a("state")} = ${ctx.value("applications", "state", outcome)}
      where x.${a("id")} = v_row.${a("id")} and ${ctx.is("applications", "state", `x.${a("state")}`, [outcome], true)};`;
}

export function stageTriggers(ctx: BlockSqlContext, stages: JobStages): string {
  const a = (column: string): string => ctx.col("applications", column);
  const t = ctx.table("applications");
  const name = ctx.naming.rename("bsb_application_stage");
  const state = ctx.naming.rename("bsb_application_stage_state");

  const open = OUTCOMES.flatMap((outcome) => {
    const marker = stages.markers[outcome];

    return marker === undefined ? [] : [marks(marker, "s")];
  });

  const isOpen = open.length === 0 ? "" : ` and not (${open.join(" or ")})`;

  const entered = ctx.has("applications", "stageEnteredAt")
    ? `
  if tg_op = 'INSERT' or new.${a("stage")} is distinct from old.${a("stage")} then
    new.${a("stageEnteredAt")} := now();
  end if;`
    : "";

  return `
-- An application stays on a stage of its own job: a new one starts on the
-- job's first open stage, and a move to another job's stage is refused.
create or replace function better_supabase.${name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.${a("stage")} is not distinct from old.${a("stage")} and new.${a("job")} is not distinct from old.${a("job")} then
    return new;
  end if;
  if new.${a("stage")} is null then
    select s.${stages.id} into new.${a("stage")} from ${stages.table} s
    where s.${stages.job} = new.${a("job")}${active(stages, "s")}${isOpen}
    order by s.${stages.rank}, s.${stages.id}
    limit 1;
  elsif not exists (
    select 1 from ${stages.table} s
    where s.${stages.id} = new.${a("stage")} and s.${stages.job} = new.${a("job")}${active(stages, "s")}
  ) then
    ${fail("HIRING_STAGE_INVALID", "the stage is not an active stage of this application's job", "22023")}
  end if;${entered}
  return new;
end;
$$;
${triggerGrant(`better_supabase.${name}()`)}
drop trigger if exists ${name} on ${t};
create trigger ${name} before insert or update of ${a("stage")}, ${a("job")} on ${t}
for each row execute function better_supabase.${name}();

-- A move to a stage that marks hired, rejected or withdrawn sets that state,
-- and a move back to an open stage makes the application active again.
create or replace function better_supabase.${state}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state text;
begin
  select ${outcomeOf(stages, "s")} into v_state from ${stages.table} s where s.${stages.id} = new.${a("stage")};
  if v_state is not null and v_state is distinct from (${ctx.label("applications", "state", `new.${a("state")}`)})::text then
    update ${t} x set ${a("state")} = ${ctx.cast("applications", "state", "v_state")} where x.${a("id")} = new.${a("id")};
  end if;
  return null;
end;
$$;
${triggerGrant(`better_supabase.${state}()`)}
drop trigger if exists ${state} on ${t};
create trigger ${state} after insert or update of ${a("stage")} on ${t}
for each row execute function better_supabase.${state}();
`;
}
