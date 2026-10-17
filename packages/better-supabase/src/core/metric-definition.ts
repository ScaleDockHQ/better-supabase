/** What a metric adds up per bucket. */
export type MetricMeasure =
  | "count"
  | { readonly sum: string }
  | { readonly avg: string };

/** The bucket sizes of a series. */
export const METRIC_GRAINS = ["hour", "day", "week", "month"] as const;
export type MetricGrain = (typeof METRIC_GRAINS)[number];

/** A literal a metric's rows must equal, such as `meter: "api_calls"`. */
export type MetricWhereValue = string | number | boolean | null;

/**
 * One metric over a table (`defineMetric`): what to measure, in which time
 * column, per tenant. The SQL module reads the same definitions from
 * `blocks.metrics.options.metrics`.
 */
export interface MetricDefinition<
  K extends string = string,
  D extends string = string,
> {
  /** Lowercase letters, digits and underscores. */
  readonly key: K;
  /** `schema.table`, or a table in `public`. */
  readonly table: string;
  readonly measure: MetricMeasure;
  /** The `timestamptz` column a row is bucketed by. */
  readonly timeColumn: string;
  /** Columns a series can filter and group by. */
  readonly dimensions?: readonly D[];
  /** The tenant column. Default `organization_id`. */
  readonly tenant?: string;
  /** The IANA time zone buckets start in. Default `UTC`. */
  readonly tz?: string;
  /** The key a caller needs in the tenant. Default `metrics.read`. */
  readonly permission?: string;
  /** Column equalities every counted row meets. */
  readonly where?: Readonly<Record<string, MetricWhereValue>>;
  /**
   * The grains `metric_points` keeps, default `["day"]`. `false` queries the
   * table directly, for small tables.
   */
  readonly rollup?: readonly MetricGrain[] | false;
  readonly label?: string;
  readonly unit?: string;
}

const KEY = /^[a-z][a-z0-9_]{0,62}$/;
const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/;
const TABLE = /^(?:[a-z_][a-z0-9_]{0,62}\.)?[a-z_][a-z0-9_]{0,62}$/;
const PERMISSION = /^[a-z][a-z0-9_.*-]{0,127}$/;

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function column(where: string, value: unknown): string {
  if (typeof value !== "string" || !COLUMN.test(value)) {
    throw new TypeError(`${where} must be a column name`);
  }
  return value;
}

function timeZone(where: string, value: unknown): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`${where} must be an IANA time zone such as UTC`);
  }
  try {
    Intl.DateTimeFormat("en", { timeZone: value }).resolvedOptions();
  } catch {
    throw new TypeError(`${where}: "${value}" is not an IANA time zone`);
  }
  return value;
}

function measureOf(where: string, value: unknown): MetricMeasure {
  if (value === "count") {
    return "count";
  }
  if (isObject(value)) {
    const keys = Object.keys(value);
    if (keys.length === 1 && (keys[0] === "sum" || keys[0] === "avg")) {
      const name = column(`${where}.${keys[0]}`, value[keys[0]]);
      return keys[0] === "sum" ? { sum: name } : { avg: name };
    }
  }
  throw new TypeError(
    `${where} must be "count", { sum: "column" } or { avg: "column" }`,
  );
}

/** Checks one definition and returns it with its defaults left unset. */
export function checkMetric(
  value: unknown,
  where = "metric",
): MetricDefinition {
  assertMetric(value, where);
  return value;
}

