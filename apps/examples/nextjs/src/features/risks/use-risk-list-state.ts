"use client";

import { useRecordListState } from "better-supabase/react";
import { parseAsArrayOf, parseAsString, useQueryStates } from "nuqs";

import { riskList } from "./risk-list";

const parsers = {
  q: parseAsString,
  status: parseAsArrayOf(parseAsString),
  category: parseAsArrayOf(parseAsString),
  band: parseAsArrayOf(parseAsString),
  after: parseAsString,
};

/** The risk list's URL state, with the query params `/api/risks/list` parses. */
export function useRiskListState() {
  return useRecordListState(riskList, useQueryStates(parsers));
}
