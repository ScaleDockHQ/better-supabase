"use client";

import { useMemo } from "react";

/**
 * The list a record list's URL state belongs to: a `defineListQuery`
 * definition, or a `defineRecordList`'s `list`.
 */
export interface RecordListUrl<Q> {
  /** The query with every default, for URL state the list refuses. */
  readonly defaults: Q;
  parse(
    input: URLSearchParams,
  ): { readonly ok: true; readonly value: Q } | { readonly ok: false };
  toSearchParams(query: Partial<Q>): URLSearchParams;
}

/** The URL state nuqs holds: one key per parser, `null` when absent. */
export type RecordListUrlState = Readonly<Record<string, unknown>>;

/**
 * What nuqs' `useQueryStates(list.nuqs(createParser))` returns: the state and
 * its setter.
 */
export type RecordListQueryStates = readonly [
  RecordListUrlState,
  (patch: Readonly<Record<string, unknown>>) => unknown,
];

/** What `useRecordListState` returns. */
export interface RecordListState<Q> {
  /** The URL state, one key per list parameter (`null` when unset). */
  readonly state: RecordListUrlState;
  /**
   * The URL state parsed by the list, defaults filled in and typed; the
   * defaults alone when the URL holds a value the list refuses.
   */
  readonly query: Q;
  /**
   * The URL state as query params, defaults left out, for the list route or
   * `recordList.load` on the server.
   */
  readonly searchParams: URLSearchParams;
  /**
   * Sets keys and goes back to the first page, as a filter or sort change
   * should.
   */
  set(patch: Readonly<Record<string, unknown>>): void;
  /** Moves to a page number (offset lists) or an `after` cursor (cursor lists). */
  setPage(page: number | string | null): void;
  /** Clears every key the list owns. */
  reset(): void;
}

const present = (state: RecordListUrlState): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(state).filter(
      ([, value]) => value !== null && value !== undefined,
    ),
  );

/**
 * A record list's URL state from nuqs, with the query params the server parses.
 * Filter and sort changes reset the page. better-supabase doesn't import nuqs:
 * pass what `useQueryStates` returns.
 *
 * ```tsx
 * import { createParser, useQueryStates } from "nuqs";
 *
 * const parsers = customerList.nuqs(createParser);
 *
 * function Customers() {
 *   const list = useRecordListState(customerList, useQueryStates(parsers));
 *   list.set({ q: "acme" });
 *   // fetch(`/api/customers/list?${list.searchParams}`)
 * }
 * ```
 */
export function useRecordListState<Q>(
  list: RecordListUrl<Q>,
  queryStates: RecordListQueryStates,
): RecordListState<Q> {
  const [state, setState] = queryStates;

  return useMemo(() => {
    // SAFETY: the state holds the values the list's own parsers produced.
    const searchParams = list.toSearchParams(present(state) as Partial<Q>);
    const parsed = list.parse(searchParams);
    const query = parsed.ok ? parsed.value : list.defaults;

    return {
      state,
      query,
      searchParams,
      set(patch) {
        void setState({ ...patch, page: null, after: null });
      },
      setPage(page) {
        void setState(
          typeof page === "string"
            ? { page: null, after: page }
            : { page, after: null },
        );
      },
      reset() {
        void setState(
          Object.fromEntries(Object.keys(state).map((key) => [key, null])),
        );
      },
    };
  }, [list, state, setState]);
}
