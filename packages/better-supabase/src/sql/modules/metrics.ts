import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import {
  METRIC_GRAINS,
  type MetricDefinition,
  type MetricGrain,
  grainDivides,
  metricsOf,
} from "../../core/metric-definition.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  SERVICE_CALLER,
  fail,
  lockTable,
  quotedTable,
  schemaPreamble,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  hooks: ["before_metric_rollup", "after_metric_rollup"],
  options: ["metrics", "window"],
  tables: {
    points: {
      name: "metric_points",
      lifecycle: { tenant: "tenant", export: false },
      columns: {
        tenant: "tenant_id",
        metric: "metric",
        grain: "grain",
        bucketStart: "bucket_start",
        dims: "dims",
        value: "value",
        count: "count",
        updatedAt: "updated_at",
      },
    },
  },
};

/** The most buckets one series returns. */
const METRIC_MAX_BUCKETS = 1000;

const WINDOW = /^[1-9][0-9]{0,3} (?:minute|hour|day|week)s?$/;

/** How far back a periodic `metrics_rollup()` re-aggregates, for late rows. */
function windowOf(ctx: ModuleContext): string {
  const window = ctx.text("window", "3 days");
  if (!WINDOW.test(window)) {
    throw new TypeError(
      'sql.modules.metrics.options.window must be an interval such as "3 days" or "12 hours"',
    );
  }
  return window;
}

/** The metrics declared in `options.metrics`. */
function declaredMetrics(ctx: ModuleContext): readonly MetricDefinition[] {
  return metricsOf(ctx.option("metrics"));
}

/** The grains `metric_points` keeps for a metric, none when it is queried directly. */
function storedGrains(metric: MetricDefinition): readonly MetricGrain[] {
  if (metric.rollup === false) return [];
  const grains = metric.rollup ?? ["day"];
  return METRIC_GRAINS.filter((grain) => grains.includes(grain));
}

const literal = (value: string | number | boolean | null): string =>
  value === null
    ? "null"
    : typeof value === "string"
      ? sqlString(value)
      : String(value);

/** `select tenant, at, dims, value, count` over the metric's table, one row per source row. */
function rowSource(metric: MetricDefinition): string {
  const t = (name: string): string => `t.${sqlIdent(name)}`;
  const dims = metric.dimensions ?? [];
  const dimsSql =
    dims.length === 0
      ? "'{}'::jsonb"
      : `jsonb_build_object(${dims.map((name) => `${sqlString(name)}, ${t(name)}`).join(", ")})`;
  const { measure } = metric;
  const [value, count] =
    measure === "count"
      ? ["1::numeric", "1::bigint"]
      : "sum" in measure
        ? [`coalesce(${t(measure.sum)}, 0)::numeric`, "1::bigint"]
        : [
            `${t(measure.avg)}::numeric`,
            `(${t(measure.avg)} is not null)::int::bigint`,
          ];
  const where = Object.entries(metric.where ?? {}).map(([name, v]) =>
    v === null ? `${t(name)} is null` : `${t(name)} = ${literal(v)}`,
  );
  return `select ${t(metric.tenant ?? "organization_id")} as tenant, ${t(metric.timeColumn)} as at, ${dimsSql} as dims, ${value} as value, ${count} as count
        from ${quotedTable(metric.table)} t${where.length === 0 ? "" : `\n        where ${where.join("\n          and ")}`}`;
}

/** The value of a bucket from its summed `value` and `count`. */
function finalValue(metric: MetricDefinition, alias: string): string {
  return metric.measure !== "count" && "avg" in metric.measure
    ? `round(${alias}.value / nullif(${alias}.count, 0), 6)`
    : `coalesce(${alias}.value, 0)`;
}

/** `timestamptz + 1 grain` in the metric's time zone, so a day is a local day. */
const plusGrain = (at: string, grain: string, tz: string): string =>
  `((${at}) at time zone ${tz} + ${grain}) at time zone ${tz}`;

function textArray(values: readonly string[]): string {
  return values.length === 0
    ? "array[]::text[]"
    : `array[${values.map(sqlString).join(", ")}]::text[]`;
}

interface Names {
  readonly points: string;
  readonly c: (column: string) => string;
}

