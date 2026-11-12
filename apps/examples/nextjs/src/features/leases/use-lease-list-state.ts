"use client";

import { useRecordListState } from "better-supabase/react";
import { createParser, useQueryStates } from "nuqs";

import { leaseList } from "./leases-list";

const parsers = leaseList.nuqs(createParser);

/** The overview's URL state: `?status=`. */
export function useLeaseListState() {
  return useRecordListState(leaseList, useQueryStates(parsers));
}
