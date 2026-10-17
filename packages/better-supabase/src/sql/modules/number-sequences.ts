import type { NumberSequencesEvents } from "../../blocks/number-sequences/events.ts";
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
  serviceGrant,
} from "../shared.ts";

const EVENTS: ModuleEvents<NumberSequencesEvents> = {
  "number.assigned": {
    subject: "number-sequences",
    payload: ["organizationId", "entity", "period", "number"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: ["before_number_assign", "after_number_assign"],
  options: ["entities"],
  tables: {
    sequences: {
      name: "number_sequences",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        entity: "entity",
        period: "period",
        lastNumber: "last_number",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

const ENTITY = /^[a-z][a-z0-9_]*$/;
const PREDICATE = /^[A-Za-z0-9_.'"=<>!() \t-]+$/;

interface SequenceEntity {
  readonly name: string;
  readonly period: "none" | "year" | "month" | "fiscal";
  readonly fiscalMonth: number;
  readonly format: string;
  readonly table?: string;
  readonly column?: string;
  readonly tenantColumn: string;
  readonly assignOn: string;
}

function sequences(ctx: ModuleContext): readonly SequenceEntity[] {
  const raw = ctx.option("entities");
  if (raw === undefined) {
    return [];
  }
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      "blocks.number-sequences.options.entities must be an object of entity name to { period, format }",
    );
  }
  return Object.entries(raw).map(([name, entry]) => entity(name, entry));
}

function entity(name: string, entry: unknown): SequenceEntity {
  const where = `blocks.number-sequences.options.entities.${name}`;
  if (!ENTITY.test(name)) {
    throw new TypeError(
      `${where}: "${name}" must be lowercase letters, digits and underscores`,
    );
  }
  if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
    throw new TypeError(`${where} must be an object`);
  }
  const record = recordOf(entry);
  const period = record["period"];
  const fiscal =
    typeof period === "object" && period !== null && !Array.isArray(period)
      ? recordOf(period)["fiscalYearStartMonth"]
      : undefined;
  const kind =
    period === "none" || period === "year" || period === "month"
      ? period
      : fiscal === undefined
        ? undefined
        : "fiscal";
  if (kind === undefined) {
    throw new TypeError(
      `${where}.period must be "none", "year", "month" or { fiscalYearStartMonth }`,
    );
  }
  const fiscalMonth = kind === "fiscal" ? Number(fiscal) : 1;
  if (
    kind === "fiscal" &&
    (!Number.isInteger(fiscalMonth) || fiscalMonth < 1 || fiscalMonth > 12)
  ) {
    throw new TypeError(
      `${where}.period.fiscalYearStartMonth must be an integer from 1 to 12`,
    );
  }
  const format = record["format"];
  if (typeof format !== "string" || format.length === 0 || format.length > 80) {
    throw new TypeError(`${where}.format must be a short template`);
  }
  const table = record["table"];
  const column = record["column"];
  if (table !== undefined && typeof table !== "string") {
    throw new TypeError(`${where}.table must be "schema.table"`);
  }
  if (
    column !== undefined &&
    (typeof column !== "string" || !ENTITY.test(column))
  ) {
    throw new TypeError(`${where}.column must be a column name`);
  }
  if ((table === undefined) !== (column === undefined)) {
    throw new TypeError(`${where} needs both table and column, or neither`);
  }
  const tenantColumn = record["tenantColumn"] ?? "tenant_id";
  if (typeof tenantColumn !== "string" || !ENTITY.test(tenantColumn)) {
    throw new TypeError(`${where}.tenantColumn must be a column name`);
  }
  const assignOn = record["assignOn"] ?? "true";
  if (typeof assignOn !== "string" || !PREDICATE.test(assignOn)) {
    throw new TypeError(
      `${where}.assignOn must be a boolean expression over new, such as new.status = 'sent'`,
    );
  }
  return {
    name,
    period: kind,
    fiscalMonth,
    format,
    ...(typeof table === "string" && typeof column === "string"
      ? { table, column }
      : {}),
    tenantColumn,
    assignOn,
  };
}

function recordOf(value: object): Record<string, unknown> {
  const record: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) {
    record[key] = item;
  }
  return record;
}

function periodSql(item: SequenceEntity, at: string): string {
  const stamp = `${at} at time zone 'utc'`;
  switch (item.period) {
    case "none": {
      return "''";
    }
    case "year": {
      return `to_char(${stamp}, 'YYYY')`;
    }
    case "month": {
      return `to_char(${stamp}, 'YYYY-MM')`;
    }
    case "fiscal": {
      return `case when extract(month from ${stamp}) >= ${String(item.fiscalMonth)} then to_char(${stamp}, 'YYYY') else (extract(year from ${stamp})::int - 1)::text end`;
    }
    default: {
      const never: never = item.period;
      return never;
    }
  }
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }
  const table = ctx.table("sequences");
  const tenant = ctx.col("sequences", "tenant");
  const entityCol = ctx.col("sequences", "entity");
  const period = ctx.col("sequences", "period");
  const last = ctx.col("sequences", "lastNumber");
  const createdAt = ctx.col("sequences", "createdAt");
  const updatedAt = ctx.col("sequences", "updatedAt");
  const fn = ctx.fn("next_number");
  const items = sequences(ctx);
  const periodCase =
    items.length === 0
      ? "''"
      : `case next_number.entity\n${items
          .map(
            (item) =>
              `    when ${sqlString(item.name)} then ${periodSql(item, "next_number.at")}`,
          )
          .join("\n")}\n    else null\n  end`;
  const tables = ctx.manages
    ? `create table if not exists ${table} (
  ${tenant} ${ctx.idType} not null,
  ${entityCol} text not null,
  ${period} text not null default '',
  ${last} bigint not null,
  ${createdAt} timestamptz not null default now(),
  ${updatedAt} timestamptz not null default now(),
  primary key (${tenant}, ${entityCol}, ${period})
);
${lockTable(table)}
`
    : "";
  const triggers = items
    .filter((item) => item.table !== undefined && item.column !== undefined)
    .map((item) => trigger(ctx, item))
    .join("\n");
  return `${schemaPreamble(ctx)}
-- Gapless numbers. next_number locks the sequence row inside the caller's
-- transaction, so a rollback releases the number. Clients get a number
-- only through a trigger: the function is service-only.
${tables}
create or replace function better_supabase.format_assigned_number(template text, n bigint, at timestamptz)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v text := template;
  width text[];
begin
  v := replace(v, '{yyyy}', to_char(at at time zone 'utc', 'YYYY'));
  v := replace(v, '{yy}', to_char(at at time zone 'utc', 'YY'));
  v := replace(v, '{mm}', to_char(at at time zone 'utc', 'MM'));
  v := replace(v, '{dd}', to_char(at at time zone 'utc', 'DD'));
  while v ~ '\\{n:[0-9]+\\}' loop
    width := regexp_match(v, '\\{n:([0-9]+)\\}');
    v := regexp_replace(v, '\\{n:[0-9]+\\}', lpad(n::text, width[1]::int, '0'));
  end loop;
  return replace(v, '{n}', n::text);
end;
$$;
${serviceGrant("better_supabase.format_assigned_number(text, bigint, timestamptz)")}

-- PostgreSQL refuses CREATE OR REPLACE when an argument is renamed.
drop function if exists ${fn}(${ctx.idType}, text, timestamptz) cascade;
create or replace function ${fn}(tenant ${ctx.idType}, p_entity text, at timestamptz default now())
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text;
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    ${fail("ACTOR_READ_ONLY", "This session is read-only")}
  end if;
  v_period := ${periodCase.replaceAll("next_number.entity", "p_entity")};
  if v_period is null then
    ${fail("NUMBER_ENTITY_UNKNOWN", "unknown number sequence", "22023")}
  end if;
  ${ctx.hook("before_number_assign", [
    [ctx.idType, "next_number.tenant"],
    ["text", "p_entity"],
    ["text", "v_period"],
  ])}
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || v_period, 0));
  insert into ${table} (${tenant}, ${entityCol}, ${period}, ${last})
  values (next_number.tenant, p_entity, v_period, 1)
  on conflict (${tenant}, ${entityCol}, ${period})
  do update set ${last} = ${table}.${last} + 1, ${updatedAt} = now()
  returning ${last} into v_n;
  ${ctx.record({
    type: "number.assigned",
    payload: `jsonb_build_object('organizationId', next_number.tenant, 'entity', p_entity, 'period', v_period, 'number', v_n)`,
    subject: `'number-sequences/' || p_entity`,
    tenant: "next_number.tenant",
    audit: {
      category: "data",
      targetType: "number_sequence",
      recordId: "p_entity",
      summary: `'assigned ' || v_n::text`,
    },
  })}
  ${ctx.hook("after_number_assign", [
    [ctx.idType, "next_number.tenant"],
    ["text", "p_entity"],
    ["bigint", "v_n"],
  ])}
  return v_n;
end;
$$;
${serviceGrant(`${fn}(${ctx.idType}, text, timestamptz)`)}
${triggers}`;
}

function trigger(ctx: ModuleContext, item: SequenceEntity): string {
  const table = item.table;
  const column = item.column;
  if (table === undefined || column === undefined) {
    return "";
  }
  const target = quotedTable(table);
  const col = sqlIdent(column);
  const fn = sqlIdent(`bs_assign_number_${item.name}`);
  return `
create or replace function better_supabase.${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    ${fail("ACTOR_READ_ONLY", "This session is read-only")}
  end if;
  if tg_op = 'UPDATE' and old.${col} is not null then
    if new.${col} is distinct from old.${col} then
      ${fail("NUMBER_IMMUTABLE", "a number cannot change", "22023")}
    end if;
    return new;
  end if;
  if new.${col} is not null or not (${item.assignOn}) then
    return new;
  end if;
  v_n := ${ctx.fn("next_number")}(new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, now());
  new.${col} := better_supabase.format_assigned_number(${sqlString(item.format)}, v_n, now());
  return new;
end;
$$;
${serviceGrant(`better_supabase.${fn}()`)}
drop trigger if exists ${fn} on ${target};
create trigger ${fn} before insert or update on ${target}
for each row execute function better_supabase.${fn}();`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "next_number",
      args: ["{id}", "text", "timestamptz"],
      returns: "bigint",
    },
  ];
}

export const NUMBER_SEQUENCES: ModuleDefinition = {
  name: "number-sequences",
  scopes: ["tenant"],
  title: "Number sequences",
  description:
    "Gapless numbers per tenant, entity and period. next_number locks the row in the caller's transaction, and a trigger fills the document column so a separate round trip cannot open a gap.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
