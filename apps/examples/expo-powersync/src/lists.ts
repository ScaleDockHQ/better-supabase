import { defineListQuery } from "better-supabase/list";

import { betterSupabase } from "./lib/supabase";

/**
 * One definition for both readers: PostgREST in web loaders, SQLite on the
 * device.
 */
const customerQuery = {
  search: ["name", "kvk"],
  facets: { status: "status" },
  sorts: {
    name: [{ name: "asc" }, { id: "asc" }],
    newest: [{ created_at: "desc" }, { id: "asc" }],
  },
  defaultSort: "name",
  pageSize: 25,
} as const;

/** Web loaders page by number and show a total. */
export const customerList = defineListQuery(betterSupabase, "customers", {
  ...customerQuery,
  pagination: "offset",
});

/** The device list continues after the last row, so a later page stays cheap. */
export const customerCursor = defineListQuery(betterSupabase, "customers", {
  ...customerQuery,
  pagination: "cursor",
});

export const customerColumns = ["id", "name", "status"] as const;
