import type { FilterQuery } from "./filter-query.ts";
import type { FacetInfo, ListSearchParams, ParserSpec } from "./list-query.ts";

import { decodeFilterQuery, encodeFilterQuery } from "./filter-query.ts";

/** Facet value meaning "not set": filters with `is null`. */
export const UNSET = "__unset__";

/** Longest `filter` URL parameter, in characters. */
export const MAX_FILTER_PARAM = 16_384;

export function validTimeZone(timeZone: string): boolean {
  try {
    return (
      new Intl.DateTimeFormat("en", { timeZone }).resolvedOptions().timeZone !==
      ""
    );
  } catch {
    return false;
  }
}

export function first(
  value: string | readonly string[] | undefined,
): string | undefined {
  return typeof value === "string" ? value : value?.[0];
}

export function all(value: string | readonly string[] | undefined): string[] {
  const values = typeof value === "string" ? [value] : [...(value ?? [])];

  return values.flatMap((entry) =>
    entry.split(",").flatMap((part) => {
      const trimmed = part.trim();

      return trimmed === "" ? [] : [trimmed];
    }),
  );
}

const isParamValue = (value: unknown): boolean =>
  value === undefined ||
  typeof value === "string" ||
  (Array.isArray(value) && value.every((entry) => typeof entry === "string"));

export function isSearchParams(value: object): value is ListSearchParams {
  return (
    value instanceof URLSearchParams ||
    (!("facets" in value && typeof value.facets === "object") &&
      Object.values(value).every(isParamValue))
  );
}

export function readRecord(
  input: ListSearchParams,
): Record<string, string | readonly string[] | undefined> {
  if (!(input instanceof URLSearchParams)) {
    return input;
  }

  const out: Record<string, string[]> = {};

  for (const [key, value] of input) {
    (out[key] ??= []).push(value);
  }

  return out;
}

export function toInt(raw: unknown): number | undefined {
  if (typeof raw === "number") {
    return raw;
  }

  if (typeof raw !== "string" || !/^\d+$/.test(raw)) {
    return Number.NaN;
  }

  return Number(raw);
}

export const listParser: ParserSpec<readonly string[]> = {
  parse: (value) => {
    const values = all(value);

    return values.length > 0 ? values : null;
  },
  serialize: (values) => values.join(","),
};

export const intParser: ParserSpec<number> = {
  parse: (value) => (/^\d+$/.test(value) ? Number(value) : null),
  serialize: String,
};

export const filterParser: ParserSpec<FilterQuery> = {
  parse: (value) => {
    const decoded =
      value.length > MAX_FILTER_PARAM ? undefined : decodeFilterQuery(value);

    const group =
      typeof decoded === "object" &&
      decoded !== null &&
      "type" in decoded &&
      decoded.type === "group";

    // SAFETY: a decoded group; `parse` checks every node before it is used.
    return group ? (decoded as FilterQuery) : null;
  },
  serialize: encodeFilterQuery,
  eq: (a, b) => encodeFilterQuery(a) === encodeFilterQuery(b),
};

/** Rows per value of one facet, from its grouped aggregate. */
export function countsOf(
  facet: FacetInfo,
  groups: readonly Record<string, unknown>[],
): Record<string, number> {
  const counts: Record<string, number> = {};

  for (const value of facet.values ?? []) {
    counts[value] = 0;
  }

  for (const group of groups) {
    const raw = group[facet.column];
    const key = raw === null || raw === undefined ? UNSET : String(raw);
    counts[key] = (counts[key] ?? 0) + Number(group["_count"] ?? 0);
  }

  return counts;
}

export const facetSchema = (facet: FacetInfo): Record<string, unknown> => ({
  type: "array",
  items: {
    type: "string",
    ...(facet.values
      ? { enum: [...facet.values, ...(facet.nullable ? [UNSET] : [])] }
      : {}),
  },
  uniqueItems: true,
});