function rollupBranch(
  ctx: ModuleContext,
  metric: MetricDefinition,
  names: Names,
): string {
  const { points, c } = names;
  const tz = sqlString(metric.tz ?? "UTC");
  const key = sqlString(metric.key);
  const grains = storedGrains(metric);
  const steps = grains.map((grain) => {
    const g = sqlString(grain);
    return `    v_from := date_trunc(${g}, v_since, ${tz});
    v_to := ${plusGrain(`date_trunc(${g}, v_until - interval '1 microsecond', ${tz})`, `interval '1 ${grain}'`, tz)};
    delete from ${points}
      where ${c("metric")} = ${key} and ${c("grain")} = ${g}
        and ${c("bucketStart")} >= v_from and ${c("bucketStart")} < v_to;
    insert into ${points} (${c("tenant")}, ${c("metric")}, ${c("grain")}, ${c("bucketStart")}, ${c("dims")}, ${c("value")}, ${c("count")}, ${c("updatedAt")})
    select s.tenant, ${key}, ${g}, date_trunc(${g}, s.at, ${tz}), s.dims, coalesce(sum(s.value), 0), sum(s.count), now()
      from (${rowSource(metric)}) s
      where s.tenant is not null and s.at >= v_from and s.at < v_to
      group by s.tenant, date_trunc(${g}, s.at, ${tz}), s.dims;
    get diagnostics v_rows = row_count;
    v_total := v_total + v_rows;`;
  });
  return `  if p_metric is null or p_metric = ${key} then
    ${ctx.hook("before_metric_rollup", [
      ["text", key],
      ["timestamptz", "v_since"],
      ["timestamptz", "v_until"],
    ])}
${steps.join("\n")}
    ${ctx.hook("after_metric_rollup", [
      ["text", key],
      ["timestamptz", "v_since"],
      ["timestamptz", "v_until"],
    ])}
  end if;`;
}

/**
 * The `source` rows of a read: `metric_points` at `v_source` when it is set,
 * otherwise the metric's table, from `start` to `p_until`.
 */
function sourceCte(
  metric: MetricDefinition,
  names: Names,
  start: string,
): string {
  const { points, c } = names;
  const filter = "coalesce(p_dims, '{}'::jsonb)";
  const stored =
    storedGrains(metric).length === 0
      ? ""
      : `select p.${c("bucketStart")} as at, p.${c("dims")} as dims, p.${c("value")} as value, p.${c("count")} as count
        from ${points} p
        where v_source is not null
          and p.${c("tenant")} = p_tenant
          and p.${c("metric")} = ${sqlString(metric.key)}
          and p.${c("grain")} = v_source
          and p.${c("bucketStart")} >= ${start}
          and p.${c("bucketStart")} < p_until
          and p.${c("dims")} @> ${filter}
      union all
      `;
  return `source as (
      ${stored}select s.at, s.dims, s.value, s.count
        from (${rowSource(metric)}) s
        where v_source is null
          and s.tenant = p_tenant
          and s.at >= ${start}
          and s.at < p_until
          and s.dims @> ${filter}
    )`;
}

/** The stored grain each requested grain reads from, coarsest first; `null` reads the table. */
function sourceGrainCase(
  metric: MetricDefinition,
  pick: "coarsest" | "finest",
): string {
  const stored = storedGrains(metric);
  if (stored.length === 0) return "null";
  if (pick === "finest") return sqlString(stored[0]!);
  const branches = METRIC_GRAINS.map((grain) => {
    const from = stored.findLast((s) => grainDivides(s, grain));
    return `when ${sqlString(grain)} then ${from === undefined ? "null" : sqlString(from)}`;
  });
  return `case p_grain ${branches.join(" ")} end`;
}

function readChecks(ctx: ModuleContext, metric: MetricDefinition): string {
  const permission = sqlString(
    metric.permission ?? ctx.permissionKey("read", OPERATIONS["metrics.read"]),
  );
  const dims = textArray(metric.dimensions ?? []);
  return `      if not (${SERVICE_CALLER} or ${ctx.can("tenant", "p_tenant", permission)}) then
        ${fail("METRIC_FORBIDDEN", "you cannot read this metric in this organization")}
      end if;
      if exists (
        select 1 from jsonb_object_keys(coalesce(p_dims, '{}'::jsonb)) k
        where k <> all (${dims})
      ) then
        ${fail("METRIC_DIMENSION_UNKNOWN", "a filter names a column that is not a dimension of this metric", "22023")}
      end if;`;
}

