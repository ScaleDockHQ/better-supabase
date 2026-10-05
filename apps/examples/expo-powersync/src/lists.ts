import { defineListQuery } from "better-supabase/list";

import { betterSupabase } from "./lib/supabase";

/** One definition for both readers: PostgREST in web loaders, SQLite on the device. */
export const customerList = defineListQuery(betterSupabase, "customers", {
  search: ["name", "kvk"],
  facets: { status: "status" },
  sorts: {
    name: [{ name: "asc" }, { id: "asc" }],
    newest: [{ created_at: "desc" }, { id: "asc" }],
  },
  defaultSort: "name",
  pageSize: 25,
});

export const customerColumns = ["id", "name", "status"] as const;
