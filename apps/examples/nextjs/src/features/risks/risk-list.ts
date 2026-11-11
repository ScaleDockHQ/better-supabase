import type { RecordListUrl } from "better-supabase/react";

import type { RecordListUrlQuery } from "@/components/record-list/record-list-types";

/** The facets of the risk list, each one a single value in the block's page. */
const RISK_FACETS = ["status", "category", "band"] as const;

type DraftQuery = {
  -readonly [K in keyof RecordListUrlQuery]: RecordListUrlQuery[K];
};

const FACETS = RISK_FACETS.map((key) => ({ key }));

const split = (value: string | null): string[] | undefined => {
  const values = value?.split(",").filter((item) => item !== "");

  return values !== undefined && values.length > 0 ? values : undefined;
};

/**
 * The URL state of the risk list (`?q=&status=&category=&band=&after=`). The
 * block's `risks.page` orders by residual score, so the list has no sort.
 */
export const riskList: RecordListUrl<RecordListUrlQuery> = {
  defaults: { sort: "risk", facets: {} },
  facets: FACETS,
  parse(input) {
    const value: DraftQuery = {
      sort: "risk",
      facets: Object.fromEntries(
        RISK_FACETS.map((key) => [key, split(input.get(key))]),
      ),
    };

    const q = input.get("q");
    const after = input.get("after");

    if (q !== null && q !== "") {
      value.q = q;
    }

    if (after !== null && after !== "") {
      value.after = after;
    }

    return { ok: true, value };
  },
  toSearchParams(query) {
    const params = new URLSearchParams();

    if (query.q !== undefined && query.q !== "") {
      params.set("q", query.q);
    }

    for (const key of RISK_FACETS) {
      const values = query.facets?.[key];

      if (values !== undefined && values.length > 0) {
        params.set(key, values.join(","));
      }
    }

    if (query.after !== undefined && query.after !== "") {
      params.set("after", query.after);
    }

    return params;
  },
};
