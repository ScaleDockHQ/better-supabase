"use client";

import { useRecordListState } from "better-supabase/react";
import { createParser, useQueryStates } from "nuqs";

import { assetList } from "./assets-list";

const parsers = assetList.nuqs(createParser);

/** The register's URL state: `?q=&status=&after=`. */
export function useAssetListState() {
  return useRecordListState(assetList, useQueryStates(parsers));
}
