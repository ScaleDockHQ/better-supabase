import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  quotedTable,
  schemaPreamble,
  SERVICE_CALLER,
  tenantIn,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["meters", "history"],
  hooks: ["usage_billing_period"],
  tables: {
    counters: {
      name: "usage_counters",
      lifecycle: { tenant: "tenant" },
      columns: {
        tenant: "organization_id",
        meter: "meter",
        day: "day",
        value: "value",
        reported: "reported_value",
        updatedAt: "updated_at",
      },
    },
    events: {
      name: "usage_events",
      lifecycle: { tenant: "tenant" },
      columns: {
        tenant: "organization_id",
        meter: "meter",
        key: "idempotency_key",
        quantity: "quantity",
        recordedAt: "recorded_at",
      },
    },
    history: {
      name: "usage_history",
      lifecycle: { user: "actor", tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        meter: "meter",
        quantity: "quantity",
        actor: "actor_id",
        source: "source",
        metadata: "metadata",
        recordedAt: "recorded_at",
      },
    },
    quotas: {
      name: "usage_quotas",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        plan: "plan",
        meter: "meter",
        limit: "limit",
        period: "period",
        createdAt: "created_at",
      },
    },
  },
};

const METER = `'^[a-z][a-z0-9_.:-]{0,63}$'`;
const METER_KEY = /^[a-z][a-z0-9_.:-]{0,63}$/;

