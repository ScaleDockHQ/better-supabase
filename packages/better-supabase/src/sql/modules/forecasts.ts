import type { ForecastsEvents } from "../../blocks/forecasts/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import {
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";

const EVENTS: ModuleEvents<ForecastsEvents> = {
  "forecast.snapshotted": {
    subject: "forecast-snapshots",
    payload: [
      "organizationId",
      "snapshotId",
      "pipelineId",
      "since",
      "until",
      "currency",
      "dealCount",
    ],
  },
};

const NAMES: ModuleNames = {
  entities: {
    snapshot: {
      table: "snapshots",
      singular: "forecast_snapshot",
      primary: true,
    },
  },
  events: EVENTS,
  tables: {
    snapshots: {
      name: "forecast_snapshots",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        pipeline: "pipeline_id",
        since: "period_start",
        until: "period_end",
        currency: "currency",
        target: "target",
        totals: "totals",
        dealCount: "deal_count",
        takenBy: "taken_by",
        takenAt: "taken_at",
      },
    },
    deals: {
      name: "forecast_snapshot_deals",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        snapshot: "snapshot_id",
        tenant: "tenant_id",
        deal: "deal_id",
        name: "name",
        owner: "owner_user_id",
        stage: "stage_id",
        forecast: "forecast_category",
        outcome: "outcome",
        amount: "amount",
        closeOn: "expected_close_on",
        closedAt: "closed_at",
      },
    },
  },
};

interface ForecastNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly s: (column: string) => string;
  readonly sd: (column: string) => string;
  readonly d: (column: string) => string;
  readonly p: (column: string) => string;
  readonly deals: string;
  readonly pipelines: string;
  readonly dealForecast: string;
  readonly read: string;
  readonly snapshot: string;
}

function names(ctx: ModuleContext): ForecastNames {
  const keys = moduleOperations("forecasts");
  const deals = ctx.of("deals");
  const pipelines = ctx.of("pipelines");

  return {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    s: (column) => ctx.col("snapshots", column),
    sd: (column) => ctx.col("deals", column),
    d: (column) => deals.col("deals", column),
    p: (column) => pipelines.col("pipelines", column),
    deals: deals.table("deals"),
    pipelines: pipelines.table("pipelines"),
    dealForecast: deals.fn("deal_forecast"),
    read: ctx.permission("read", keys.read),
    snapshot: ctx.permission("snapshot", keys.snapshot),
  };
}

function tables(ctx: ModuleContext, n: ForecastNames): string {
  const { t, s, sd, p } = n;
  const policy = (table: string): string => `${ctx.tableName(table).name}_read`;

  return `create table if not exists ${t("snapshots")} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("pipeline")} uuid references ${n.pipelines} (${p("id")}) on delete cascade,
  ${s("since")} date not null,
  ${s("until")} date not null,
  ${s("currency")} text not null check (${s("currency")} ~ '^[A-Z]{3}$'),
  ${s("target")} bigint check (${s("target")} >= 0),
  ${s("totals")} jsonb not null check (jsonb_typeof(${s("totals")}) = 'object'),
  ${s("dealCount")} integer not null default 0,
  ${s("takenBy")} uuid references auth.users (id) on delete set null,
  ${s("takenAt")} timestamptz not null default clock_timestamp(),
  check (${s("until")} >= ${s("since")})
);
create index if not exists ${ctx.naming.rename("forecast_snapshots_period_idx")} on ${t("snapshots")} (${s("tenant")}, ${s("since")}, ${s("until")}, ${s("takenAt")} desc);
create index if not exists ${ctx.naming.rename("forecast_snapshots_pipeline_idx")} on ${t("snapshots")} (${s("pipeline")}) where ${s("pipeline")} is not null;
create index if not exists ${ctx.naming.rename("forecast_snapshots_taken_by_idx")} on ${t("snapshots")} (${s("takenBy")}) where ${s("takenBy")} is not null;
${lockTable(t("snapshots"), { read: true })}
create table if not exists ${t("deals")} (
  ${sd("snapshot")} uuid not null references ${t("snapshots")} (${s("id")}) on delete cascade,
  ${sd("tenant")} ${ctx.idType} not null,
  ${sd("deal")} uuid not null,
  ${sd("name")} text not null,
  ${sd("owner")} uuid,
  ${sd("stage")} uuid,
  ${sd("forecast")} text,
  ${sd("outcome")} text not null,
  ${sd("amount")} bigint not null,
  ${sd("closeOn")} date,
  ${sd("closedAt")} timestamptz,
  primary key (${sd("snapshot")}, ${sd("deal")})
);
create index if not exists ${ctx.naming.rename("forecast_snapshot_deals_deal_idx")} on ${t("deals")} (${sd("tenant")}, ${sd("deal")});
${lockTable(t("deals"), { read: true })}
drop policy if exists ${policy("snapshots")} on ${t("snapshots")};
create policy ${policy("snapshots")} on ${t("snapshots")} for select to authenticated
using (${ctx.scope.check(s("tenant"), n.read)});
drop policy if exists ${policy("deals")} on ${t("deals")};
create policy ${policy("deals")} on ${t("deals")} for select to authenticated
using (${ctx.scope.check(sd("tenant"), n.read)});
`;
}

