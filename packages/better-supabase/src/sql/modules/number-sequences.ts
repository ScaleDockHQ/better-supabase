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
  SERVICE_CALLER,
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
      typed: ["entity"],
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
  readonly periodColumn?: string;
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

  const periodColumn = record["periodColumn"];

  if (
    periodColumn !== undefined &&
    (typeof periodColumn !== "string" || !ENTITY.test(periodColumn))
  ) {
    throw new TypeError(`${where}.periodColumn must be a column name`);
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
    ...(typeof periodColumn === "string" ? { periodColumn } : {}),
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

const rowAt = (column: string): string =>
  `better_supabase.number_at(${column})`;

const TOKEN = /\{(yyyy|yy|mm|dd|n(?::[0-9]+)?)\}/g;

const TOKEN_PATTERN: Readonly<Record<string, string>> = {
  yyyy: "([0-9]{4})",
  yy: "([0-9]{2})",
  mm: "([0-9]{2})",
  dd: "([0-9]{2})",
  n: "([0-9]+)",
};

function formatPattern(format: string): {
  readonly pattern: string;
  readonly groups: ReadonlyMap<string, number>;
} {
  const groups = new Map<string, number>();
  let pattern = "";
  let cursor = 0;
  let index = 0;

  for (const match of format.matchAll(TOKEN)) {
    const token = match[1]!.startsWith("n") ? "n" : match[1]!;
    index += 1;
    pattern += escapeRegex(format.slice(cursor, match.index));
    pattern += TOKEN_PATTERN[token]!;
    cursor = match.index + match[0].length;

    if (!groups.has(token)) {
      groups.set(token, index);
    }
  }

  return {
    pattern: `^${pattern}${escapeRegex(format.slice(cursor))}$`,
    groups,
  };
}

const escapeRegex = (text: string): string =>
  text.replaceAll(/[\\^$.|?*+()[\]{}]/g, "\\$&");

function syncPeriod(
  item: SequenceEntity,
  groups: ReadonlyMap<string, number>,
): string | undefined {
  if (item.period === "none") {
    return "''";
  }

  if (item.periodColumn !== undefined) {
    return periodSql(item, rowAt(`t.${sqlIdent(item.periodColumn)}`));
  }

  const part = (token: string): string | undefined => {
    const group = groups.get(token);

    return group === undefined ? undefined : `m.parts[${String(group)}]`;
  };

  const yy = part("yy");
  const year = part("yyyy") ?? (yy === undefined ? undefined : `'20' || ${yy}`);
  const month = part("mm");

  switch (item.period) {
    case "year": {
      return year;
    }

    case "month": {
      return year === undefined || month === undefined
        ? undefined
        : `${year} || '-' || ${month}`;
    }

    case "fiscal": {
      return year === undefined || month === undefined
        ? undefined
        : `case when ${month}::int >= ${String(item.fiscalMonth)} then ${year} else ((${year})::int - 1)::text end`;
    }

    default: {
      const never: never = item.period;

      return never;
    }
  }
}

function syncEntity(
  ctx: ModuleContext,
  item: SequenceEntity & { readonly table: string; readonly column: string },
): string {
  const { pattern, groups } = formatPattern(item.format);
  const period = syncPeriod(item, groups);
  const number = groups.get("n");
  const where = `p_entity is null or p_entity = ${sqlString(item.name)}`;

  if (period === undefined || number === undefined) {
    const problem =
      number === undefined
        ? `the ${item.name} format has no {n} to read a number from`
        : `the ${item.name} format holds no period; set options.entities.${item.name}.periodColumn`;

    return `  if ${where} then
    ${fail("NUMBER_SYNC_UNSUPPORTED", problem, "22023")}
  end if;`;
  }

  const table = ctx.table("sequences");
  const tenant = ctx.col("sequences", "tenant");
  const entity = ctx.col("sequences", "entity");
  const periodCol = ctx.col("sequences", "period");
  const last = ctx.col("sequences", "lastNumber");
  const updatedAt = ctx.col("sequences", "updatedAt");
  const owner = `t.${sqlIdent(item.tenantColumn)}`;

  return `  if ${where} then
    insert into ${table} (${tenant}, ${entity}, ${periodCol}, ${last})
    select s.tenant, ${ctx.cast("sequences", "entity", sqlString(item.name))}, s.period, max(s.n)
    from (
      select ${owner} as tenant, ${period} as period, (m.parts[${String(number)}])::bigint as n
      from ${quotedTable(item.table)} t
      cross join lateral regexp_match(t.${sqlIdent(item.column)}::text, ${sqlString(pattern)}) as m(parts)
      where m.parts is not null
        and (p_tenant is null or ${owner} = p_tenant)
    ) s
    where s.tenant is not null and s.period is not null
    group by s.tenant, s.period
    on conflict (${tenant}, ${entity}, ${periodCol})
    do update set ${last} = greatest(${table}.${last}, excluded.${last}), ${updatedAt} = now();
    get diagnostics v_count = row_count;
    v_rows := v_rows + v_count;
  end if;`;
}

function syncFunction(
  ctx: ModuleContext,
  items: readonly SequenceEntity[],
): string {
  const fn = ctx.fn("sync_number_sequences");

  const synced = items.filter(
    (
      item,
    ): item is SequenceEntity & {
      readonly table: string;
      readonly column: string;
    } => item.table !== undefined && item.column !== undefined,
  );

  const known =
    synced.length === 0
      ? "false"
      : `p_entity in (${synced.map((item) => sqlString(item.name)).join(", ")})`;

  return `
-- Raises each sequence to the highest number its table already holds, per
-- tenant and period, for rows numbered outside next_number: seeds, imports
-- and restores. A null tenant or entity syncs every one.
create or replace function ${fn}(p_tenant ${ctx.idType} default null, p_entity text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer := 0;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    ${fail("ACTOR_READ_ONLY", "This session is read-only")}
  end if;
  if p_entity is not null and not (${known}) then
    ${fail("NUMBER_ENTITY_UNKNOWN", "no numbered table for this sequence", "22023")}
  end if;
${synced.map((item) => syncEntity(ctx, item)).join("\n")}
  return v_rows;
end;
$$;
${serviceGrant(`${fn}(${ctx.idType}, text)`)}`;
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

create or replace function better_supabase.number_at(value timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value $$;
create or replace function better_supabase.number_at(value timestamp)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value at time zone 'utc' $$;
create or replace function better_supabase.number_at(value date)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value::timestamp at time zone 'utc' $$;
${serviceGrant("better_supabase.number_at(timestamptz)")}
${serviceGrant("better_supabase.number_at(timestamp)")}
${serviceGrant("better_supabase.number_at(date)")}

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
  values (next_number.tenant, ${ctx.cast("sequences", "entity", "p_entity")}, v_period, 1)
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
${syncFunction(ctx, items)}
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
  v_at timestamptz;
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
  -- A number is assigned here or by the service role, never sent by a client.
  if new.${col} is not null then
    if not (${SERVICE_CALLER}) then
      ${fail("NUMBER_MANUAL", "a number is assigned by the sequence, not set by hand", "42501")}
    end if;
    return new;
  end if;
  if not (${item.assignOn}) then
    return new;
  end if;
  v_at := ${item.periodColumn === undefined ? "now()" : `coalesce(${rowAt(`new.${sqlIdent(item.periodColumn)}`)}, now())`};
  v_n := ${ctx.fn("next_number")}(new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, v_at);
  new.${col} := better_supabase.format_assigned_number(${sqlString(item.format)}, v_n, v_at);
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
