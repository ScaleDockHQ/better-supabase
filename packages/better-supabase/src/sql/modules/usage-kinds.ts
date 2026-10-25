import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { UsageMeter } from "./usage-meters.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";
import { isMeterTable, metersOf } from "./usage-meters.ts";

/** The meters that count distinct subjects or are computed by a query. */
export interface UsageKinds {
  readonly distinct: readonly string[];
  readonly computed: readonly {
    readonly meter: string;
    readonly period: string;
    readonly query: string;
  }[];
}

function usageKindsOf(ctx: BlockSqlContext): UsageKinds {
  const meters = metersOf(ctx);

  const entries: readonly [string, UsageMeter][] =
    meters === undefined || isMeterTable(meters) ? [] : Object.entries(meters);

  return {
    distinct: entries.flatMap(([meter, info]) =>
      info.kind === "distinct" ? [meter] : [],
    ),
    computed: entries.flatMap(([meter, info]) =>
      info.kind === "computed"
        ? [{ meter, period: info.period ?? "month", query: info.query ?? "" }]
        : [],
    ),
  };
}

/**
 * Distinct meters (`track_usage`: one unit per subject and period) and computed
 * meters (`usage_refresh`: a gauge a query reports per tenant). Both write the
 * counters table, so quotas, status and Stripe reporting read them like any
 * counter.
 */
export function usageKindsSql(ctx: BlockSqlContext): string {
  const kinds = usageKindsOf(ctx);

  return `${kinds.distinct.length > 0 ? distinctSql(ctx, kinds) : ""}${kinds.computed.length > 0 ? computedSql(ctx, kinds) : ""}`;
}

function distinctSql(ctx: BlockSqlContext, kinds: UsageKinds): string {
  const permissions = moduleOperations("usage");
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const distinct = ctx.table("distinct");
  const dc = (logical: string): string => ctx.col("distinct", logical);

  const distinctList = kinds.distinct
    .map((meter) => sqlString(meter))
    .join(", ");

  return `
-- Distinct meters: one row per subject and period, so a subject counts once.
create table if not exists ${distinct} (
  ${dc("tenant")} ${id} not null,
  ${dc("meter")} text not null,
  ${dc("periodStart")} date not null,
  ${dc("subject")} text not null,${
    ctx.has("distinct", "firstSeen")
      ? `\n  ${dc("firstSeen")} timestamptz not null default now(),`
      : ""
  }
  primary key (${dc("tenant")}, ${dc("meter")}, ${dc("periodStart")}, ${dc("subject")})
);${
    ctx.owns("distinct")
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("distinct").name}_subject_key`)} on ${distinct} (${dc("tenant")}, ${dc("meter")}, ${dc("periodStart")}, ${dc("subject")});`
  }
alter table ${distinct} enable row level security;
revoke all on ${distinct} from public, anon, authenticated;
grant all on ${distinct} to service_role;

-- Counts subject once in the current period of a distinct meter. The first
-- sight adds one unit to the meter's counter; later ones change nothing, so
-- the quota and the Stripe report see the period's distinct count. Returns
-- { recorded, used, today } like record_usage.
create or replace function ${fn("track_usage")}(
  tenant ${id}, meter text, subject text, period text default 'month')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_start date;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "tenant", ctx.permission("record", permissions.record))}) then
    ${fail("USAGE_FORBIDDEN", "Not allowed to record usage in this tenant")}
  end if;
  if track_usage.subject is null or track_usage.subject = '' then
    ${fail("USAGE_SUBJECT", "subject is required", "22023")}
  end if;
  if track_usage.meter <> all (array[${distinctList}]) then
    ${fail("USAGE_METER_KIND", "Meter is not a distinct meter", "22023")}
  end if;
  v_start := ${fn("usage_window_start")}(track_usage.tenant, track_usage.period, (now() at time zone 'utc')::date);
  insert into ${distinct} (${dc("tenant")}, ${dc("meter")}, ${dc("periodStart")}, ${dc("subject")})
  values (track_usage.tenant, track_usage.meter, v_start, track_usage.subject)
  on conflict do nothing;
  if not found then
    return jsonb_build_object('recorded', false,
      'used', ${fn("usage_used")}(track_usage.tenant, track_usage.meter, track_usage.period),
      'today', ${fn("usage_used")}(track_usage.tenant, track_usage.meter, 'day'));
  end if;
  return ${fn("record_usage")}(track_usage.tenant, track_usage.meter, 1);
end;
$$;

revoke execute on function ${fn("track_usage")}(${id}, text, text, text) from public, anon;
grant execute on function ${fn("track_usage")}(${id}, text, text, text) to authenticated, service_role;
`;
}

