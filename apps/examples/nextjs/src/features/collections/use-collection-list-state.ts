"use client";

import { useRecordListState } from "better-supabase/react";
import { createParser, useQueryStates } from "nuqs";

import { collectionList } from "./collections-list";

const parsers = collectionList.nuqs(createParser);

/** The overview's URL state: `?scope=&state=`. */
export function useCollectionListState() {
  return useRecordListState(collectionList, useQueryStates(parsers));
}
