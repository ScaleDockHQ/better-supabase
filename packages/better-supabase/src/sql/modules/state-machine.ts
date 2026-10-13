import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  quotedTable,
  schemaPreamble,
  userGrant,
} from "../shared.ts";

const EVENTS: ModuleEvents = {
  "status.changed": {
    subject: "statuses",
    payload: ["organizationId", "subjectType", "subjectId", "from", "to"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: ["before_status_transition", "after_status_transition"],
  options: ["machines"],
  tables: {
    history: {
      name: "status_history",
      lifecycle: { tenant: "tenant", user: "actor", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        fromStatus: "from_status",
        toStatus: "to_status",
        actor: "actor_user_id",
        reason: "reason",
        createdAt: "created_at",
      },
    },
    stages: {
      name: "status_stages",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        label: "label",
        outcome: "outcome",
        display: "display",
        clearedAt: "cleared_at",
        createdAt: "created_at",
      },
    },
  },
};

const NAME = /^[a-z][a-z0-9_]*$/;

interface Machine {
  readonly name: string;
  readonly table: string;
  readonly column: string;
  readonly idColumn: string;
  readonly tenantColumn: string;
  readonly initial: string;
  readonly transitions: Readonly<Record<string, readonly string[]>>;
  /** Writes a timeline row (label snapshot, display order, cleared_at). */
  readonly stages: boolean;
  readonly history?: {
    readonly table: string;
    readonly from: string;
    readonly to: string;
    readonly actor: string;
    readonly reason: string;
    readonly subject: string;
    readonly tenant: string;
  };
}

function machines(ctx: ModuleContext): readonly Machine[] {
  const raw = ctx.option("machines");
  if (raw === undefined) return [];
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      "sql.modules.state-machine.options.machines must be an object",
    );
  }
  return Object.entries(raw).map(([name, entry]) => machine(name, entry));
}

function machine(name: string, entry: unknown): Machine {
  const where = `sql.modules.state-machine.options.machines.${name}`;
  if (!NAME.test(name)) throw new TypeError(`${where} has an invalid name`);
  if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
    throw new TypeError(`${where} must be an object`);
  }
  const record: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(entry)) record[key] = value;
  const table = record["table"];
  const column = record["column"];
  const initial = record["initial"];
  const transitions = record["transitions"];
  if (typeof table !== "string" || typeof column !== "string") {
    throw new TypeError(`${where} needs table and column`);
  }
  if (typeof initial !== "string" || !NAME.test(column)) {
    throw new TypeError(`${where}.column must be a column name`);
  }
  if (
    typeof transitions !== "object" ||
    transitions === null ||
    Array.isArray(transitions)
  ) {
    throw new TypeError(
      `${where}.transitions must be an object of status to statuses`,
    );
  }
  const edges: Record<string, readonly string[]> = {};
  for (const [from, to] of Object.entries(transitions)) {
    if (!Array.isArray(to) || to.some((item) => typeof item !== "string")) {
      throw new TypeError(
        `${where}.transitions.${from} must be a list of statuses`,
      );
    }
    edges[from] = to;
  }
  const history = historyOf(record["history"], where);
  return {
    name,
    table,
    column,
    idColumn: typeof record["id"] === "string" ? record["id"] : "id",
    tenantColumn:
      typeof record["tenant"] === "string" ? record["tenant"] : "tenant_id",
    initial,
    transitions: edges,
    stages: record["stages"] === true,
    ...(history === undefined ? {} : { history }),
  };
}

