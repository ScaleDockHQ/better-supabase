"use client";

import { useRecordListState } from "better-supabase/react";
import { useQueryStates } from "nuqs";

import type { RecordListUrl } from "@/components/record-list/record-list-types";
import type { AdminList } from "@/lib/admin-list";

/**
 * The URL state of an admin list (`?q=&status=&sort=&after=`), in the shape the
 * list kit takes. A facet or sort change goes back to the first page.
 */
export function useAdminListState(list: AdminList): RecordListUrl {
  return useRecordListState(list, useQueryStates(list.parsers()));
}
