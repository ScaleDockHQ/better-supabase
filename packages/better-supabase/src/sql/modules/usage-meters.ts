import type { ModuleContext } from "../context.ts";

import { isRecord } from "../../core/guards.ts";
import { quotedTable } from "../shared.ts";

export const METER = `'^[a-z][a-z0-9_.:-]{0,63}$'`;

const METER_KEY = /^[a-z][a-z0-9_.:-]{0,63}$/;

/** One meter in `options.meters`: how to show it. */
export interface UsageMeter {
  /** What one unit is, such as `tokens`, `requests` or `bytes`. */
  readonly unit?: string;
  /** A group for display, such as `ai` or `storage`. */
  readonly category?: string;
  readonly label?: string;
  /**
   * `counter` (default) adds recorded quantities, `distinct` counts each
   * subject once per period (`track_usage`) and `computed` is a gauge a query
   * reports per tenant (`usage_refresh`).
   */
  readonly kind?: "counter" | "distinct" | "computed";
  /** The window a distinct or computed meter measures; default `month`. */
  readonly period?: string;
  /** A computed meter's SQL: a select of `(tenant, value)` rows. */
  readonly query?: string;
}

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

    if (value === undefined) {
      return undefined;
    }

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

export const isMeterTable = (
  value: Readonly<Record<string, UsageMeter>> | MeterTable,
): value is MeterTable => "table" in value && typeof value.table === "string";

export const qualifiedTable = (table: string): string => quotedTable(table);

/**
 * `options.meters`: the meter catalog, inline or `{ table }` for one the app
 * keeps in a table; with either, unknown meters are refused.
 */
export function metersOf(
  ctx: ModuleContext,
): Readonly<Record<string, UsageMeter>> | MeterTable | undefined {
  const where = "blocks.usage.options.meters";
  const option = ctx.option("meters");

  if (option === undefined) {
    return undefined;
  }

  if (isRecord(option) && typeof option["table"] === "string") {
    return meterTableOf(where, option);
  }

  const out: Record<string, UsageMeter> = {};

  if (!isRecord(option)) {
    throw new TypeError(
      `${where} must be an object of meter to { unit?, category?, label? }`,
    );
  }

  for (const [meter, value] of Object.entries(option)) {
    if (!METER_KEY.test(meter)) {
      throw new TypeError(`${where}: "${meter}" is not a meter name`);
    }

    if (!isRecord(value)) {
      throw new TypeError(`${where}.${meter} must be an object`);
    }

    const entry: Record<string, string> = {};

    for (const [key, text] of Object.entries(value)) {
      if (
        !["unit", "category", "label", "kind", "period", "query"].includes(
          key,
        ) ||
        typeof text !== "string"
      ) {
        throw new TypeError(
          `${where}.${meter}.${key}: use unit, category, label, kind, period and query as strings`,
        );
      }

      if (
        key === "kind" &&
        !["counter", "distinct", "computed"].includes(text)
      ) {
        throw new TypeError(
          `${where}.${meter}.kind must be counter, distinct or computed`,
        );
      }

      if (
        key === "period" &&
        !["day", "week", "month", "year", "billing"].includes(text)
      ) {
        throw new TypeError(
          `${where}.${meter}.period must be day, week, month, year or billing`,
        );
      }

      if (key === "query" && (text.includes(";") || text.includes("$$"))) {
        throw new TypeError(
          `${where}.${meter}.query must be one select without ";" or "$$"`,
        );
      }

      entry[key] = text;
    }

    if (entry["kind"] === "computed" && entry["query"] === undefined) {
      throw new TypeError(`${where}.${meter}: a computed meter needs a query`);
    }

    if (entry["query"] !== undefined && entry["kind"] !== "computed") {
      throw new TypeError(`${where}.${meter}: query needs kind "computed"`);
    }

    // SAFETY: kind, period and query were checked above; entry holds only strings.
    out[meter] = entry;
  }

  return out;
}

/** The catalog `usage_meters()` returns: every meter without its query. */
export function publicCatalog(
  meters: Readonly<Record<string, UsageMeter>> | undefined,
): Record<string, Omit<UsageMeter, "query">> {
  const out: Record<string, Omit<UsageMeter, "query">> = {};

  for (const [name, info] of Object.entries(meters ?? {})) {
    const { query: _query, ...shown } = info;

    out[name] = shown;
  }

  return out;
}
