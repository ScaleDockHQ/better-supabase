"use client";

import { useRecordListState } from "better-supabase/react";
import { createParser, useQueryStates } from "nuqs";

import { passList } from "./passes-list";

const parsers = passList.nuqs(createParser);

/** The overview's URL state: `?status=&after=`. */
export function usePassListState() {
  return useRecordListState(passList, useQueryStates(parsers));
}
