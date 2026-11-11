"use client";

import { useQuery } from "@tanstack/react-query";

import type { RecordListPage } from "./record-list-types";

export interface RecordListPageState<Row> {
  readonly page: RecordListPage<Row> | undefined;
  /** A request is running; the previous rows stay on screen meanwhile. */
  readonly pending: boolean;
  readonly failed: boolean;
  readonly retry: () => void;
}

/**
 * The rows for a list's URL state. The default state (an empty query string)
 * shows the first page the server rendered, so a navigation paints without a
 * request; every other state asks the list route and keeps the previous rows
 * until the answer arrives, so the grid never collapses while a search types.
 */
export function useRecordListPage<Row>({
  endpoint,
  search,
  initial,
}: {
  endpoint: string;
  /** `RecordListState.searchParams` as a string, defaults left out. */
  search: string;
  initial: RecordListPage<Row>;
}): RecordListPageState<Row> {
  const remote = search !== "";

  const query = useQuery({
    queryKey: ["record-list", endpoint, search],
    queryFn: async ({ signal }): Promise<RecordListPage<Row>> => {
      const response = await fetch(`${endpoint}?${search}`, { signal });

      if (!response.ok) {
        throw new Error(`${endpoint} answered ${response.status}`);
      }

      // SAFETY: the list route of this entity answers with a `RecordListPage`.
      return (await response.json()) as RecordListPage<Row>;
    },
    enabled: remote,
    staleTime: 30_000,
    placeholderData: (previous) => previous ?? initial,
  });

  return {
    page: remote ? query.data : initial,
    pending: remote && query.isFetching,
    failed: remote && query.isError && !query.isFetching,
    retry: () => {
      void query.refetch();
    },
  };
}
