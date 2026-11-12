"use client";

import { useRecordListState } from "better-supabase/react";
import { createParser, useQueryStates } from "nuqs";

import { reviewList } from "./reviews-list";

const parsers = reviewList.nuqs(createParser);

/** The overview's URL state: `?status=`. */
export function useReviewListState() {
  return useRecordListState(reviewList, useQueryStates(parsers));
}