function assertMetric(
  value: unknown,
  where: string,
): asserts value is MetricDefinition {
  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object`);
  }
  const key = value["key"];
  if (typeof key !== "string" || !KEY.test(key)) {
    throw new TypeError(
      `${where}.key must be lowercase letters, digits and underscores`,
    );
  }
  const at = `${where} ${key}`;
  const table = value["table"];
  if (typeof table !== "string" || !TABLE.test(table)) {
    throw new TypeError(`${at}.table must be "table" or "schema.table"`);
  }
  const dimensions = value["dimensions"] ?? [];
  if (!Array.isArray(dimensions)) {
    throw new TypeError(`${at}.dimensions must be a list of columns`);
  }
  const dims = dimensions.map((name: unknown) =>
    column(`${at}.dimensions`, name),
  );
  if (new Set(dims).size !== dims.length) {
    throw new TypeError(`${at}.dimensions lists a column twice`);
  }
  const rollup = value["rollup"];
  if (
    rollup !== undefined &&
    rollup !== false &&
    !(
      Array.isArray(rollup) &&
      rollup.length > 0 &&
      rollup.every((grain: unknown) =>
        METRIC_GRAINS.some((known) => known === grain),
      )
    )
  ) {
    throw new TypeError(
      `${at}.rollup must be false or a list of ${METRIC_GRAINS.join(", ")}`,
    );
  }
  const permission = value["permission"];
  if (
    permission !== undefined &&
    (typeof permission !== "string" || !PERMISSION.test(permission))
  ) {
    throw new TypeError(`${at}.permission must be a permission key`);
  }
  const filter = value["where"];
  if (filter !== undefined) {
    if (!isObject(filter)) {
      throw new TypeError(`${at}.where must be an object of column to value`);
    }
    for (const [name, literal] of Object.entries(filter)) {
      column(`${at}.where`, name);
      if (
        !(
          literal === null ||
          typeof literal === "string" ||
          typeof literal === "boolean" ||
          (typeof literal === "number" && Number.isFinite(literal))
        )
      ) {
        throw new TypeError(
          `${at}.where.${name} must be a string, number, boolean or null`,
        );
      }
    }
  }
  for (const name of ["label", "unit"] as const) {
    if (value[name] !== undefined && typeof value[name] !== "string") {
      throw new TypeError(`${at}.${name} must be a string`);
    }
  }
  measureOf(`${at}.measure`, value["measure"]);
  column(`${at}.timeColumn`, value["timeColumn"]);
  if (value["tenant"] !== undefined) {
    column(`${at}.tenant`, value["tenant"]);
  }
  if (value["tz"] !== undefined) {
    timeZone(`${at}.tz`, value["tz"]);
  }
}

/**
 * Declares a metric. The key and dimensions are kept as literal types, so
 * `createMetrics({ metrics })` types `series("revenue", ...)`.
 *
 * ```ts
 * export const revenue = defineMetric({
 *   key: "revenue",
 *   table: "public.orders",
 *   measure: { sum: "total" },
 *   timeColumn: "placed_at",
 *   dimensions: ["channel"],
 * });
 * ```
 */
export function defineMetric<
  const K extends string,
  const D extends string = never,
>(definition: MetricDefinition<K, D>): MetricDefinition<K, D> {
  checkMetric(definition, "defineMetric");
  return definition;
}

/** `options.metrics`: a list of definitions, or an object of key to definition. */
export function metricsOf(
  value: unknown,
  where = "blocks.metrics.options.metrics",
): readonly MetricDefinition[] {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value) && !isObject(value)) {
    throw new TypeError(
      `${where} must be a list of defineMetric() definitions or an object of key to definition`,
    );
  }
  const entries: unknown[] = Array.isArray(value)
    ? value
    : Object.entries(value).map(([key, entry]) =>
        isObject(entry) ? { key, ...entry } : entry,
      );
  const metrics = entries.map((entry, index) =>
    checkMetric(entry, `${where}[${String(index)}]`),
  );
  const keys = new Set<string>();
  for (const metric of metrics) {
    if (keys.has(metric.key)) {
      throw new TypeError(`${where}: metric "${metric.key}" is defined twice`);
    }
    keys.add(metric.key);
  }
  return metrics;
}

/** The grain a stored rollup at `stored` can be summed into. */
export function grainDivides(stored: MetricGrain, grain: MetricGrain): boolean {
  switch (stored) {
    case "hour": {
      return true;
    }
    case "day": {
      return grain !== "hour";
    }
    case "week": {
      return grain === "week";
    }
    case "month": {
      return grain === "month";
    }
    default: {
      const never: never = stored;
      return never;
    }
  }
}
