import { defineListQuery } from "better-supabase/list";

import { clientApp } from "./supabase/client-app";
import { customersTable } from "./supabase/tables/customers";

/**
 * Defined over the client app and the `customers` table module, so the client
 * component that reads the URL state loads one table and not the server's
 * `betterSupabase`. `/customers?q=&status=&sort=&page=`. With `facetCounts`,
 * the page and the per-status counts are two requests in one wave.
 */
export const customerList = defineListQuery(clientApp, customersTable, {
  search: ["name"],
  facets: { status: "status" },
  sorts: {
    name: [{ name: "asc" }, { id: "asc" }],
    newest: [{ createdAt: "desc" }, { id: "asc" }],
  },
  defaultSort: "name",
  pageSize: 50,
  facetCounts: true,
});
