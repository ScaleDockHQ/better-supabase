import type { AppColumnFormat } from "../preset/index.ts";
import type { AppColumn, AppColumnType } from "./design.ts";

import { isAppDefault } from "../preset/index.ts";

/** The most options a select takes, and the longest option. */
const MAX_OPTIONS = 100;
const MAX_OPTION = 100;

const AUTH_USERS = "auth.users";

/** The column types each format fits, as `appTables` checks them. */
const FORMAT_TYPES: Readonly<
  Record<AppColumnFormat, readonly AppColumnType[]>
> = {
  email: ["text"],
  url: ["text"],
  phone: ["text"],
  long_text: ["text"],
  color: ["text"],
  rating: ["integer", "bigint"],
  percent: ["integer", "numeric"],
  currency: ["bigint"],
};

const FORMAT_LABELS: Readonly<Record<AppColumnFormat, string>> = {
  email: "email",
  url: "url",
  phone: "phone",
  long_text: "long text",
  color: "color",
  rating: "rating",
  percent: "percent",
  currency: "money",
};

const NUMBER_TYPES: ReadonlySet<AppColumnType> = new Set([
  "integer",
  "bigint",
  "numeric",
]);

const CONTROL = /\p{Cc}/u;

/** An app column under construction. */
type DraftColumn = { -readonly [K in keyof AppColumn]: AppColumn[K] };

/**
 * Whether a column signed-in users can't write is required with no default,
 * which `appTables` refuses: nobody but the server could insert a row.
 */
export function lockedWithoutDefault(column: AppColumn): boolean {
  return (
    column.access !== undefined &&
    column.nullable === false &&
    column.default === undefined &&
    column.identity !== true
  );
}

/**
 * Whether a column can be encrypted: not a `text[]`, and no unique key,
 * reference or identity, which only work on the stored value.
 */
export function encryptable(column: AppColumn): boolean {
  return (
    column.type !== "text[]" &&
    column.unique !== true &&
    column.references === undefined &&
    column.identity !== true
  );
}

/** Whether `min` and `max` apply to a `type` column, as a value or a length. */
export function takesBounds(type: AppColumnType): boolean {
  return type === "text" || NUMBER_TYPES.has(type);
}

/** Whether a bound of a `type` column has to be a whole number. */
function wholeBounds(type: AppColumnType): boolean {
  return type !== "numeric";
}

function fitsBound(
  type: AppColumnType,
  value: number | undefined,
): value is number {
  return (
    value !== undefined &&
    takesBounds(type) &&
    (!wholeBounds(type) || Number.isInteger(value)) &&
    (type !== "text" || value >= 0)
  );
}

/**
 * A column without the keys its type can't take: a format of another type,
 * options outside text and text[], bounds that don't apply, an identity outside
 * integer and bigint, and a default an identity or the type refuses.
 */
export function fitted(column: AppColumn): AppColumn {
  const {
    format,
    options,
    min,
    max,
    identity,
    default: fallback,
    nullable,
    encrypted,
    ...rest
  } = column;

  const { type } = column;

  const counted =
    identity === true && (type === "integer" || type === "bigint");

  const next: DraftColumn = { ...rest };

  if (nullable !== undefined && !(counted && nullable)) {
    next.nullable = nullable;
  }

  if (fallback !== undefined && !counted && isAppDefault(type, fallback)) {
    next.default = fallback;
  }

  if (format !== undefined && FORMAT_TYPES[format].includes(type)) {
    next.format = format;
  }

  if (options !== undefined && (type === "text" || type === "text[]")) {
    next.options = options;
  }

  if (fitsBound(type, min)) {
    next.min = min;
  }

  if (fitsBound(type, max)) {
    next.max = max;
  }

  if (counted) {
    next.identity = true;
  }

  if (encrypted === true && encryptable(next)) {
    next.encrypted = true;
  }

  return next;
}

/** Why `option` can't join a select's `options`, or `undefined` when it can. */
export function optionError(
  options: readonly string[],
  option: string,
): string | undefined {
  if (option === "") {
    return "Enter an option.";
  }

  if (option.length > MAX_OPTION) {
    return `Use at most ${MAX_OPTION} characters.`;
  }

  if (CONTROL.test(option)) {
    return "Leave out line breaks and tabs.";
  }

  if (options.includes(option)) {
    return `${option} is already an option.`;
  }

  if (options.length >= MAX_OPTIONS) {
    return `A select takes at most ${MAX_OPTIONS} options.`;
  }

  return undefined;
}

/**
 * Why `value` can't be a bound of `column`, or `undefined` when it can (an
 * empty value clears it).
 */
export function boundError(
  column: AppColumn,
  side: "min" | "max",
  value: string,
): string | undefined {
  const trimmed = value.trim();

  if (trimmed === "") {
    return undefined;
  }

  const number = Number(trimmed);

  if (!Number.isFinite(number)) {
    return "Enter a number.";
  }

  if (column.type === "text" && (!Number.isInteger(number) || number < 0)) {
    return "A length is a whole number of 0 or more.";
  }

  if (wholeBounds(column.type) && !Number.isInteger(number)) {
    return `A ${column.type} bound is a whole number.`;
  }

  if (side === "min" && column.max !== undefined && number > column.max) {
    return `Keep it at or below the largest value, ${column.max}.`;
  }

  if (side === "max" && column.min !== undefined && number < column.min) {
    return `Keep it at or above the smallest value, ${column.min}.`;
  }

  return undefined;
}

/** `column` with its bounds replaced; a bound left out is removed. */
export function withBounds(
  column: AppColumn,
  bounds: {
    readonly min?: number | undefined;
    readonly max?: number | undefined;
  },
): AppColumn {
  const { min: _min, max: _max, ...rest } = column;
  const next: DraftColumn = { ...rest };

  if (bounds.min !== undefined) {
    next.min = bounds.min;
  }

  if (bounds.max !== undefined) {
    next.max = bounds.max;
  }

  return next;
}

/**
 * What the canvas shows for a column that is more than its type, such as an
 * email or a select.
 */
export function columnLabel(column: AppColumn): string | undefined {
  if (column.identity === true) {
    return "autonumber";
  }

  if (column.options !== undefined) {
    return column.type === "text[]" ? "multi-select" : "select";
  }

  if (
    column.references?.block === undefined &&
    column.references?.table === AUTH_USERS
  ) {
    return "person";
  }

  return column.format === undefined ? undefined : FORMAT_LABELS[column.format];
}