function seriesBranch(
  ctx: ModuleContext,
  metric: MetricDefinition,
  names: Names,
): string {
  const tz = sqlString(metric.tz ?? "UTC");
  const dims = textArray(metric.dimensions ?? []);
  return `    when ${sqlString(metric.key)} then
${readChecks(ctx, metric)}
      if p_group_by is not null and p_group_by <> all (${dims}) then
        ${fail("METRIC_DIMENSION_UNKNOWN", "group_by is not a dimension of this metric", "22023")}
      end if;
      v_source := ${sourceGrainCase(metric, "coarsest")};
      v_start := date_trunc(p_grain, p_from, ${tz});
      select count(*) into v_buckets
        from generate_series(v_start at time zone ${tz}, (p_until at time zone ${tz}) - interval '1 microsecond', ('1 ' || p_grain)::interval);
      if v_buckets > ${String(METRIC_MAX_BUCKETS)} then
        ${fail("METRIC_RANGE_TOO_LARGE", `a series returns at most ${String(METRIC_MAX_BUCKETS)} buckets; pick a coarser grain`, "22023")}
      end if;
      return (
        with ${sourceCte(metric, names, "v_start")},
        buckets as (
          select b at time zone ${tz} as bucket
            from generate_series(v_start at time zone ${tz}, (p_until at time zone ${tz}) - interval '1 microsecond', ('1 ' || p_grain)::interval) b
        ),
        grouped as (
          select date_trunc(p_grain, s.at, ${tz}) as bucket,
                 case when p_group_by is null then null else s.dims ->> p_group_by end as grp,
                 sum(s.value) as value,
                 sum(s.count) as count
            from source s
            group by 1, 2
        ),
        per_bucket as (
          select g.bucket, sum(g.value) as value, sum(g.count) as count,
                 jsonb_object_agg(coalesce(g.grp, ''), ${finalValue(metric, "g")}) as groups
            from grouped g
            group by g.bucket
        )
        select coalesce(jsonb_agg(
          jsonb_build_object('bucket', b.bucket, 'value', ${finalValue(metric, "p")}, 'count', coalesce(p.count, 0))
            || case when p_group_by is null then '{}'::jsonb else jsonb_build_object('groups', coalesce(p.groups, '{}'::jsonb)) end
          order by b.bucket), '[]'::jsonb)
          from buckets b
          left join per_bucket p on p.bucket = b.bucket
      );`;
}

function valueBranch(
  ctx: ModuleContext,
  metric: MetricDefinition,
  names: Names,
): string {
  return `    when ${sqlString(metric.key)} then
${readChecks(ctx, metric)}
      v_source := ${sourceGrainCase(metric, "finest")};
      return (
        with ${sourceCte(metric, names, "p_from")},
        total as (select sum(s.value) as value, sum(s.count) as count from source s)
        select jsonb_build_object('value', ${finalValue(metric, "t")}, 'count', coalesce(t.count, 0))
          from total t
      );`;
}

