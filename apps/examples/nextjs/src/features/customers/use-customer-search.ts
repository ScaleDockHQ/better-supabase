"use client";

import { skipToken, useQuery } from "@tanstack/react-query";
import { useDeferredValue } from "react";

import { logos } from "@/lib/buckets";
import { useQueries, useSupabase } from "@/lib/hooks";
import { bsb } from "@/lib/supabase/client";
import { customersTable } from "@/lib/supabase/tables/customers";

import type { CustomerRow } from "./components/customer-table";

// The browser client registers a table when a module imports it (ADR 0262);
// `queries.customers` exists only after this.
bsb.table(customersTable);

/**
 * Searches every customer by name from the browser, beyond the first page the
 * server sent. RLS scopes the rows to the caller's tenant. A repeated search
 * within `staleTime` paints from the TanStack Query cache without a request;
 * status filtering stays local so it never refetches.
 */
export function useCustomerSearch(needle: string) {
  const queries = useQueries();
  const storage = logos.connect(useSupabase());
  const search = useDeferredValue(needle);

  return useQuery({
    ...queries.customers.list(
      search === ""
        ? skipToken
        : {
            select: ["id", "name", "status", "logoPath"],
            where: { name: { contains: search } },
            include: {
              _count: { notes: true },
              _max: { notes: { createdAt: true } },
            },
            orderBy: [{ name: "asc" }, { id: "asc" }],
            limit: 50,
          },
    ),
    staleTime: 5 * 60_000,
    select: (customers): readonly CustomerRow[] =>
      customers.map((customer) => ({
        id: customer.id,
        name: customer.name,
        status: customer.status,
        logoUrl: customer.logoPath
          ? storage.publicUrl(customer.logoPath).data
          : null,
        notes: customer._count.notes,
        lastNoteAt: customer._max.notes.createdAt,
      })),
  });
}
