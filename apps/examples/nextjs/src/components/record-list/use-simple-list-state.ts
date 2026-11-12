"use client";

import type { RecordListState } from "better-supabase/react";

import { useRecordListState } from "better-supabase/react";
import { parseAsArrayOf, parseAsString, useQueryStates } from "nuqs";

import type { SimpleList, SimpleListQuery } from "@/lib/simple-list";

/**
 * The URL state of a `defineSimpleList` list through nuqs. Every key is plain
 * text in the URL, and a facet is a comma-separated list under its own key.
 */
export function useSimpleListState(
  list: SimpleList,
): RecordListState<SimpleListQuery> {
  const parsers = {
    q: parseAsString,
    sort: parseAsString,
    after: parseAsString,
    page: parseAsString,
    ...Object.fromEntries(
      list.config.facets.map((key) => [key, parseAsArrayOf(parseAsString)]),
    ),
  };

  return useRecordListState(list, useQueryStates(parsers));
}