function computedSql(ctx: BlockSqlContext, kinds: UsageKinds): string {
  const fn = (name: string): string => ctx.fn(name);
  const counters = ctx.table("counters");
  const cc = (logical: string): string => ctx.col("counters", logical);

  const refreshes = kinds.computed
    .map(
      ({ meter, period, query }) => `
  if usage_refresh.meter is null or usage_refresh.meter = ${sqlString(meter)} then
    for r in select q.tenant, q.value from (${query}) as q(tenant, value) loop
      v_since := ${fn("usage_window_start")}(r.tenant, ${sqlString(period)}, v_today);
      insert into ${counters} as c (${cc("tenant")}, ${cc("meter")}, ${cc("day")}, ${cc("value")})
      values (r.tenant, ${sqlString(meter)}, v_today, greatest(0, r.value - coalesce((
        select sum(o.${cc("value")}) from ${counters} o
        where o.${cc("tenant")} = r.tenant and o.${cc("meter")} = ${sqlString(meter)}
          and o.${cc("day")} >= v_since and o.${cc("day")} < v_today), 0)))
      on conflict (${cc("tenant")}, ${cc("meter")}, ${cc("day")}) do update
        set ${cc("value")} = excluded.${cc("value")}${ctx.has("counters", "updatedAt") ? `, ${cc("updatedAt")} = now()` : ""};
      v_rows := v_rows + 1;
    end loop;
  end if;`,
    )
    .join("");

  return `
-- Recomputes computed meters (options.meters.<meter>.query) for every tenant
-- the query returns, or for one meter. The counter of today is set so the
-- period's total equals the reported value. Returns the rows written. Service
-- role only; schedule it with pg_cron.
create or replace function ${fn("usage_refresh")}(meter text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  r record;
  v_today date := (now() at time zone 'utc')::date;
  v_since date;
  v_rows integer := 0;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("USAGE_FORBIDDEN", "only the service role refreshes computed meters")}
  end if;${refreshes}
  return v_rows;
end;
$$;

revoke execute on function ${fn("usage_refresh")}(text) from public, anon, authenticated;
grant execute on function ${fn("usage_refresh")}(text) to service_role;
`;
}

/** Hourly pg_cron schedule for computed meters, when pg_cron is installed. */
export function usageRefreshSchedule(ctx: BlockSqlContext): string {
  if (usageKindsOf(ctx).computed.length === 0) {
    return "";
  }

  return `-- Refreshes computed usage meters hourly when pg_cron is installed.
do $$
begin
  if pg_catalog.to_regnamespace('cron') is not null then
    perform cron.schedule('better-supabase-usage-refresh', '5 * * * *', ${sqlString(`select ${ctx.fn("usage_refresh")}()`)});
  else
    raise notice 'pg_cron is not installed: call ${ctx.fn("usage_refresh").replaceAll("'", "")}() on a schedule to refresh computed usage meters';
  end if;
end;
$$;`;
}

export function usageKindsContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const kinds = usageKindsOf(ctx);

  return [
    ...(kinds.distinct.length > 0
      ? [
          {
            name: "track_usage",
            args: ["{id}", "text", "text", "text"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(kinds.computed.length > 0
      ? [{ name: "usage_refresh", args: ["text"], returns: "integer" }]
      : []),
  ];
}