/** One meter in `options.meters`: how to show it. */
export interface UsageMeter {
  /** What one unit is, such as `tokens`, `requests` or `bytes`. */
  readonly unit?: string;
  /** A group for display, such as `ai` or `storage`. */
  readonly category?: string;
  readonly label?: string;
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** `options.meters` as a table: the app's own meter catalog. */
interface MeterTable {
  readonly table: string;
  readonly key: string;
  readonly unit?: string;
  readonly category?: string;
  readonly label?: string;
  /** A boolean column; only rows where it is true are meters. */
  readonly active?: string;
}

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

function meterTableOf(
  where: string,
  option: Record<string, unknown>,
): MeterTable {
  const text = (name: string): string | undefined => {
    const value = option[name];
    if (value === undefined) return undefined;
    if (
      typeof value !== "string" ||
      !value.split(".").every((part) => IDENT.test(part))
    ) {
      throw new TypeError(`${where}.${name} must be a lowercase identifier`);
    }
    return value;
  };
  for (const name of Object.keys(option)) {
    if (
      !["table", "key", "unit", "category", "label", "active"].includes(name)
    ) {
      throw new TypeError(
        `${where}: a table catalog takes table, key, unit, category, label and active, not ${name}`,
      );
    }
  }
  const table = text("table")!;
  if (table.split(".").length > 2) {
    throw new TypeError(`${where}.table must be "table" or "schema.table"`);
  }
  const optional = (name: "unit" | "category" | "label" | "active") => {
    const value = text(name);
    return value === undefined ? {} : { [name]: value };
  };
  return {
    table,
    key: text("key") ?? "key",
    ...optional("unit"),
    ...optional("category"),
    ...optional("label"),
    ...optional("active"),
  };
}

const isMeterTable = (
  value: Readonly<Record<string, UsageMeter>> | MeterTable,
): value is MeterTable => "table" in value && typeof value.table === "string";

const qualifiedTable = (table: string): string => quotedTable(table);

/**
 * `options.meters`: the meter catalog, inline or `{ table }` for one the app
 * keeps in a table; with either, unknown meters are refused.
 */
function metersOf(
  ctx: ModuleContext,
): Readonly<Record<string, UsageMeter>> | MeterTable | undefined {
  const where = "sql.modules.usage.options.meters";
  const option = ctx.option("meters");
  if (option === undefined) return undefined;
  if (isObject(option) && typeof option["table"] === "string") {
    return meterTableOf(where, option);
  }
  const out: Record<string, UsageMeter> = {};
  if (!isObject(option)) {
    throw new TypeError(
      `${where} must be an object of meter to { unit?, category?, label? }`,
    );
  }
  for (const [meter, value] of Object.entries(option)) {
    if (!METER_KEY.test(meter)) {
      throw new TypeError(`${where}: "${meter}" is not a meter name`);
    }
    if (!isObject(value)) {
      throw new TypeError(`${where}.${meter} must be an object`);
    }
    const entry: Record<string, string> = {};
    for (const [key, text] of Object.entries(value)) {
      if (
        !["unit", "category", "label"].includes(key) ||
        typeof text !== "string"
      ) {
        throw new TypeError(
          `${where}.${meter}.${key}: use unit, category and label as strings`,
        );
      }
      entry[key] = text;
    }
    out[meter] = entry;
  }
  return out;
}

function build(ctx: ModuleContext, layout: ModuleLayout): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const counters = ctx.table("counters");
  const events = ctx.table("events");
  const quotas = ctx.table("quotas");
  const cc = (logical: string): string => ctx.col("counters", logical);
  const ec = (logical: string): string => ctx.col("events", logical);
  const qc = (logical: string): string => ctx.col("quotas", logical);
  const history = ctx.table("history");
  const hc = (logical: string): string => ctx.col("history", logical);
  const keepHistory = ctx.flag("history", false);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = MODULE_PERMISSIONS.usage;
  const canRead = (tenant: string): string =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission("read", permissions.read)}), false))`;
  const readPolicy = (tenant: string): string =>
    tenantIn(tenant, ctx.permission("read", permissions.read));
  const member = (tenant: string): string =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.has_organization_role(${tenant}), false))`;
  const canRecord = (tenant: string): string =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission("record", permissions.record)}), false))`;
  // used is the quota period's usage, as usage_status reports it; today the UTC day's.
  const outcome = (recorded: "true" | "false"): string =>
    `jsonb_build_object('recorded', ${recorded}, 'used', ${fn("usage_used")}(tenant, meter, coalesce((select q.period from ${fn("usage_quota")}(tenant, meter) q), 'month')), 'today', ${fn("usage_used")}(tenant, meter, 'day'))`;
  // Plan quotas apply to tenants with that entitlement key, to tenants on that
  // plan key when entitlements read a plan catalog, or to every tenant with
  // plan '*'.
  const meters = metersOf(ctx);
  const table =
    meters !== undefined && isMeterTable(meters) ? meters : undefined;
  const catalog =
    table === undefined
      ? `${sqlString(JSON.stringify(meters ?? {}))}::jsonb`
      : `(select coalesce(jsonb_object_agg(m.${sqlIdent(table.key)}::text, jsonb_strip_nulls(jsonb_build_object(${(
          ["unit", "category", "label"] as const
        )
          .flatMap((name) => {
            const column = table[name];
            return column === undefined
              ? []
              : [`'${name}', m.${sqlIdent(column)}::text`];
          })
          .join(", ")}))), '{}'::jsonb)
    from ${qualifiedTable(table.table)} m${table.active ? ` where m.${sqlIdent(table.active)}` : ""})`;
  const meterCheck = meters
    ? `
  if not (${fn("usage_meters")}() ? meter) then
    raise exception 'Unknown meter %', meter using errcode = '22023', hint = 'USAGE_METER_UNKNOWN';
  end if;`
    : "";
  const billingHook = sqlString(
    `${ctx.hookTarget("usage_billing_period")}(${id})`,
  );
  const periodCheck = `${qc("period")} in ('day', 'week', 'month', 'year', 'billing')`;
  const quotaNames = ctx.tableName("quotas");
  const periodConstraint = sqlIdent(
    `${quotaNames.name}_${qc("period").replaceAll('"', "")}_check`,
  );
  const planKeys =
    typeof layout.entitlements?.source === "object"
      ? ` or q.${qc("plan")} = any (better_supabase.tenant_plans(tenant))`
      : "";
  const planMatches = ctx.installed("entitlements")
    ? `q.${qc("plan")} = '*' or q.${qc("plan")} = any (better_supabase.tenant_entitlements(tenant))${planKeys}`
    : `q.${qc("plan")} = '*'`;

  return `${schemaPreamble(ctx)}
-- Usage per tenant, meter and UTC day. Quotas sum the days of their period.
create table if not exists ${counters} (
  ${cc("tenant")} ${id} not null,
  ${cc("meter")} text not null check (${cc("meter")} ~ ${METER}),
  ${cc("day")} date not null,
  ${cc("value")} numeric not null default 0 check (${cc("value")} >= 0),
  ${cc("reported")} numeric not null default 0 check (${cc("reported")} >= 0),
  ${cc("updatedAt")} timestamptz not null default now(),
  primary key (${cc("tenant")}, ${cc("meter")}, ${cc("day")})
);
-- Quantities are numeric, so a meter can count fractions (GB-hours, credits).
alter table ${counters} alter column ${cc("value")} type numeric;
alter table ${counters} alter column ${cc("reported")} type numeric;
create index if not exists usage_counters_unreported_idx on ${counters} (${cc("day")})
  where ${cc("value")} > ${cc("reported")};
alter table ${counters} enable row level security;
revoke all on ${counters} from anon, authenticated;
grant select on ${counters} to authenticated;
grant all on ${counters} to service_role;
drop policy if exists "usage_counters_read" on ${counters};
create policy "usage_counters_read" on ${counters} for select to authenticated
  using (${readPolicy(cc("tenant"))});

