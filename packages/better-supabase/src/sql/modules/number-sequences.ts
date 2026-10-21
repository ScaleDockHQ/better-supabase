import type { NumberSequencesEvents } from "../../blocks/number-sequences/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";
import type {
  SequenceEntity,
  TenantColumn,
} from "./number-sequences-entities.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  quotedTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";
import { sequences } from "./number-sequences-entities.ts";

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

function periodSql(item: SequenceEntity, at: string, format: string): string {
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

    case "format": {
      return `better_supabase.number_format_period(${format}, ${at})`;
    }

    default: {
      const never: never = item.period;

      return never;
    }
  }
}

function periodOf(
  ctx: ModuleContext,
  item: SequenceEntity,
  args: {
    readonly at: string;
    readonly format: string;
    readonly tenant: string;
  },
): string {
  const own = periodSql(item, args.at, args.format);

  if (item.periodFrom === undefined) {
    return own;
  }

  const stamp = `${args.at} at time zone 'utc'`;

  return `case ${ctx.fn("number_period")}(${args.tenant}, ${sqlString(item.name)})
      when 'none' then ''
      when 'year' then to_char(${stamp}, 'YYYY')
      when 'month' then to_char(${stamp}, 'YYYY-MM')
      when 'format' then better_supabase.number_format_period(${args.format}, ${args.at})
      else ${own}
    end`;
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
    return periodSql(
      item,
      rowAt(`t.${sqlIdent(item.periodColumn)}`),
      sqlString(item.format),
    );
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

    case "format": {
      return undefined;
    }

    default: {
      const never: never = item.period;

      return never;
    }
  }
}

function formatOf(
  ctx: ModuleContext,
  item: SequenceEntity,
  tenant: string,
): string {
  return item.formatFrom === undefined
    ? sqlString(item.format)
    : `${ctx.fn("number_format")}(${tenant}, ${sqlString(item.name)})`;
}

interface SyncSource {
  readonly period: string | undefined;
  readonly number: string | undefined;
  readonly match: string | undefined;
}

function syncSource(ctx: ModuleContext, item: SequenceEntity): SyncSource {
  const sequence =
    item.sequenceColumn === undefined
      ? undefined
      : `t.${sqlIdent(item.sequenceColumn)}`;

  const owner = `t.${sqlIdent(item.tenantColumn)}`;
  const format = formatOf(ctx, item, owner);

  const rowPeriod =
    item.periodColumn === undefined
      ? undefined
      : periodOf(ctx, item, {
          at: rowAt(`t.${sqlIdent(item.periodColumn)}`),
          format,
          tenant: owner,
        });

  if (item.formatFrom !== undefined) {
    const period =
      item.periodFrom === undefined && item.period === "none"
        ? "''"
        : rowPeriod;

    return sequence === undefined
      ? {
          period,
          number: "m.parts[1]",
          match: `better_supabase.number_format_pattern(${format})`,
        }
      : { period, number: sequence, match: undefined };
  }

  const { pattern, groups } = formatPattern(item.format);

  const period =
    item.periodFrom === undefined ? syncPeriod(item, groups) : rowPeriod;

  const group = groups.get("n");

  const number =
    sequence ?? (group === undefined ? undefined : `m.parts[${String(group)}]`);

  const parses =
    (period?.includes("m.parts") ?? false) ||
    (number?.startsWith("m.parts") ?? false);

  return { period, number, match: parses ? sqlString(pattern) : undefined };
}

