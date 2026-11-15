import type { SortingState } from "@tanstack/react-table";
import type { PageSort } from "better-supabase/blocks";

import { MAX_PAGE_SORTS } from "better-supabase/blocks";

/** The columns the register sorts by, each with the direction it starts in. */
const START = {
  residualScore: "desc",
  number: "asc",
  nextReviewOn: "asc",
} as const satisfies Readonly<Record<string, "asc" | "desc">>;

function isRiskSort(by: string): by is keyof typeof START {
  return by in START;
}

/** The sort the register applies without one in the URL. */
export const RISK_DEFAULT_SORT = "residualScore";

/** The direction a term sorts in: the one it names, or its column's start. */
export function directionOf(term: PageSort): "asc" | "desc" {
  if (term.direction !== undefined) {
    return term.direction;
  }

  return isRiskSort(term.by) ? START[term.by] : "asc";
}

/**
 * The terms of a `sort` URL value (`residualScore:desc,number`), declared
 * columns only.
 */
export function parseRiskSort(sort: string): readonly PageSort[] {
  const terms: PageSort[] = [];

  for (const part of sort.split(",")) {
    const [by = "", direction] = part.split(":");

    if (isRiskSort(by) && !terms.some((term) => term.by === by)) {
      terms.push(
        direction === "asc" || direction === "desc"
          ? { by, direction }
          : { by },
      );
    }
  }

  return terms.slice(0, MAX_PAGE_SORTS);
}

/** The `sort` URL value of some terms. */
export function formatRiskSort(terms: readonly PageSort[]): string {
  return terms
    .map((term) =>
      term.direction === undefined ? term.by : `${term.by}:${term.direction}`,
    )
    .join(",");
}

/**
 * The sort after a header click on `by`. A plain click sorts by that column
 * alone, and flips it when it already leads. `extend` (shift-click) keeps the
 * other terms: it flips the column when it is a term and appends it otherwise,
 * up to the most terms a list accepts.
 */
export function clickRiskSort(
  sort: string,
  by: string,
  extend: boolean,
): string {
  const terms = parseRiskSort(sort.length === 0 ? RISK_DEFAULT_SORT : sort);

  const flipped = (term: PageSort): PageSort => ({
    by: term.by,
    direction: directionOf(term) === "asc" ? "desc" : "asc",
  });

  const at = terms.findIndex((term) => term.by === by);

  if (extend) {
    if (at !== -1) {
      return formatRiskSort(
        terms.map((term, index) => (index === at ? flipped(term) : term)),
      );
    }

    return formatRiskSort(
      terms.length >= MAX_PAGE_SORTS ? terms : [...terms, { by }],
    );
  }

  const lead = terms.at(0);

  return formatRiskSort([lead?.by === by ? flipped(lead) : { by }]);
}

/** The header sort state of a `sort` URL value. */
export function sortingOf(sort: string): SortingState {
  return parseRiskSort(sort.length === 0 ? RISK_DEFAULT_SORT : sort).map(
    (term) => ({ id: term.by, desc: directionOf(term) === "desc" }),
  );
}

/**
 * The `sort` URL value of a header sort state. No terms, or the default one
 * alone, is the default sort, which the URL leaves out.
 */
export function sortFromSorting(sorting: SortingState): string {
  const terms = sorting.map((term): PageSort => ({
    by: term.id,
    direction: term.desc ? "desc" : "asc",
  }));

  const only = terms.at(0);

  if (
    terms.length === 0 ||
    (terms.length === 1 &&
      only?.by === RISK_DEFAULT_SORT &&
      directionOf({ by: RISK_DEFAULT_SORT }) === only.direction)
  ) {
    return RISK_DEFAULT_SORT;
  }

  return formatRiskSort(terms);
}