-- One row per idempotency key, so a retried increment counts once.
create table if not exists ${events} (
  ${ec("tenant")} ${id} not null,
  ${ec("meter")} text not null,
  ${ec("key")} text not null,
  ${ec("quantity")} numeric not null,
  ${ec("recordedAt")} timestamptz not null default now(),
  primary key (${ec("tenant")}, ${ec("meter")}, ${ec("key")})
);
alter table ${events} alter column ${ec("quantity")} type numeric;
${
  keepHistory
    ? `
-- options.history: one row per recorded quantity, with who (actor_id) and
-- what (source, metadata) used it, for a usage page.
create table if not exists ${history} (
  ${hc("id")} bigint generated always as identity primary key,
  ${hc("tenant")} ${id} not null,
  ${hc("meter")} text not null,
  ${hc("quantity")} numeric not null,
  ${hc("actor")} uuid,
  ${hc("source")} text check (length(${hc("source")}) <= 200),
  ${hc("metadata")} jsonb not null default '{}',
  ${hc("recordedAt")} timestamptz not null default now()
);
create index if not exists usage_history_tenant_idx on ${history} (${hc("tenant")}, ${hc("recordedAt")} desc, ${hc("id")} desc);
alter table ${history} enable row level security;
revoke all on ${history} from anon, authenticated;
grant select on ${history} to authenticated;
grant all on ${history} to service_role;
drop policy if exists "usage_history_read" on ${history};
create policy "usage_history_read" on ${history} for select to authenticated
  using (${readPolicy(hc("tenant"))});
`
    : ""
}
create index if not exists usage_events_recorded_at_idx on ${events} (${ec("recordedAt")});
alter table ${events} enable row level security;
revoke all on ${events} from anon, authenticated;
grant all on ${events} to service_role;

-- A tenant row overrides the plan rows; of several plan rows the highest
-- limit wins. A null limit is unlimited, so it wins over every limit.
create table if not exists ${quotas} (
  ${qc("id")} uuid primary key default gen_random_uuid(),
  ${qc("tenant")} ${id},
  ${qc("plan")} text,
  ${qc("meter")} text not null check (${qc("meter")} ~ ${METER}),
  ${qc("limit")} numeric check (${qc("limit")} >= 0),
  ${qc("period")} text not null default 'month' check (${periodCheck}),
  ${qc("createdAt")} timestamptz not null default now(),
  check ((${qc("tenant")} is null) <> (${qc("plan")} is null)),
  unique nulls not distinct (${qc("tenant")}, ${qc("plan")}, ${qc("meter")})
);
alter table ${quotas} alter column ${qc("limit")} type numeric;
alter table ${quotas} alter column ${qc("limit")} drop not null;
alter table ${quotas} drop constraint if exists ${periodConstraint};
alter table ${quotas} add constraint ${periodConstraint} check (${periodCheck});
alter table ${quotas} enable row level security;
revoke all on ${quotas} from anon, authenticated;
grant select on ${quotas} to authenticated;
grant all on ${quotas} to service_role;
drop policy if exists "usage_quotas_read" on ${quotas};
create policy "usage_quotas_read" on ${quotas} for select to authenticated
  using (${qc("tenant")} is null or ${readPolicy(qc("tenant"))});

-- The bigint signatures and return types before quantities were numeric.
drop function if exists ${fn("usage_quota")}(${id}, text);
drop function if exists ${fn("usage_used")}(${id}, text, text);
drop function if exists ${fn("record_usage")}(${id}, text, bigint, text);
drop function if exists ${fn("consume_quota")}(${id}, text, bigint, text);
drop function if exists ${fn("mark_usage_reported")}(${id}, text, date, bigint);
-- The signatures before usage carried a source, metadata and actor.
drop function if exists ${fn("record_usage")}(${id}, text, numeric, text);
drop function if exists ${fn("consume_quota")}(${id}, text, numeric, text);
-- The signature before the report could skip meters and tenants.
drop function if exists ${fn("unreported_usage")}(integer);

-- The quota that applies to tenant and meter, or no row. An unlimited quota
-- is a row with a null quota_limit.
create or replace function ${fn("usage_quota")}(tenant ${id}, meter text)
returns table (quota_limit numeric, period text)
language sql
stable
security definer
set search_path = ''
as $$
  select q.${qc("limit")}, q.${qc("period")}
  from ${quotas} q
  where q.${qc("meter")} = usage_quota.meter
    and (q.${qc("tenant")} = usage_quota.tenant or (q.${qc("tenant")} is null and (${planMatches})))
  order by (q.${qc("tenant")} is not null) desc, q.${qc("limit")} desc nulls first
  limit 1
$$;

