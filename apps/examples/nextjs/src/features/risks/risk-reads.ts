import type { PageOptions, PageSort } from "better-supabase/blocks";
import type { EntityListReads } from "better-supabase/list";

import { sortsOf } from "better-supabase/blocks";

import type { AppDb } from "@/lib/block-entity-page";

import type { RiskRow } from "./risk-rows";

import { toRiskRows } from "./risk-rows";
import { directionOf } from "./risk-sort";

type DraftOptions = { -readonly [K in keyof PageOptions]: PageOptions[K] };

const PAGE_SIZE = 50;

/** The block's own page size cap per read. */
const READ_SIZE = 200;

/** The most risks one list reads, so a register that outgrows it still answers. */
const MAX_ROWS = 2000;

const byNumber = (a: string, b: string): number =>
  a.localeCompare(b, undefined, { numeric: true });

/**
 * How each sort term compares two risks: a missing score or review date sorts
 * first.
 */
const COMPARERS = new Map<string, (a: RiskRow, b: RiskRow) => number>([
  ["residualScore", (a, b) => (a.score ?? -1) - (b.score ?? -1)],
  ["number", (a, b) => byNumber(a.number, b.number)],
  [
    "nextReviewOn",
    (a, b) => (a.nextReviewOn ?? "").localeCompare(b.nextReviewOn ?? ""),
  ],
]);

function compare(a: RiskRow, b: RiskRow, term: PageSort): number {
  const order = COMPARERS.get(term.by)?.(a, b) ?? 0;

  return directionOf(term) === "desc" ? -order : order;
}

/**
 * The risks of a page in the order of every sort term, then by number. The
 * block's `page` orders by the first term only (ADR 0896), so the register
 * reads its rows through this module instead.
 */
export function sortRisks(
  rows: readonly RiskRow[],
  terms: readonly PageSort[],
): readonly RiskRow[] {
  return rows.toSorted((a, b) => {
    for (const term of terms) {
      const order = compare(a, b, term);

      if (order !== 0) {
        return order;
      }
    }

    return byNumber(a.number, b.number);
  });
}

/**
 * The reads module of the risk register (ADR 0895). It asks the block for the
 * risks that match the search and filters, orders them by every sort term and
 * pages them with an offset cursor. The facets are the block's.
 */
export function riskReads(db: AppDb): EntityListReads<RiskRow> {
  return {
    async page(options: PageOptions) {
      const terms = sortsOf(options.sort);
      const items = [];

      let after: readonly string[] | undefined;

      do {
        const draft: DraftOptions = { limit: READ_SIZE };

        if (options.q !== undefined) {
          draft.q = options.q;
        }

        if (options.filters !== undefined) {
          draft.filters = options.filters;
        }

        if (after !== undefined) {
          draft.after = after;
        }

        const read = await db.risks.page(draft);

        if (!read.ok) {
          return read;
        }

        items.push(...read.data.items);
        after = read.data.hasMore
          ? (read.data.nextCursor ?? undefined)
          : undefined;
      } while (after !== undefined && items.length < MAX_ROWS);

      const matrices = await db.risks.matrices();

      if (!matrices.ok) {
        return matrices;
      }

      const sorted = sortRisks(toRiskRows(items, matrices.data), terms);
      const limit = options.limit ?? PAGE_SIZE;
      const start = Number(options.after?.[0] ?? 0);
      const end = start + limit;

      return {
        ok: true as const,
        data: {
          items: sorted.slice(start, end),
          hasMore: end < sorted.length,
          nextCursor: end < sorted.length ? [String(end)] : null,
          sorted: { applied: terms, ignored: [] },
        },
        error: null,
      };
    },
    facets(options) {
      return db.risks.facets(options);
    },
  };
}
