import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["meters"],
  hooks: ["usage_billing_period"],
  tables: {
    counters: {
      name: "usage_counters",
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
      columns: {
        tenant: "organization_id",
        meter: "meter",
        key: "idempotency_key",
        quantity: "quantity",
        recordedAt: "recorded_at",
      },
    },
    quotas: {
      name: "usage_quotas",
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

/** `options.meters`: the meter catalog; with it, unknown meters are refused. */
function metersOf(
  ctx: ModuleContext,
): Readonly<Record<string, UsageMeter>> | undefined {
  const where = "sql.modules.usage.options.meters";
  const option = ctx.option("meters");
  if (option === undefined) return undefined;
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
  const fn = (name: string): string => ctx.fn(name);
  const permissions = MODULE_PERMISSIONS.usage;
  const canRead = (tenant: string): string =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission("read", permissions.read)}), false))`;
  const member = (tenant: string): string =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.has_organization_role(${tenant}), false))`;
  // Plan quotas apply to tenants with that entitlement key, to tenants on that
  // plan key when entitlements read a plan catalog, or to every tenant with
  // plan '*'.
  const meters = metersOf(ctx);
  const catalog = sqlString(JSON.stringify(meters ?? {}));
  const meterCheck = meters
    ? `
  if not (${catalog}::jsonb ? meter) then
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
  ${cc("value")} bigint not null default 0 check (${cc("value")} >= 0),
  ${cc("reported")} bigint not null default 0 check (${cc("reported")} >= 0),
  ${cc("updatedAt")} timestamptz not null default now(),
  primary key (${cc("tenant")}, ${cc("meter")}, ${cc("day")})
);
create index if not exists usage_counters_unreported_idx on ${counters} (${cc("day")})
  where ${cc("value")} > ${cc("reported")};
alter table ${counters} enable row level security;
revoke all on ${counters} from anon, authenticated;
grant select on ${counters} to authenticated;
grant all on ${counters} to service_role;
drop policy if exists "usage_counters_read" on ${counters};
create policy "usage_counters_read" on ${counters} for select to authenticated
  using (${canRead(cc("tenant"))});

-- One row per idempotency key, so a retried increment counts once.
create table if not exists ${events} (
  ${ec("tenant")} ${id} not null,
  ${ec("meter")} text not null,
  ${ec("key")} text not null,
  ${ec("quantity")} bigint not null,
  ${ec("recordedAt")} timestamptz not null default now(),
  primary key (${ec("tenant")}, ${ec("meter")}, ${ec("key")})
);
create index if not exists usage_events_recorded_at_idx on ${events} (${ec("recordedAt")});
alter table ${events} enable row level security;
revoke all on ${events} from anon, authenticated;
grant all on ${events} to service_role;

-- A tenant row overrides the plan rows; of several plan rows the highest
-- limit wins.
create table if not exists ${quotas} (
  ${qc("id")} uuid primary key default gen_random_uuid(),
  ${qc("tenant")} ${id},
  ${qc("plan")} text,
  ${qc("meter")} text not null check (${qc("meter")} ~ ${METER}),
  ${qc("limit")} bigint not null check (${qc("limit")} >= 0),
  ${qc("period")} text not null default 'month' check (${periodCheck}),
  ${qc("createdAt")} timestamptz not null default now(),
  check ((${qc("tenant")} is null) <> (${qc("plan")} is null)),
  unique nulls not distinct (${qc("tenant")}, ${qc("plan")}, ${qc("meter")})
);
alter table ${quotas} drop constraint if exists ${periodConstraint};
alter table ${quotas} add constraint ${periodConstraint} check (${periodCheck});
alter table ${quotas} enable row level security;
revoke all on ${quotas} from anon, authenticated;
grant select on ${quotas} to authenticated;
grant all on ${quotas} to service_role;
drop policy if exists "usage_quotas_read" on ${quotas};
create policy "usage_quotas_read" on ${quotas} for select to authenticated
  using (${qc("tenant")} is null or ${canRead(qc("tenant"))});

-- The quota that applies to tenant and meter, or no row.
create or replace function ${fn("usage_quota")}(tenant ${id}, meter text)
returns table (quota_limit bigint, period text)
language sql
stable
security definer
set search_path = ''
as $$
  select q.${qc("limit")}, q.${qc("period")}
  from ${quotas} q
  where q.${qc("meter")} = usage_quota.meter
    and (q.${qc("tenant")} = usage_quota.tenant or (q.${qc("tenant")} is null and (${planMatches})))
  order by (q.${qc("tenant")} is not null) desc, q.${qc("limit")} desc
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

-- Usage of meter in the current window of period, counted by UTC day.
create or replace function ${fn("usage_used")}(tenant ${id}, meter text, period text default 'month')
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(c.${cc("value")}), 0)::bigint
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
immutable
set search_path = ''
as $$
  select ${catalog}::jsonb
$$;

-- { meter, used, limit, remaining, period, resets_at }; limit and remaining
-- are null without a quota.
create or replace function ${fn("usage_status")}(tenant ${id}, meter text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quota record;
  used bigint;
  win record;
begin
  if not ${member("tenant")} then
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
    'period', coalesce(quota.period, 'month'),
    'resets_at', win.ends_at,
    'starts_at', win.starts_at
  ) || coalesce(${fn("usage_meters")}() -> meter, '{}'::jsonb);
end;
$$;

-- For policies: whether quantity more fits the tenant's quota.
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
  select * into quota from ${fn("usage_quota")}(tenant, meter);
  if quota.quota_limit is null then
    return true;
  end if;
  return ${fn("usage_used")}(tenant, meter, quota.period) + quantity <= quota.quota_limit;
end;
$$;

-- Adds quantity once per idempotency key. Returns { recorded, used }:
-- recorded is false for a key seen before.
create or replace function ${fn("record_usage")}(
  tenant ${id},
  meter text,
  quantity bigint default 1,
  idempotency_key text default null
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
  if not ${member("tenant")} then
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
      return jsonb_build_object('recorded', false, 'used', ${fn("usage_used")}(tenant, meter, 'day'));
    end if;
  end if;
  insert into ${counters} as c (${cc("tenant")}, ${cc("meter")}, ${cc("day")}, ${cc("value")})
  values (tenant, meter, today, quantity)
  on conflict (${cc("tenant")}, ${cc("meter")}, ${cc("day")}) do update
    set ${cc("value")} = c.${cc("value")} + excluded.${cc("value")}, ${cc("updatedAt")} = now();
  return jsonb_build_object('recorded', true, 'used', ${fn("usage_used")}(tenant, meter, 'day'));
end;
$$;

-- Like record_usage, but first checks the quota and raises quota_exceeded
-- (SQLSTATE BSQ29) without recording when quantity does not fit. Today's
-- counter row is locked, so concurrent calls cannot both take the last unit.
create or replace function ${fn("consume_quota")}(
  tenant ${id},
  meter text,
  quantity bigint default 1,
  idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  today date := (now() at time zone 'utc')::date;
  quota record;
  used bigint;
  win record;
begin
  if not ${member("tenant")} then
    raise exception 'Not allowed to record usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;${meterCheck}
  insert into ${counters} (${cc("tenant")}, ${cc("meter")}, ${cc("day")})
  values (tenant, meter, today)
  on conflict do nothing;
  perform 1 from ${counters} c
  where c.${cc("tenant")} = consume_quota.tenant and c.${cc("meter")} = consume_quota.meter and c.${cc("day")} = today
  for update;
  if idempotency_key is not null and exists (
    select 1 from ${events} e
    where e.${ec("tenant")} = consume_quota.tenant and e.${ec("meter")} = consume_quota.meter and e.${ec("key")} = consume_quota.idempotency_key
  ) then
    return jsonb_build_object('recorded', false, 'used', ${fn("usage_used")}(tenant, meter, 'day'));
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
  return ${fn("record_usage")}(tenant, meter, quantity, idempotency_key);
end;
$$;

-- Server-side, for reportUsageToStripe: counters with unreported usage.
create or replace function ${fn("unreported_usage")}(max_rows integer default 500)
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
    'reported_value', c.${cc("reported")}
  ) order by c.${cc("day")}, c.${cc("meter")}), '[]'::jsonb)
  from (
    select * from ${counters} c
    where c.${cc("value")} > c.${cc("reported")}
    order by c.${cc("day")}
    limit max_rows
  ) c
$$;

-- Marks a counter as reported up to value; never moves it backwards.
create or replace function ${fn("mark_usage_reported")}(tenant ${id}, meter text, day date, value bigint)
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

revoke execute on function ${fn("usage_window")}(${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("usage_meters")}() from public;
grant execute on function ${fn("usage_window")}(${id}, text) to service_role;
grant execute on function ${fn("usage_meters")}() to anon, authenticated, service_role;
revoke execute on function ${fn("usage_quota")}(${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("usage_used")}(${id}, text, text) from public, anon, authenticated;
revoke execute on function ${fn("usage_status")}(${id}, text) from public, anon;
revoke execute on function ${fn("within_quota")}(${id}, text, bigint) from public, anon;
revoke execute on function ${fn("record_usage")}(${id}, text, bigint, text) from public, anon;
revoke execute on function ${fn("consume_quota")}(${id}, text, bigint, text) from public, anon;
revoke execute on function ${fn("unreported_usage")}(integer) from public, anon, authenticated;
revoke execute on function ${fn("mark_usage_reported")}(${id}, text, date, bigint) from public, anon, authenticated;
grant execute on function ${fn("usage_quota")}(${id}, text) to service_role;
grant execute on function ${fn("usage_used")}(${id}, text, text) to service_role;
grant execute on function ${fn("usage_status")}(${id}, text) to authenticated, service_role;
grant execute on function ${fn("within_quota")}(${id}, text, bigint) to authenticated, service_role;
grant execute on function ${fn("record_usage")}(${id}, text, bigint, text) to authenticated, service_role;
grant execute on function ${fn("consume_quota")}(${id}, text, bigint, text) to authenticated, service_role;
grant execute on function ${fn("unreported_usage")}(integer) to service_role;
grant execute on function ${fn("mark_usage_reported")}(${id}, text, date, bigint) to service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "usage_status", args: ["{id}", "text"], returns: "jsonb" },
    { name: "usage_meters", args: [], returns: "jsonb" },
    { name: "usage_window", args: ["{id}", "text"], returns: "record" },
    {
      name: "within_quota",
      args: ["{id}", "text", "bigint"],
      returns: "boolean",
    },
    {
      name: "record_usage",
      args: ["{id}", "text", "bigint", "text"],
      returns: "jsonb",
    },
    {
      name: "consume_quota",
      args: ["{id}", "text", "bigint", "text"],
      returns: "jsonb",
    },
    { name: "unreported_usage", args: ["integer"], returns: "jsonb" },
    {
      name: "mark_usage_reported",
      args: ["{id}", "text", "date", "bigint"],
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
  version: 1,
  names: NAMES,
  contract,
  build,
};