-- The window of a period for tenant: the current UTC day, week, month or
-- year, or with 'billing' the app's usage_billing_period(tenant) (the
-- subscription's current period, say), falling back to the month.
create or replace function ${fn("usage_window")}(tenant ${id}, period text default 'month')
returns table (starts_at timestamptz, ends_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period text := coalesce(usage_window.period, 'month');
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_period = 'billing' then
    if to_regprocedure(${billingHook}) is not null then
      -- Not a literal name, so plpgsql_check passes without the hook.
      execute format('select h.starts_at, h.ends_at from %s($1) h', to_regprocedure(${billingHook})::oid::regproc)
        into v_start, v_end using usage_window.tenant;
    end if;
    if v_start is null or v_end is null or v_end <= v_start then
      v_period := 'month';
      v_start := null;
    end if;
  end if;
  if v_start is null then
    v_start := date_trunc(v_period, now() at time zone 'utc') at time zone 'utc';
    v_end := v_start + ('1 ' || v_period)::interval;
  end if;
  return query select v_start, v_end;
end;
$$;

-- The first UTC day of the window of period that holds day, which can be
-- in an earlier window than now. Earlier billing periods are assumed to be as
-- long as the current one; past 120 of them it falls back to the month.
create or replace function ${fn("usage_window_start")}(tenant ${id}, period text, day date)
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_length interval;
  v_steps integer := 0;
begin
  if usage_window_start.period is null then
    return usage_window_start.day;
  end if;
  if usage_window_start.period <> 'billing' then
    return date_trunc(usage_window_start.period, usage_window_start.day)::date;
  end if;
  select w.starts_at, w.ends_at into v_start, v_end
  from ${fn("usage_window")}(usage_window_start.tenant, 'billing') w;
  v_length := age(v_end, v_start);
  while usage_window_start.day < (v_start at time zone 'utc')::date and v_steps < 120 loop
    v_start := v_start - v_length;
    v_steps := v_steps + 1;
  end loop;
  if usage_window_start.day < (v_start at time zone 'utc')::date then
    return date_trunc('month', usage_window_start.day)::date;
  end if;
  return (v_start at time zone 'utc')::date;
end;
$$;

-- Usage of meter in the current window of period, counted by UTC day.
create or replace function ${fn("usage_used")}(tenant ${id}, meter text, period text default 'month')
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(c.${cc("value")}), 0)::numeric
  from ${counters} c, ${fn("usage_window")}(usage_used.tenant, usage_used.period) w
  where c.${cc("tenant")} = usage_used.tenant
    and c.${cc("meter")} = usage_used.meter
    and c.${cc("day")} >= (w.starts_at at time zone 'utc')::date
    and c.${cc("day")} < greatest((w.ends_at at time zone 'utc')::date, (w.starts_at at time zone 'utc')::date + 1)
$$;

-- The meter catalog (options.meters): meter to { unit, category, label }.
create or replace function ${fn("usage_meters")}()
returns jsonb
language sql
${table === undefined ? "immutable" : "stable\nsecurity definer"}
set search_path = ''
as $$
  select ${catalog}
$$;

-- { meter, used, limit, remaining, unlimited, period, resets_at }; limit and
-- remaining are null without a quota and for an unlimited one. Needs usage.read,
-- like usage_overview.
create or replace function ${fn("usage_status")}(tenant ${id}, meter text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quota record;
  used numeric;
  win record;
begin
  if not ${canRead("tenant")} then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  select * into quota from ${fn("usage_quota")}(tenant, meter);
  select * into win from ${fn("usage_window")}(tenant, coalesce(quota.period, 'month'));
  used := ${fn("usage_used")}(tenant, meter, coalesce(quota.period, 'month'));
  return jsonb_build_object(
    'meter', meter,
    'used', used,
    'limit', quota.quota_limit,
    'remaining', case when quota.quota_limit is null then null else greatest(quota.quota_limit - used, 0) end,
    'unlimited', quota.period is not null and quota.quota_limit is null,
    'period', coalesce(quota.period, 'month'),
    'resets_at', win.ends_at,
    'starts_at', win.starts_at
  ) || coalesce(${fn("usage_meters")}() -> meter, '{}'::jsonb);
end;
$$;

create or replace function ${fn("usage_overview")}(tenant ${id})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${canRead("tenant")} then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(${fn("usage_status")}(usage_overview.tenant, m.meter) order by m.meter), '[]'::jsonb)
    from (
      select jsonb_object_keys(${fn("usage_meters")}()) as meter
      union
      select q.${qc("meter")} from ${quotas} q
      where q.${qc("tenant")} = usage_overview.tenant
        or (q.${qc("tenant")} is null and (${planMatches.replaceAll("(tenant)", "(usage_overview.tenant)")}))
      union
      select distinct c.${cc("meter")} from ${counters} c
      where c.${cc("tenant")} = usage_overview.tenant
    ) m
  );
