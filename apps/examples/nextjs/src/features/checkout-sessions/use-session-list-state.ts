"use client";

import { useRecordListState } from "better-supabase/react";
import { createParser, useQueryStates } from "nuqs";

import { sessionList } from "./checkout-sessions-list";

const parsers = sessionList.nuqs(createParser);

/** The overview's URL state: `?status=&protocol=`. */
export function useSessionListState() {
  return useRecordListState(sessionList, useQueryStates(parsers));
}