function functions(ctx: ModuleContext, n: ForecastNames): string {
  const { fn, t, s, sd, d, p } = n;

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'pipelineId', ${row}.${s("pipeline")}, 'since', ${row}.${s("since")}, 'until', ${row}.${s("until")}, 'currency', ${row}.${s("currency")}, 'target', ${row}.${s("target")}::text, 'totals', ${row}.${s("totals")}, 'dealCount', ${row}.${s("dealCount")}, 'takenBy', ${row}.${s("takenBy")}, 'takenAt', ${row}.${s("takenAt")})`;

  const dealJson = (row: string): string =>
    `jsonb_build_object('dealId', ${row}.${sd("deal")}, 'name', ${row}.${sd("name")}, 'ownerId', ${row}.${sd("owner")}, 'stageId', ${row}.${sd("stage")}, 'forecast', ${row}.${sd("forecast")}, 'outcome', ${row}.${sd("outcome")}, 'amount', ${row}.${sd("amount")}::text, 'closeOn', ${row}.${sd("closeOn")}, 'closedAt', ${row}.${sd("closedAt")})`;

  const invalid = (message: string): string =>
    fail("FORECAST_INVALID", message, "22023");

  const notFound = fail(
    "FORECAST_NOT_FOUND",
    "No forecast snapshot you can read has this id",
    "P0002",
  );

  const readable = (tenant: string): string =>
    `(${SERVICE_CALLER} or ${ctx.scope.can(tenant, n.read)})`;

  const change = `case
      when a.${sd("deal")} is null then 'added'
      when b.${sd("deal")} is null then 'removed'
      when a.${sd("outcome")} = 'open' and b.${sd("outcome")} = 'won' then 'won'
      when a.${sd("outcome")} = 'open' and b.${sd("outcome")} = 'lost' then 'lost'
      else 'changed'
    end`;

  const differs = `a.${sd("deal")} is null or b.${sd("deal")} is null
      or a.${sd("amount")} <> b.${sd("amount")}
      or a.${sd("forecast")} is distinct from b.${sd("forecast")}
      or a.${sd("stage")} is distinct from b.${sd("stage")}
      or a.${sd("outcome")} <> b.${sd("outcome")}
      or a.${sd("closeOn")} is distinct from b.${sd("closeOn")}
      or a.${sd("owner")} is distinct from b.${sd("owner")}`;

  return `