end;
$$;

-- For policies: whether quantity more fits the tenant's quota. False for a
-- caller outside the tenant, so it can't probe another tenant's usage.
--   with check (better_supabase.within_quota(organization_id, 'projects'))
create or replace function ${fn("within_quota")}(tenant ${id}, meter text, quantity bigint default 1)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quota record;
begin
  if not ${member("tenant")} then
    return false;
  end if;
  select * into quota from ${fn("usage_quota")}(tenant, meter);
  if quota.quota_limit is null then
    return true;
  end if;
  return ${fn("usage_used")}(tenant, meter, quota.period) + quantity <= quota.quota_limit;
end;
$$;

-- Adds quantity once per idempotency key, for usage.record or the service
-- role. Returns { recorded, used, today }: recorded is false for a key seen
-- before, used is the usage in the quota's period and today the UTC day's. With options.history, also keeps
-- who (the caller, or actor for the service role) and what (source,
-- metadata) used it.
create or replace function ${fn("record_usage")}(
  tenant ${id},
  meter text,
  quantity numeric default 1,
  idempotency_key text default null,
  source text default null,
  metadata jsonb default null,
  actor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  today date := (now() at time zone 'utc')::date;
begin
  if not ${canRecord("tenant")} then
    raise exception 'Not allowed to record usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  if quantity is null or quantity < 0 then
    raise exception 'quantity must be zero or more' using errcode = '22023', hint = 'USAGE_QUANTITY';
  end if;${meterCheck}
  if idempotency_key is not null then
    insert into ${events} (${ec("tenant")}, ${ec("meter")}, ${ec("key")}, ${ec("quantity")})
    values (tenant, meter, idempotency_key, quantity)
    on conflict do nothing;
    if not found then
      return ${outcome("false")};
    end if;
  end if;
  insert into ${counters} as c (${cc("tenant")}, ${cc("meter")}, ${cc("day")}, ${cc("value")})
  values (tenant, meter, today, quantity)
  on conflict (${cc("tenant")}, ${cc("meter")}, ${cc("day")}) do update
    set ${cc("value")} = c.${cc("value")} + excluded.${cc("value")}, ${cc("updatedAt")} = now();${
      keepHistory
        ? `
  insert into ${history} (${hc("tenant")}, ${hc("meter")}, ${hc("quantity")}, ${hc("actor")}, ${hc("source")}, ${hc("metadata")})
  values (tenant, meter, quantity,
    case when ${SERVICE_CALLER} then coalesce(record_usage.actor, auth.uid()) else auth.uid() end,
    record_usage.source, coalesce(record_usage.metadata, '{}'));`
        : ""
    }
  return ${outcome("true")};
end;
$$;

-- Like record_usage, but first checks the quota and raises quota_exceeded
-- (SQLSTATE BSQ29) without recording when quantity does not fit. A transaction
-- lock per tenant and meter, not today's counter row, serializes the calls, so
-- calls on either side of UTC midnight cannot both take the last unit.
create or replace function ${fn("consume_quota")}(
  tenant ${id},
  meter text,
  quantity numeric default 1,
  idempotency_key text default null,
  source text default null,
  metadata jsonb default null,
  actor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  quota record;
  used numeric;
  win record;
begin
  if not ${canRecord("tenant")} then
    raise exception 'Not allowed to record usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;${meterCheck}
  perform pg_advisory_xact_lock(hashtext('better_supabase.consume_quota'), hashtext(tenant::text || '/' || meter));
  if idempotency_key is not null and exists (
    select 1 from ${events} e
    where e.${ec("tenant")} = consume_quota.tenant and e.${ec("meter")} = consume_quota.meter and e.${ec("key")} = consume_quota.idempotency_key
  ) then
    return ${outcome("false")};
  end if;
  select * into quota from ${fn("usage_quota")}(tenant, meter);
  if quota.quota_limit is not null then
    used := ${fn("usage_used")}(tenant, meter, quota.period);
    if used + quantity > quota.quota_limit then
      select * into win from ${fn("usage_window")}(tenant, quota.period);
      raise exception 'Quota for % exceeded', meter using
        errcode = 'BSQ29',
        hint = 'QUOTA_EXCEEDED',
        detail = jsonb_build_object(
          'meter', meter,
          'limit', quota.quota_limit,
          'used', used,
          'retry_after', greatest(1, ceil(extract(epoch from win.ends_at - now()))::integer)
        )::text;
    end if;
  end if;
  return ${fn("record_usage")}(tenant, meter, quantity, idempotency_key, source, metadata, actor);
end;
$$;

-- Records several meters at once, all or none: entries is [{ meter, quantity }],
-- each checked against its quota first when check is true (a quota_exceeded
-- on one records nothing). idempotency_key is per batch. Returns { recorded,
-- used: { meter: usage in its quota period }, today: { meter: today's usage } }.
create or replace function ${fn("record_usage_batch")}(
  tenant ${id},
  entries jsonb,
  idempotency_key text default null,
  "check" boolean default false,
  source text default null,
  metadata jsonb default null,
  actor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry jsonb;
  outcome jsonb;
  recorded boolean := false;
  used jsonb := '{}';
  today_used jsonb := '{}';
begin
  -- A JSON text of the array, as a transport that sends arrays as text passes it.
  if jsonb_typeof(entries) = 'string' then
    entries := (entries #>> '{}')::jsonb;
  end if;
  if jsonb_typeof(entries) <> 'array' or jsonb_array_length(entries) = 0 then
    raise exception 'entries must be a non-empty array of { meter, quantity }' using errcode = '22023', hint = 'USAGE_ENTRIES';
  end if;
  for entry in select value from jsonb_array_elements(entries) loop
    if jsonb_typeof(entry -> 'meter') <> 'string' then
      raise exception 'Every entry needs a meter' using errcode = '22023', hint = 'USAGE_ENTRIES';
    end if;
    if record_usage_batch."check" then
      outcome := ${fn("consume_quota")}(tenant, entry ->> 'meter', coalesce((entry ->> 'quantity')::numeric, 1),
        case when idempotency_key is null then null else idempotency_key || ':' || (entry ->> 'meter') end,
        source, metadata, actor);
    else
      outcome := ${fn("record_usage")}(tenant, entry ->> 'meter', coalesce((entry ->> 'quantity')::numeric, 1),
        case when idempotency_key is null then null else idempotency_key || ':' || (entry ->> 'meter') end,
        source, metadata, actor);
    end if;
    recorded := recorded or (outcome ->> 'recorded')::boolean;
    used := used || jsonb_build_object(entry ->> 'meter', outcome -> 'used');
    today_used := today_used || jsonb_build_object(entry ->> 'meter', outcome -> 'today');
  end loop;
  return jsonb_build_object('recorded', recorded, 'used', used, 'today', today_used);
end;
$$;

-- Server-side, for reportUsageToStripe: counters with unreported usage, with
-- the quota that includes some of it (included, null without a quota) and the
-- usage of the earlier days of that quota's window (window_before), so the
-- report can send only the overage. skip_meters and skip_tenants leave out
-- counters the report can't send yet, so they don't fill every batch.
create or replace function ${fn("unreported_usage")}(
  max_rows integer default 500,
  skip_meters text[] default '{}',
  skip_tenants ${id}[] default '{}'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id', c.${cc("tenant")},
    'meter', c.${cc("meter")},
    'day', c.${cc("day")},
    'value', c.${cc("value")},
    'reported_value', c.${cc("reported")},
    'included', q.quota_limit,
    'unlimited', q.period is not null and q.quota_limit is null,
    'window_before', (
      select coalesce(sum(o.${cc("value")}), 0)
      from ${counters} o
      where o.${cc("tenant")} = c.${cc("tenant")} and o.${cc("meter")} = c.${cc("meter")}
        and o.${cc("day")} < c.${cc("day")}
        and o.${cc("day")} >= w.since
    )
  ) order by c.${cc("day")}, c.${cc("meter")}), '[]'::jsonb)
  from (
    select * from ${counters} c
    where c.${cc("value")} > c.${cc("reported")}
      and c.${cc("meter")} <> all (coalesce(unreported_usage.skip_meters, '{}'))
      and c.${cc("tenant")} <> all (coalesce(unreported_usage.skip_tenants, '{}'))
    order by c.${cc("day")}
    limit max_rows
  ) c
  left join lateral ${fn("usage_quota")}(c.${cc("tenant")}, c.${cc("meter")}) q on true
  cross join lateral (
    select ${fn("usage_window_start")}(c.${cc("tenant")}, q.period, c.${cc("day")}) as since
  ) w
$$;

-- Marks a counter as reported up to value; never moves it backwards.
create or replace function ${fn("mark_usage_reported")}(tenant ${id}, meter text, day date, value numeric)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update ${counters} c set ${cc("reported")} = greatest(c.${cc("reported")}, mark_usage_reported.value)
    where c.${cc("tenant")} = mark_usage_reported.tenant
      and c.${cc("meter")} = mark_usage_reported.meter
      and c.${cc("day")} = mark_usage_reported.day
    returning 1
  )
  select exists (select 1 from updated)
$$;

-- A tenant's usage history, newest first, of one meter when given, before
-- before_id for the next page. [] without options.history. Needs usage.read.
create or replace function ${fn("usage_history")}(tenant ${id}, meter text default null, max_rows integer default 100, before_id bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${canRead("tenant")} then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  ${
    keepHistory
      ? `return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', h.${hc("id")}, 'meter', h.${hc("meter")}, 'quantity', h.${hc("quantity")},
      'actor', h.${hc("actor")}, 'source', h.${hc("source")}, 'metadata', h.${hc("metadata")},
      'recorded_at', h.${hc("recordedAt")}
    ) order by h.${hc("id")} desc), '[]'::jsonb)
    from (
      select * from ${history} h
      where h.${hc("tenant")} = usage_history.tenant
        and (usage_history.meter is null or h.${hc("meter")} = usage_history.meter)
        and (before_id is null or h.${hc("id")} < before_id)
      order by h.${hc("id")} desc
      limit least(greatest(coalesce(max_rows, 100), 1), 1000)
    ) h
  );`
      : "return '[]'::jsonb;"
  }
end;
$$;

-- Who and what used a meter in the current window of its quota period:
-- [{ actor, source, quantity }], largest first. [] without options.history.
create or replace function ${fn("usage_breakdown")}(tenant ${id}, meter text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quota record;
  win record;
begin
  if not ${canRead("tenant")} then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  select * into quota from ${fn("usage_quota")}(tenant, meter);
  select * into win from ${fn("usage_window")}(tenant, coalesce(quota.period, 'month'));
  ${
    keepHistory
      ? `return (
    select coalesce(jsonb_agg(jsonb_build_object('actor', b.actor, 'source', b.source, 'quantity', b.quantity) order by b.quantity desc), '[]'::jsonb)
    from (
      select h.${hc("actor")} as actor, h.${hc("source")} as source, sum(h.${hc("quantity")}) as quantity
      from ${history} h
      where h.${hc("tenant")} = usage_breakdown.tenant and h.${hc("meter")} = usage_breakdown.meter
        and h.${hc("recordedAt")} >= win.starts_at and h.${hc("recordedAt")} < win.ends_at
      group by 1, 2
    ) b
  );`
      : "return '[]'::jsonb;"
  }
end;
$$;

-- Deletes up to batch history rows older than older_than; returns how many.
create or replace function ${fn("purge_usage_history")}(older_than interval default '400 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
${
  keepHistory
    ? `declare
  purged integer;
begin
  with gone as (
    delete from ${history} where ${hc("id")} in (
      select h.${hc("id")} from ${history} h
      where h.${hc("recordedAt")} < now() - older_than
      order by h.${hc("id")} limit batch
    )
    returning 1
  )
  select count(*)::integer into purged from gone;
  return purged;
end;`
    : `begin
  return 0;
end;`
}
$$;

-- Deletes up to batch idempotency keys older than older_than; returns how
-- many. A retry with a purged key counts again, so keep them longer than
-- any client retries.
create or replace function ${fn("purge_usage_events")}(older_than interval default '30 days', batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from ${events} x
    where (x.${ec("tenant")}, x.${ec("meter")}, x.${ec("key")}) in (
      select e.${ec("tenant")}, e.${ec("meter")}, e.${ec("key")} from ${events} e
      where e.${ec("recordedAt")} < now() - coalesce(older_than, '30 days')
      order by e.${ec("recordedAt")} limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$$;

revoke execute on function ${fn("usage_history")}(${id}, text, integer, bigint) from public, anon;
revoke execute on function ${fn("usage_breakdown")}(${id}, text) from public, anon;
revoke execute on function ${fn("purge_usage_history")}(interval, integer) from public, anon, authenticated;
grant execute on function ${fn("usage_history")}(${id}, text, integer, bigint) to authenticated, service_role;
grant execute on function ${fn("usage_breakdown")}(${id}, text) to authenticated, service_role;
grant execute on function ${fn("purge_usage_history")}(interval, integer) to service_role;
revoke execute on function ${fn("purge_usage_events")}(interval, integer) from public, anon, authenticated;
grant execute on function ${fn("purge_usage_events")}(interval, integer) to service_role;
revoke execute on function ${fn("usage_window")}(${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("usage_meters")}() from public;
grant execute on function ${fn("usage_window")}(${id}, text) to service_role;
revoke execute on function ${fn("usage_window_start")}(${id}, text, date) from public, anon, authenticated;
grant execute on function ${fn("usage_window_start")}(${id}, text, date) to service_role;
grant execute on function ${fn("usage_meters")}() to anon, authenticated, service_role;
revoke execute on function ${fn("usage_quota")}(${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("usage_used")}(${id}, text, text) from public, anon, authenticated;
revoke execute on function ${fn("usage_status")}(${id}, text) from public, anon;
revoke execute on function ${fn("usage_overview")}(${id}) from public, anon;
grant execute on function ${fn("usage_overview")}(${id}) to authenticated, service_role;
revoke execute on function ${fn("within_quota")}(${id}, text, bigint) from public, anon;
revoke execute on function ${fn("record_usage")}(${id}, text, numeric, text, text, jsonb, uuid) from public, anon;
revoke execute on function ${fn("consume_quota")}(${id}, text, numeric, text, text, jsonb, uuid) from public, anon;
revoke execute on function ${fn("record_usage_batch")}(${id}, jsonb, text, boolean, text, jsonb, uuid) from public, anon;
grant execute on function ${fn("record_usage_batch")}(${id}, jsonb, text, boolean, text, jsonb, uuid) to authenticated, service_role;
revoke execute on function ${fn("unreported_usage")}(integer, text[], ${id}[]) from public, anon, authenticated;
revoke execute on function ${fn("mark_usage_reported")}(${id}, text, date, numeric) from public, anon, authenticated;
grant execute on function ${fn("usage_quota")}(${id}, text) to service_role;
grant execute on function ${fn("usage_used")}(${id}, text, text) to service_role;
grant execute on function ${fn("usage_status")}(${id}, text) to authenticated, service_role;
grant execute on function ${fn("within_quota")}(${id}, text, bigint) to authenticated, service_role;
grant execute on function ${fn("record_usage")}(${id}, text, numeric, text, text, jsonb, uuid) to authenticated, service_role;
grant execute on function ${fn("consume_quota")}(${id}, text, numeric, text, text, jsonb, uuid) to authenticated, service_role;
grant execute on function ${fn("unreported_usage")}(integer, text[], ${id}[]) to service_role;
grant execute on function ${fn("mark_usage_reported")}(${id}, text, date, numeric) to service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "usage_status", args: ["{id}", "text"], returns: "jsonb" },
    { name: "usage_overview", args: ["{id}"], returns: "jsonb" },
    { name: "usage_meters", args: [], returns: "jsonb" },
    { name: "usage_window", args: ["{id}", "text"], returns: "record" },
    {
      name: "usage_window_start",
      args: ["{id}", "text", "date"],
      returns: "date",
    },
    {
      name: "within_quota",
      args: ["{id}", "text", "bigint"],
      returns: "boolean",
    },
    {
      name: "record_usage",
      args: ["{id}", "text", "numeric", "text", "text", "jsonb", "uuid"],
      returns: "jsonb",
    },
    {
      name: "consume_quota",
      args: ["{id}", "text", "numeric", "text", "text", "jsonb", "uuid"],
      returns: "jsonb",
    },
    {
      name: "record_usage_batch",
      args: ["{id}", "jsonb", "text", "boolean", "text", "jsonb", "uuid"],
      returns: "jsonb",
    },
    {
      name: "unreported_usage",
      args: ["integer", "text[]", "{id}[]"],
      returns: "jsonb",
    },
    {
      name: "usage_history",
      args: ["{id}", "text", "integer", "bigint"],
      returns: "jsonb",
    },
    { name: "usage_breakdown", args: ["{id}", "text"], returns: "jsonb" },
    {
      name: "mark_usage_reported",
      args: ["{id}", "text", "date", "numeric"],
      returns: "boolean",
    },
  ];
}

export const USAGE: ModuleDefinition = {
  name: "usage",
  title: "Usage metering and quotas",
  description:
    "Usage counters per tenant, meter and day with idempotent increments, quotas per tenant or plan, within_quota() for policies and consume_quota(), which raises quota_exceeded. unreported_usage() feeds reportUsageToStripe.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 4,
  upgrades: [
    {
      from: 1,
      description:
        "Quantities, counters and limits are numeric, so meters count fractions; record_usage and consume_quota take numeric quantities and a source, metadata and actor, and mark_usage_reported takes numeric.",
      sql: (ctx) =>
        [
          `drop function if exists ${ctx.fn("record_usage")}(${ctx.idType}, text, bigint, text);`,
          `drop function if exists ${ctx.fn("consume_quota")}(${ctx.idType}, text, bigint, text);`,
          `drop function if exists ${ctx.fn("mark_usage_reported")}(${ctx.idType}, text, date, bigint);`,
        ].join("\n"),
    },
    {
      from: 2,
      description:
        "unreported_usage takes skip_meters and skip_tenants, so reportUsageToStripe passes over counters it can't send instead of stopping at them.",
      sql: (ctx) =>
        `drop function if exists ${ctx.fn("unreported_usage")}(integer);`,
    },
    {
      from: 3,
      description:
        "Recording usage needs usage.record (or the service role) instead of any membership, record_usage returns used for the quota's period and today for the UTC day, and purge_usage_events deletes old idempotency keys.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
