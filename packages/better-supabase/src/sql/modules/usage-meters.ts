import type { ModuleContext } from "../context.ts";

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
