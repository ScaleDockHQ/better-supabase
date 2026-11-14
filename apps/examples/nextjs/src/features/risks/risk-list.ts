import type { PageOptions } from "better-supabase/blocks";
import type { RecordListUrl } from "better-supabase/react";

import * as v from "valibot";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

import { risksList } from "@/lib/supabase/pages/risks.list";

/** The facets of the risk list, each one a single value in the block's page. */
const RISK_FACETS = ["status", "category", "band"] as const;

/** The sort the block applies without one: the highest residual score first. */
export const RISK_DEFAULT_SORT = "residualScore";

type DraftQuery = {
  -readonly [K in keyof RecordListUrlQuery]: RecordListUrlQuery[K];
};

type DraftOptions = { -readonly [K in keyof PageOptions]: PageOptions[K] };

const FACETS = RISK_FACETS.map((key) => ({ key }));

const cursorSchema = v.array(v.string());

/**
 * The cursor travels in the list state as JSON, and in the URL as `after`
 * values.
 */
function cursorOf(value: string): readonly string[] | undefined {
  try {
    const parsed = v.safeParse(cursorSchema, JSON.parse(value));

    return parsed.success ? parsed.output : undefined;
  } catch {
    return undefined;
  }
}

/** The block's page options for a list state. */
export function riskPageOptions(
  query: Partial<RecordListUrlQuery>,
  limit?: number,
): PageOptions {
  const filters: Record<string, readonly string[]> = {};

  for (const key of RISK_FACETS) {
    const values = query.facets?.[key];

    if (values !== undefined && values.length > 0) {
      filters[key] = values;
    }
  }

  const options: DraftOptions = {};
  const after = query.after === undefined ? undefined : cursorOf(query.after);

  if (limit !== undefined) {
    options.limit = limit;
  }

  if (query.q !== undefined && query.q !== "") {
    options.q = query.q;
  }

  if (query.sort !== undefined && query.sort !== RISK_DEFAULT_SORT) {
    options.sort = { by: query.sort };
  }

  if (Object.keys(filters).length > 0) {
    options.filters = filters;
  }

  if (after !== undefined) {
    options.after = after;
  }

  return options;
}

/**
 * The URL state of the risk list (`?q=&sort=&status=&category=&band=&after=`).
 * The generated `risksList` (ADR 0859) reads and checks it against the block's
 * declared sorts, facets and search; this maps its page options to the list
 * kit's state and back.
 */
export const riskList: RecordListUrl<RecordListUrlQuery> = {
  defaults: { sort: RISK_DEFAULT_SORT, facets: {} },
  facets: FACETS,
  parse(input) {
    const parsed = risksList.parse(input);

    if (!parsed.ok) {
      return { ok: false };
    }

    const { q, sort, filters, after } = parsed.value;

    const value: DraftQuery = {
      sort: sort?.by ?? RISK_DEFAULT_SORT,
      facets: Object.fromEntries(
        RISK_FACETS.map((key) => [key, filters?.[key]]),
      ),
    };

    if (q !== undefined) {
      value.q = q;
    }

    if (after !== undefined) {
      value.after = JSON.stringify(after);
    }

    return { ok: true, value };
  },
  toSearchParams(query) {
    return risksList.toSearchParams(riskPageOptions(query));
  },
};
