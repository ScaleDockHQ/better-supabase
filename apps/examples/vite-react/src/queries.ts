import type { BetterQueries } from "better-supabase/query";

import type { Models } from "./lib/supabase";

import { betterSupabase } from "./lib/supabase";
import { customersTable } from "./lib/supabase/tables/customers";

// The browser registers the tables it reads (ADR 0262); this page needs one.
betterSupabase.registerTable(customersTable);

type AppQueries = BetterQueries<Models, unknown>;

const columns = ["id", "name", "status"] as const;

/** One spec for the query and for `useLiveQuery`; `contains` escapes the term. */
export const customerSpec = (search: string | undefined) =>
  betterSupabase.spec.customers.list({
    select: columns,
    where: search === undefined ? {} : { name: { contains: search } },
    orderBy: { name: "asc" },
    limit: 50,
  });

export const createCustomer = (queries: AppQueries) =>
  queries.customers.create({ select: columns });