function syncEntity(
  ctx: ModuleContext,
  item: SequenceEntity & { readonly table: string; readonly column: string },
): string {
  const { period, number, match } = syncSource(ctx, item);
  const where = `p_entity is null or p_entity = ${sqlString(item.name)}`;

  if (period === undefined || number === undefined) {
    const problem =
      number === undefined
        ? `the ${item.name} format has no {n} to read a number from`
        : item.periodFrom === undefined
          ? item.formatFrom === undefined
            ? `the ${item.name} format holds no period; set options.entities.${item.name}.periodColumn`
            : `the ${item.name} format is chosen per tenant; set options.entities.${item.name}.periodColumn`
          : `the ${item.name} period is chosen per tenant; set options.entities.${item.name}.periodColumn`;

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

  const join =
    match === undefined
      ? ""
      : `
      cross join lateral regexp_match(t.${sqlIdent(item.column)}::text, ${match}) as m(parts)`;

  const found =
    match === undefined ? `${number} is not null` : "m.parts is not null";

  return `  if ${where} then
    insert into ${table} (${tenant}, ${entity}, ${periodCol}, ${last})
    select s.tenant, ${ctx.cast("sequences", "entity", sqlString(item.name))}, s.period, max(s.n)
    from (
      select ${owner} as tenant, ${period} as period, (${number})::bigint as n
      from ${quotedTable(item.table)} t${join}
      where ${found}
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

function periodCaseOf(
  ctx: ModuleContext,
  items: readonly SequenceEntity[],
  args: {
    readonly tenant: string;
    readonly entity: string;
    readonly at: string;
  },
): string {
  if (items.length === 0) {
    return "''";
  }

  const branches = items.map(
    (item) =>
      `    when ${sqlString(item.name)} then ${periodOf(ctx, item, { at: args.at, format: formatOf(ctx, item, args.tenant), tenant: args.tenant })}`,
  );

  return `case ${args.entity}\n${branches.join("\n")}\n    else null\n  end`;
}

function previewFunction(
  ctx: ModuleContext,
  items: readonly SequenceEntity[],
): string {
  const fn = ctx.fn("preview_number");
  const table = ctx.table("sequences");

  const fallback = ctx.permission(
    "assign",
    OPERATIONS["number-sequences.assign"],
  );

  const own = items.filter((item) => item.permission !== undefined);

  const assign =
    own.length === 0
      ? fallback
      : `case p_entity\n${own.map((item) => `    when ${sqlString(item.name)} then ${sqlString(item.permission ?? "")}`).join("\n")}\n    else ${fallback}\n  end`;

  const format =
    items.length === 0
      ? "'{n}'"
      : `${ctx.fn("number_format")}(p_tenant, p_entity)`;

  const period = periodCaseOf(ctx, items, {
    tenant: "p_tenant",
    entity: "p_entity",
    at: "p_at",
  });

  return `
create or replace function ${fn}(p_tenant ${ctx.idType}, p_entity text, p_at timestamptz default now())
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_last bigint;
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("p_tenant", assign)}) then
    ${fail("NUMBER_FORBIDDEN", "not allowed to number documents in this tenant")}
  end if;
  v_format := ${format};
  v_period := ${period};
  if v_format is null or v_period is null then
    ${fail("NUMBER_ENTITY_UNKNOWN", "unknown number sequence", "22023")}
  end if;
  select s.${ctx.col("sequences", "lastNumber")} into v_last
  from ${table} s
  where s.${ctx.col("sequences", "tenant")} = p_tenant
    and s.${ctx.col("sequences", "entity")} = ${ctx.cast("sequences", "entity", "p_entity")}
    and s.${ctx.col("sequences", "period")} = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$$;
${userGrant(`${fn}(${ctx.idType}, text, timestamptz)`)}`;
}

function formatFunction(
  ctx: ModuleContext,
  items: readonly SequenceEntity[],
): string {
  const fn = ctx.fn("number_format");
  const chosen = items.filter((item) => item.formatFrom !== undefined);

  const branches = items.map((item) => {
    const from = item.formatFrom;

    const value =
      from === undefined
        ? sqlString(item.format)
        : `coalesce((select nullif(btrim(s.${from.column}), '') from ${from.table} s where s.${sqlIdent(from.key)} = p_tenant), ${sqlString(item.format)})`;

    return `    when ${sqlString(item.name)} then ${value}`;
  });

  const resolve =
    branches.length === 0
      ? "null"
      : `case p_entity\n${branches.join("\n")}\n    else null\n  end`;

  const check =
    chosen.length === 0
      ? ""
      : `
  if p_entity in (${chosen.map((item) => sqlString(item.name)).join(", ")}) and v_format !~ '\\{n(:[0-9]+)?\\}' then
    ${fail("NUMBER_FORMAT_INVALID", "the tenant's number format has no {n}", "22023")}
  end if;`;

  return `