-- Takes a snapshot of the forecast call for one currency between since and
-- until: the deal_forecast totals for the whole organization and every deal
-- they count (open deals closing in the period, deals closed in it). Needs
-- forecasts.snapshot. Returns the snapshot without its deals.
create or replace function ${fn("take_forecast_snapshot")}(tenant ${ctx.idType}, pipeline uuid, since date, until date, currency text, target bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("snapshots")};
  v_currency text := upper(take_forecast_snapshot.currency);
  v_count integer;
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("take_forecast_snapshot.tenant", n.snapshot)}) then
    ${fail("FORECAST_FORBIDDEN", "Taking a forecast snapshot needs the forecasts.snapshot permission", "42501")}
  end if;
  if take_forecast_snapshot.since is null or take_forecast_snapshot.until is null
    or take_forecast_snapshot.until < take_forecast_snapshot.since
    or take_forecast_snapshot.until - take_forecast_snapshot.since > 366 then
    ${invalid("until must be on or after since, at most a year later")}
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    ${invalid("currency must be a three-letter code")}
  end if;
  if take_forecast_snapshot.target < 0 then
    ${invalid("target must not be negative")}
  end if;
  if take_forecast_snapshot.pipeline is not null and not exists (
    select 1 from ${n.pipelines} x
    where x.${p("id")} = take_forecast_snapshot.pipeline and x.${p("tenant")} = take_forecast_snapshot.tenant
  ) then
    ${fail("FORECAST_PIPELINE_UNKNOWN", "The organization has no pipeline with this id", "P0002")}
  end if;
  insert into ${t("snapshots")} (${s("tenant")}, ${s("pipeline")}, ${s("since")}, ${s("until")}, ${s("currency")}, ${s("target")}, ${s("totals")}, ${s("takenBy")})
  values (take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target,
    ${n.dealForecast}(take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, null),
    auth.uid())
  returning * into v_row;
  insert into ${t("deals")} (${sd("snapshot")}, ${sd("tenant")}, ${sd("deal")}, ${sd("name")}, ${sd("owner")}, ${sd("stage")}, ${sd("forecast")}, ${sd("outcome")}, ${sd("amount")}, ${sd("closeOn")}, ${sd("closedAt")})
  select v_row.${s("id")}, x.${d("tenant")}, x.${d("id")}, x.${d("name")}, x.${d("owner")}, x.${d("stage")}, x.${d("forecast")}, x.${d("outcome")}, x.${d("amount")}, x.${d("closeOn")}, x.${d("closedAt")}
  from ${n.deals} x
  where x.${d("tenant")} = take_forecast_snapshot.tenant
    and x.${d("currency")} = v_currency
    and x.${d("archivedAt")} is null
    and (take_forecast_snapshot.pipeline is null or x.${d("pipeline")} = take_forecast_snapshot.pipeline)
    and (
      (x.${d("outcome")} = 'open' and x.${d("closeOn")} between take_forecast_snapshot.since and take_forecast_snapshot.until)
      or (x.${d("outcome")} <> 'open' and x.${d("closedAt")}::date between take_forecast_snapshot.since and take_forecast_snapshot.until)
    );
  get diagnostics v_count = row_count;
  update ${t("snapshots")} x set ${s("dealCount")} = v_count
  where x.${s("id")} = v_row.${s("id")}
  returning * into v_row;
  ${ctx.record({
    type: "forecast.snapshotted",
    payload: `jsonb_build_object('organizationId', v_row.${s("tenant")}, 'snapshotId', v_row.${s("id")}, 'pipelineId', v_row.${s("pipeline")}, 'since', v_row.${s("since")}, 'until', v_row.${s("until")}, 'currency', v_row.${s("currency")}, 'dealCount', v_row.${s("dealCount")})`,
    subject: `'forecast-snapshots/' || v_row.${s("id")}::text`,
    tenant: `v_row.${s("tenant")}::text`,
    audit: false,
  })}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("take_forecast_snapshot")}(${ctx.idType}, uuid, date, date, text, bigint)`)}

-- The organization's snapshots, newest first, optionally of one pipeline and
-- of the period between since and until. Needs forecasts.read.
create or replace function ${fn("forecast_snapshots")}(tenant ${ctx.idType}, pipeline uuid default null, since date default null, until date default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.taken_at desc, z.id), '[]'::jsonb)
  from (
    select ${json("x")} as item, x.${s("takenAt")} as taken_at, x.${s("id")} as id
    from ${t("snapshots")} x
    where x.${s("tenant")} = forecast_snapshots.tenant
      and ${readable(`x.${s("tenant")}`)}
      and (forecast_snapshots.pipeline is null or x.${s("pipeline")} = forecast_snapshots.pipeline)
      and (forecast_snapshots.since is null or x.${s("since")} = forecast_snapshots.since)
      and (forecast_snapshots.until is null or x.${s("until")} = forecast_snapshots.until)
    order by x.${s("takenAt")} desc, x.${s("id")}
    limit ${pageSize("forecast_snapshots.max_count", 50, 200)}
  ) z
$$;
${userGrant(`${fn("forecast_snapshots")}(${ctx.idType}, uuid, date, date, integer)`)}

-- One snapshot with its deals, the largest amount first.
create or replace function ${fn("forecast_snapshot")}(snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t("snapshots")};
begin
  select * into v_row from ${t("snapshots")} x where x.${s("id")} = forecast_snapshot.snapshot;
  if v_row.${s("id")} is null or not ${readable(`v_row.${s("tenant")}`)} then
    ${notFound}
  end if;
  return ${json("v_row")} || jsonb_build_object('deals', (
    select coalesce(jsonb_agg(${dealJson("y")} order by y.${sd("amount")} desc, y.${sd("deal")}), '[]'::jsonb)
    from ${t("deals")} y where y.${sd("snapshot")} = v_row.${s("id")}
  ));
end;
$$;
${userGrant(`${fn("forecast_snapshot")}(uuid)`)}

-- What changed between two snapshots of one organization and currency: each
-- deal that was added, removed, won, lost or changed its amount, forecast
-- category, stage, owner or close date, with its values in both.
create or replace function ${fn("forecast_changes")}(from_snapshot uuid, to_snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from ${t("snapshots")};
  v_to ${t("snapshots")};
begin
  select * into v_from from ${t("snapshots")} x where x.${s("id")} = forecast_changes.from_snapshot;
  select * into v_to from ${t("snapshots")} x where x.${s("id")} = forecast_changes.to_snapshot;
  if v_from.${s("id")} is null or v_to.${s("id")} is null
    or not ${readable(`v_from.${s("tenant")}`)} or not ${readable(`v_to.${s("tenant")}`)} then
    ${notFound}
  end if;
  if v_from.${s("tenant")} <> v_to.${s("tenant")} or v_from.${s("currency")} <> v_to.${s("currency")} then
    ${fail("FORECAST_MISMATCH", "Both snapshots must be of one organization and currency", "22023")}
  end if;
  return jsonb_build_object(
    'from', ${json("v_from")},
    'to', ${json("v_to")},
    'deals', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'dealId', coalesce(b.${sd("deal")}, a.${sd("deal")}),
        'name', coalesce(b.${sd("name")}, a.${sd("name")}),
        'change', ${change},
        'before', case when a.${sd("deal")} is null then null else ${dealJson("a")} end,
        'after', case when b.${sd("deal")} is null then null else ${dealJson("b")} end
      ) order by coalesce(b.${sd("amount")}, a.${sd("amount")}) desc, coalesce(b.${sd("deal")}, a.${sd("deal")})), '[]'::jsonb)
      from (select * from ${t("deals")} where ${sd("snapshot")} = v_from.${s("id")}) a
      full join (select * from ${t("deals")} where ${sd("snapshot")} = v_to.${s("id")}) b on b.${sd("deal")} = a.${sd("deal")}
      where ${differs}
    ));
end;
$$;
${userGrant(`${fn("forecast_changes")}(uuid, uuid)`)}
`;
}

function build(ctx: ModuleContext): string {
  const n = names(ctx);

  return `${schemaPreamble(ctx)}
-- Forecasts: snapshots of the forecast call over time, with the deals each
-- one counted, and what changed between two of them.
${tables(ctx, n)}${functions(ctx, n)}`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "take_forecast_snapshot",
      args: ["{id}", "uuid", "date", "date", "text", "bigint"],
      returns: "jsonb",
    },
    {
      name: "forecast_snapshots",
      args: ["{id}", "uuid", "date", "date", "integer"],
      returns: "jsonb",
    },
    { name: "forecast_snapshot", args: ["uuid"], returns: "jsonb" },
    { name: "forecast_changes", args: ["uuid", "uuid"], returns: "jsonb" },
  ];
}

export const FORECASTS: ModuleDefinition = {
  name: "forecasts",
  scopes: ["tenant"],
  title: "Forecasts",
  description:
    "Snapshots of the deals forecast call over time: the totals by category and every deal they counted, a list per period, and what changed between two snapshots (added, removed, won, lost, moved).",
  requires: ["tenant", "access", "deals"],
  integrates: ["outbox", "data-lifecycle"],
  target: "schema",
  modes: ["managed"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
