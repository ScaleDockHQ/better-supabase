"use client";

import { useRecordListState } from "better-supabase/react";
import { createParser, useQueryStates } from "nuqs";

import { giftList } from "./donations-list";

const parsers = giftList.nuqs(createParser);

/** The overview's URL state: `?q=&status=&after=`. */
export function useGiftListState() {
  return useRecordListState(giftList, useQueryStates(parsers));
}