function historyOf(
  value: unknown,
  where: string,
): Machine["history"] | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${where}.history must be an object`);
  }
  const record: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) record[key] = item;
  const text = (key: string, fallback: string): string => {
    const item = record[key];
    if (item === undefined) return fallback;
    if (typeof item !== "string" || !NAME.test(item)) {
      throw new TypeError(`${where}.history.${key} must be a column name`);
    }
    return item;
  };
  const table = record["table"];
  if (typeof table !== "string") {
    throw new TypeError(`${where}.history.table is required`);
  }
  return {
    table,
    from: text("from", "from_status"),
    to: text("to", "to_status"),
    actor: text("actor", "actor_user_id"),
    reason: text("reason", "reason"),
    subject: text("subject", "subject_id"),
    tenant: text("tenant", "tenant_id"),
  };
}

function stageWrite(
  ctx: ModuleContext,
  item: Machine,
  kind: "open" | "advance",
): string {
  if (!item.stages || !ctx.hasTable("stages")) return "";
  const stages = ctx.table("stages");
  const subjectType = ctx.col("stages", "subjectType");
  const subjectId = ctx.col("stages", "subjectId");
  const cleared = ctx.col("stages", "clearedAt");
  const display = ctx.col("stages", "display");
  const id = sqlIdent(item.idColumn);
  const clear =
    kind === "advance"
      ? `update ${stages} set ${cleared} = now()
  where ${subjectType} = ${sqlString(item.name)}
    and ${subjectId} = new.${id}::text
    and ${cleared} is null;`
      : "";
  return `${clear}
  insert into ${stages} (${ctx.col("stages", "tenant")}, ${subjectType}, ${subjectId}, ${ctx.col("stages", "label")}, ${display})
  values (new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, new.${id}::text, new.${sqlIdent(item.column)},
    coalesce((select max(s.${display}) from ${stages} s where s.${subjectId} = new.${id}::text), 0) + 1);`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const history = ctx.table("history");
  const tables = ctx.manages
    ? `create table if not exists ${history} (
  ${ctx.col("history", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("history", "tenant")} ${ctx.idType} not null,
  ${ctx.col("history", "subjectType")} text not null,
  ${ctx.col("history", "subjectId")} text not null,
  ${ctx.col("history", "fromStatus")} text,
  ${ctx.col("history", "toStatus")} text not null,
  ${ctx.col("history", "actor")} uuid,
  ${ctx.col("history", "reason")} text,
  ${ctx.col("history", "createdAt")} timestamptz not null default now()
);
${lockTable(history, { read: true })}
${
  ctx.hasTable("stages")
    ? `create table if not exists ${ctx.table("stages")} (
  ${ctx.col("stages", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("stages", "tenant")} ${ctx.idType} not null,
  ${ctx.col("stages", "subjectType")} text not null,
  ${ctx.col("stages", "subjectId")} text not null,
  ${ctx.col("stages", "label")} text not null,
  ${ctx.col("stages", "outcome")} text,
  ${ctx.col("stages", "display")} integer not null,
  ${ctx.col("stages", "clearedAt")} timestamptz,
  ${ctx.col("stages", "createdAt")} timestamptz not null default now()
);
${lockTable(ctx.table("stages"), { read: true })}
`
    : ""
}`
    : "";
  const list = machines(ctx);
  for (const item of list) {
    if (item.stages && !ctx.hasTable("stages")) {
      throw new TypeError(
        `sql.modules.state-machine.options.machines.${item.name}.stages needs the stages table`,
      );
    }
  }
  const arms = list
    .map((item) => {
      const allowed = Object.entries(item.transitions)
        .map(
          ([from, to]) =>
            `when ${sqlString(from)} then new.${sqlIdent(item.column)} = any (${sqlString(`{${to.join(",")}}`)}::text[])`,
        )
        .join(" ");
      const target = quotedTable(item.table);
      const hist = item.history;
      const write = hist
        ? `insert into ${quotedTable(hist.table)} (${sqlIdent(hist.subject)}, ${sqlIdent(hist.tenant)}, ${sqlIdent(hist.from)}, ${sqlIdent(hist.to)}, ${sqlIdent(hist.actor)}, ${sqlIdent(hist.reason)})
        values (new.${sqlIdent(item.idColumn)}, new.${sqlIdent(item.tenantColumn)}, old.${sqlIdent(item.column)}, new.${sqlIdent(item.column)}, auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''));`
        : `insert into ${history} (${ctx.col("history", "tenant")}, ${ctx.col("history", "subjectType")}, ${ctx.col("history", "subjectId")}, ${ctx.col("history", "fromStatus")}, ${ctx.col("history", "toStatus")}, ${ctx.col("history", "actor")}, ${ctx.col("history", "reason")})
        values (new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, new.${sqlIdent(item.idColumn)}::text, old.${sqlIdent(item.column)}, new.${sqlIdent(item.column)}, auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''));`;
      return `
create or replace function better_supabase.bs_transition_${item.name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.${sqlIdent(item.column)} is null then
      new.${sqlIdent(item.column)} := ${sqlString(item.initial)};
    end if;
    ${stageWrite(ctx, item, "open")}
    return new;
  end if;
  if new.${sqlIdent(item.column)} is not distinct from old.${sqlIdent(item.column)} then
    return new;
  end if;
  if not (case old.${sqlIdent(item.column)} ${allowed} else false end) then
    ${fail("STATE_TRANSITION_INVALID", "that status change is not allowed", "22023")}
  end if;
  ${write}
  ${stageWrite(ctx, item, "advance")}
  return new;
end;
$$;
drop trigger if exists bs_transition_${item.name} on ${target};
create trigger bs_transition_${item.name} before insert or update of ${sqlIdent(item.column)} on ${target}
for each row execute function better_supabase.bs_transition_${item.name}();`;
    })
    .join("\n");
  return `${schemaPreamble(ctx)}
${tables}
${arms}
create or replace function ${ctx.fn("transition")}(subject_type text, subject_id text, to_status text, reason text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  ${ctx.hook("before_status_transition", [
    ["text", "transition.subject_type"],
    ["text", "transition.subject_id"],
    ["text", "transition.to_status"],
  ])}
  ${
    list.length === 0
      ? fail("STATE_MACHINE_UNKNOWN", "unknown subject", "22023")
      : `case transition.subject_type
${list
  .map(
    (item) =>
      `    when ${sqlString(item.name)} then
      update ${quotedTable(item.table)} set ${sqlIdent(item.column)} = transition.to_status
      where ${sqlIdent(item.idColumn)}::text = transition.subject_id;`,
  )
  .join("\n")}
    else
      ${fail("STATE_MACHINE_UNKNOWN", "unknown subject", "22023")}
  end case;`
  }
  ${ctx.record({
    type: "status.changed",
    payload: `jsonb_build_object('organizationId', null, 'subjectType', transition.subject_type, 'subjectId', transition.subject_id, 'from', null, 'to', transition.to_status)`,
    subject: `'statuses/' || transition.subject_type || '/' || transition.subject_id`,
    audit: false,
  })}
  ${ctx.hook("after_status_transition", [
    ["text", "transition.subject_type"],
    ["text", "transition.to_status"],
  ])}
  return true;
end;
$$;
${userGrant(`${ctx.fn("transition")}(text, text, text, text)`)}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "transition",
      args: ["text", "text", "text", "text"],
      returns: "boolean",
    },
  ];
}

export const STATE_MACHINE: ModuleDefinition = {
  name: "state-machine",
  title: "State machine",
  description:
    "Allowed status transitions, a history row and a status.changed event. A machine can also write a stages timeline. Each machine is a subject table named in options.machines.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