create or replace function ${fn}(p_tenant ${ctx.idType}, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
begin
  v_format := ${resolve};${check}
  return v_format;
end;
$$;
${serviceGrant(`${fn}(${ctx.idType}, text)`)}`;
}

function periodFunction(
  ctx: ModuleContext,
  items: readonly SequenceEntity[],
): string {
  const fn = ctx.fn("number_period");

  const branches = items.flatMap((item) => {
    const from = item.periodFrom;

    return from === undefined
      ? []
      : [
          `    when ${sqlString(item.name)} then (select nullif(btrim(s.${from.column}::text), '') from ${from.table} s where s.${sqlIdent(from.key)} = p_tenant)`,
        ];
  });

  const resolve =
    branches.length === 0
      ? "null"
      : `case p_entity\n${branches.join("\n")}\n    else null\n  end`;

  return `
create or replace function ${fn}(p_tenant ${ctx.idType}, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period text;
begin
  v_period := ${resolve};
  if v_period is not null and v_period not in ('none', 'year', 'month', 'format') then
    ${fail("NUMBER_PERIOD_INVALID", "the tenant's number period must be none, year, month or format", "22023")}
  end if;
  return v_period;
end;
$$;
${serviceGrant(`${fn}(${ctx.idType}, text)`)}`;
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

function tenantValue(
  from: TenantColumn,
  row: string | undefined,
  tenant: string,
): string {
  return row === undefined
    ? `(select nullif(btrim(s.${from.column}::text), '') from ${from.table} s where s.${sqlIdent(from.key)} = ${tenant})`
    : `nullif(btrim(${row}.${from.column}::text), '')`;
}

function periodKind(
  item: SequenceEntity,
  values: { readonly period?: string; readonly format: string },
): string {
  const own =
    item.period === "fiscal"
      ? `fiscal:${String(item.fiscalMonth)}`
      : item.period;

  const chosen =
    values.period === undefined
      ? sqlString(own)
      : `coalesce(${values.period}, ${sqlString(own)})`;

  return `better_supabase.number_period_kind(${chosen}, ${values.format})`;
}

function periodTrigger(
  ctx: ModuleContext,
  item: SequenceEntity,
  source: TenantColumn,
  name: string,
): string {
  const tenant = `new.${sqlIdent(source.key)}`;
  const own = (from: TenantColumn): boolean => from.table === source.table;

  const kind = (row: string): string => {
    const format =
      item.formatFrom === undefined
        ? sqlString(item.format)
        : `coalesce(${tenantValue(item.formatFrom, own(item.formatFrom) ? row : undefined, tenant)}, ${sqlString(item.format)})`;

    return periodKind(item, {
      ...(item.periodFrom === undefined
        ? {}
        : {
            period: tenantValue(
              item.periodFrom,
              own(item.periodFrom) ? row : undefined,
              tenant,
            ),
          }),
      format,
    });
  };

  const fn = sqlIdent(name);

  return `
create or replace function better_supabase.${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if ${kind("old")} is distinct from ${kind("new")} then
    perform ${ctx.fn("sync_number_sequences")}(${tenant}, ${sqlString(item.name)});
  end if;
  return null;
end;
$$;
${serviceGrant(`better_supabase.${fn}()`)}
drop trigger if exists ${fn} on ${source.table};
create trigger ${fn} after update on ${source.table}
for each row execute function better_supabase.${fn}();`;
}

function periodTriggers(ctx: ModuleContext, item: SequenceEntity): string {
  if (item.table === undefined || item.column === undefined) {
    return "";
  }

  const varies =
    item.periodFrom !== undefined ||
    (item.formatFrom !== undefined && item.period === "format");

  const { period, number } = syncSource(ctx, item);

  if (!varies || period === undefined || number === undefined) {
    return "";
  }

  const sources = [item.periodFrom, item.formatFrom].filter(
    (from): from is TenantColumn => from !== undefined,
  );

  return sources
    .filter(
      (from, index) =>
        sources.findIndex((other) => other.table === from.table) === index,
    )
    .map((from, index) =>
      periodTrigger(
        ctx,
        item,
        from,
        `bs_sync_number_period_${item.name}${index === 0 ? "" : "_format"}`,
      ),
    )
    .join("\n");
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

  const periodCase = periodCaseOf(ctx, items, {
    tenant: "next_number.tenant",
    entity: "p_entity",
    at: "next_number.at",
  });

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
    .map((item) => `${trigger(ctx, item)}${periodTriggers(ctx, item)}`)
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

create or replace function better_supabase.number_format_period(p_format text, p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_format ~ '\\{yy(yy)?\\}' and p_format ~ '\\{mm\\}' then to_char(p_at at time zone 'utc', 'YYYY-MM')
    when p_format ~ '\\{yy(yy)?\\}' then to_char(p_at at time zone 'utc', 'YYYY')
    else ''
  end
$$;
${serviceGrant("better_supabase.number_format_period(text, timestamptz)")}

create or replace function better_supabase.number_period_kind(p_period text, p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_period <> 'format' then p_period
    when p_format ~ '\\{yy(yy)?\\}' and p_format ~ '\\{mm\\}' then 'month'
    when p_format ~ '\\{yy(yy)?\\}' then 'year'
    else 'none'
  end
$$;
${serviceGrant("better_supabase.number_period_kind(text, text)")}

create or replace function better_supabase.number_format_pattern(p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '^' || replace(replace(replace(
    regexp_replace(
      regexp_replace(
        replace(replace(replace(replace(p_format, '{yyyy}', chr(1)), '{yy}', chr(2)), '{mm}', chr(2)), '{dd}', chr(2)),
        '\\{n(:[0-9]+)?\\}', chr(3), 'g'),
      '([^[:alnum:]\\x01-\\x03])', '\\\\\\1', 'g'),
    chr(1), '[0-9]{4}'), chr(2), '[0-9]{2}'), chr(3), '([0-9]+)') || '$'
$$;
${serviceGrant("better_supabase.number_format_pattern(text)")}

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
  v_period := ${periodCase};
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
${formatFunction(ctx, items)}
${periodFunction(ctx, items)}
${previewFunction(ctx, items)}
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

  const sequence =
    item.sequenceColumn === undefined
      ? undefined
      : sqlIdent(item.sequenceColumn);

  const fn = sqlIdent(`bs_assign_number_${item.name}`);

  const manual = fail(
    "NUMBER_MANUAL",
    "a number is assigned by the sequence, not set by hand",
    "42501",
  );

  const manualSequence =
    sequence === undefined
      ? ""
      : `
  if not (${SERVICE_CALLER}) then
    if tg_op = 'INSERT' then
      if new.${sequence} is not null then
        ${manual}
      end if;
    elsif new.${sequence} is distinct from old.${sequence} then
      ${manual}
    end if;
  end if;`;

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
    if new.${col} is distinct from old.${col}${sequence === undefined ? "" : ` or new.${sequence} is distinct from old.${sequence}`} then
      ${fail("NUMBER_IMMUTABLE", "a number cannot change", "22023")}
    end if;
    return new;
  end if;
  -- A number is assigned here or by the service role, never sent by a client.${manualSequence}
  if new.${col} is not null then
    if not (${SERVICE_CALLER}) then
      ${manual}
    end if;
    return new;
  end if;
  if not (${item.assignOn}) then
    return new;
  end if;
  v_at := ${item.periodColumn === undefined ? "now()" : `coalesce(${rowAt(`new.${sqlIdent(item.periodColumn)}`)}, now())`};
  v_n := ${ctx.fn("next_number")}(new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, v_at);
  new.${col} := better_supabase.format_assigned_number(${formatOf(ctx, item, `new.${sqlIdent(item.tenantColumn)}`)}, v_n, v_at);${
    sequence === undefined
      ? ""
      : `
  new.${sequence} := v_n;`
  }
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
    {
      name: "preview_number",
      args: ["{id}", "text", "timestamptz"],
      returns: "text",
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
  permissionKeys: (ctx) =>
    sequences(ctx).flatMap((item) =>
      item.permission === undefined
        ? []
        : [
            {
              action: "assign",
              key: item.permission,
              scope: "tenant",
              setting: `blocks.number-sequences.options.entities.${item.name}.permission`,
            },
          ],
    ),
};