function definitionsJson(metrics: readonly MetricDefinition[]): string {
  const json = metrics.map((metric) => ({
    key: metric.key,
    label: metric.label ?? null,
    unit: metric.unit ?? null,
    measure:
      metric.measure === "count"
        ? "count"
        : "sum" in metric.measure
          ? "sum"
          : "avg",
    dimensions: metric.dimensions ?? [],
    grains: storedGrains(metric),
    tz: metric.tz ?? "UTC",
  }));
  return `${sqlString(JSON.stringify(json))}::jsonb`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const points = ctx.table("points");
  const c = (column: string): string => ctx.col("points", column);
  const names: Names = { points, c };
  const fn = (name: string): string => ctx.fn(name);
  const metrics = declaredMetrics(ctx);
  const window = windowOf(ctx);
  const keys = textArray(metrics.map((metric) => metric.key));
  const unknown = fail("METRIC_UNKNOWN", "no metric has this key", "22023");
  const grains = textArray(METRIC_GRAINS);
  const tables = ctx.manages
    ? `create table if not exists ${points} (
  ${c("tenant")} ${ctx.idType} not null,
  ${c("metric")} text not null,
  ${c("grain")} text not null check (${c("grain")} in ('hour', 'day', 'week', 'month')),
  ${c("bucketStart")} timestamptz not null,
  ${c("dims")} jsonb not null default '{}'::jsonb,
  ${c("value")} numeric not null,
  ${c("count")} bigint not null,
  ${c("updatedAt")} timestamptz not null default now(),
  primary key (${c("tenant")}, ${c("metric")}, ${c("grain")}, ${c("bucketStart")}, ${c("dims")})
);
${lockTable(points)}
create index if not exists metric_points_rollup_idx on ${points} (${c("metric")}, ${c("grain")}, ${c("bucketStart")});
`
    : "";
  const series =
    metrics.length === 0
      ? ""
      : `  case p_metric
${metrics.map((metric) => seriesBranch(ctx, metric, names)).join("\n")}
    else
      ${unknown}
  end case;`;
  const value =
    metrics.length === 0
      ? ""
      : `  case p_metric
${metrics.map((metric) => valueBranch(ctx, metric, names)).join("\n")}
    else
      ${unknown}
  end case;`;
  const rollups = metrics
    .filter((metric) => storedGrains(metric).length > 0)
    .map((metric) => rollupBranch(ctx, metric, names));
  return `${schemaPreamble(ctx)}
${tables}
-- Re-aggregates the window [since, until), default the last ${window}, so
-- rows that arrive late or change land in their buckets. Run it from cron or
-- a job; metricsSink runs it for the window of each event.
create or replace function ${fn("metrics_rollup")}(
  p_metric text default null,
  p_since timestamptz default null,
  p_until timestamptz default null
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_since timestamptz := coalesce(p_since, now() - interval '${window}');
  v_until timestamptz := coalesce(p_until, now());
  v_from timestamptz;
  v_to timestamptz;
  v_rows integer;
  v_total integer := 0;
begin
  if p_metric is not null and p_metric <> all (${keys}) then
    ${unknown}
  end if;
  if v_until <= v_since then
    return 0;
  end if;
  perform pg_advisory_xact_lock(hashtext('better_supabase.metrics_rollup'));
${rollups.join("\n")}
  return v_total;
end;
$$;
${serviceGrant(`${fn("metrics_rollup")}(text, timestamptz, timestamptz)`)}

-- One bucket per grain from [from, until), as { bucket, value, count } and
-- { groups } with group_by. Reads metric_points at a stored grain that
-- divides the requested one, otherwise the table.
create or replace function ${fn("metric_series")}(
  p_metric text,
  p_tenant ${ctx.idType},
  p_from timestamptz,
  p_until timestamptz,
  p_grain text default 'day',
  p_dims jsonb default '{}'::jsonb,
  p_group_by text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_source text;
  v_start timestamptz;
  v_buckets integer;
begin
  if p_grain is null or p_grain <> all (${grains}) then
    ${fail("METRIC_GRAIN_INVALID", "grain must be hour, day, week or month", "22023")}
  end if;
  if p_from is null or p_until is null or p_until <= p_from then
    ${fail("METRIC_RANGE_INVALID", "the range needs a start before its end", "22023")}
  end if;
${series || `  ${unknown}`}
end;
$$;
${userGrant(`${fn("metric_series")}(text, ${ctx.idType}, timestamptz, timestamptz, text, jsonb, text)`)}

-- The total over [from, until), as { value, count }, from the finest stored
-- grain (whole buckets) or the table.
create or replace function ${fn("metric_value")}(
  p_metric text,
  p_tenant ${ctx.idType},
  p_from timestamptz,
  p_until timestamptz,
  p_dims jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_source text;
begin
  if p_from is null or p_until is null or p_until <= p_from then
    ${fail("METRIC_RANGE_INVALID", "the range needs a start before its end", "22023")}
  end if;
${value || `  ${unknown}`}
end;
$$;
${userGrant(`${fn("metric_value")}(text, ${ctx.idType}, timestamptz, timestamptz, jsonb)`)}

-- The declared metrics, for pickers and chart labels.
create or replace function ${fn("metric_definitions")}()
returns jsonb
language sql
immutable
set search_path = ''
as $$ select ${definitionsJson(metrics)} $$;
${userGrant(`${fn("metric_definitions")}()`)}
`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  return [
    {
      name: "metrics_rollup",
      args: ["text", "timestamptz", "timestamptz"],
      returns: "integer",
    },
    {
      name: "metric_series",
      args: [
        "text",
        ctx.idType,
        "timestamptz",
        "timestamptz",
        "text",
        "jsonb",
        "text",
      ],
      returns: "jsonb",
    },
    {
      name: "metric_value",
      args: ["text", ctx.idType, "timestamptz", "timestamptz", "jsonb"],
      returns: "jsonb",
    },
    { name: "metric_definitions", args: [], returns: "jsonb" },
  ];
}

export const METRICS: ModuleDefinition = {
  name: "metrics",
  title: "Metrics",
  description:
    "Metrics declared with defineMetric over a table (count, sum or avg per time bucket and dimension), rolled up into metric_points or read from the table, with metric_series and metric_value checked against a permission in the tenant.",
  requires: ["tenant", "access"],
  integrates: ["usage", "jobs"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
