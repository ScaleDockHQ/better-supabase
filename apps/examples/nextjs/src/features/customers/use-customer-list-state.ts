"use client";

import { useRecordListState } from "better-supabase/react";
import { createParser, useQueryStates } from "nuqs";

import { customerList } from "@/lib/lists";

const parsers = customerList.nuqs(createParser);

/**
 * The customer list's URL state (`?status=&sort=&page=`), with the query params
 * `/api/customers/records` parses. A status change goes back to page 1.
 */
export function useCustomerListState() {
  return useRecordListState(customerList, useQueryStates(parsers));
}
