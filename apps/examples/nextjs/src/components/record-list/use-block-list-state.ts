"use client";

import { useRecordListState } from "better-supabase/react";
import { parseAsArrayOf, parseAsString, useQueryStates } from "nuqs";
import { useMemo } from "react";

import type { BlockList } from "@/lib/block-list";

import type { RecordListUrl } from "./record-list-types";

/**
 * The URL state of a block list (`?q=&sort=&status=a,b&after=`) in the shape
 * the list kit takes. Facet changes and searches go back to the first page.
 */
export function useBlockListState(list: BlockList): RecordListUrl {
  const parsers = useMemo(
    () => ({
      q: parseAsString,
      sort: parseAsString,
      after: parseAsString,
      page: parseAsString,
      ...Object.fromEntries(
        list.facets.map(({ key }) => [key, parseAsArrayOf(parseAsString)]),
      ),
    }),
    [list],
  );

  return useRecordListState(list, useQueryStates(parsers));
}
