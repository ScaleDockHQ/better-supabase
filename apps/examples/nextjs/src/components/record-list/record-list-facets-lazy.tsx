"use client";

import dynamic from "next/dynamic";

import { Skeleton } from "@/components/ui/skeleton";

/**
 * The facet filters load after the first paint and only in the browser: the
 * ReUI `Filters` code (chips, editors, the field picker) is about 180 KB of
 * gzipped server bundle and is not needed to show the rows. The skeleton holds
 * the space of the Add filter button.
 */
export const RecordListFacetsLazy = dynamic(
  () => import("./record-list-facets").then((mod) => mod.RecordListFacets),
  { ssr: false, loading: () => <Skeleton className="h-8 w-28" /> },
);
