"use client";

import { useRecordListState } from "better-supabase/react";
import { createParser, useQueryStates } from "nuqs";

import { claimList } from "./warranty-list";

const parsers = claimList.nuqs(createParser);

/** The overview's URL state: `?status=`. */
export function useClaimListState() {
  return useRecordListState(claimList, useQueryStates(parsers));
}
