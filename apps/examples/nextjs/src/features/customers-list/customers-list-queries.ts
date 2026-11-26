import "server-only";
import { cacheTag } from "next/cache";

import { tags } from "@/lib/supabase/generated.tags";
import { bsbShell as bsb } from "@/lib/supabase/server-shell";

import { getCustomerRows } from "./customers-reads";

/**
 * The first page of the caller's customers plus the count per status.
 * `bsb.cached()` queries with the user's token, so RLS decides the rows; the
 * private cache keeps them in this browser only, for as long as the session
 * view may be reused. The page doesn't read `searchParams`, so it stays in the
 * instant App Shell; filtered pages go through `/api/customers/overview`.
 */
export async function getCustomers() {
  "use cache: private";

  const { db } = await bsb.cached({
    tables: ["customers", "notes"],
    keep: { name: "customers-list" },
  });

  cacheTag(tags.customers());

  return getCustomerRows(db, {});
}

/** One customer with its notes; `null` when RLS hides it or it is gone. */
export async function getCustomer(id: string) {
  "use cache: private";

  const { db } = await bsb.cached({
    tables: ["customers", "notes"],
    id,
    keep: { name: "customer" },
  });

  cacheTag(tags.customers());

  const customer = await db.customers
    .get(
      { id },
      {
        select: [
          "id",
          "name",
          "status",
          "logoPath",
          "ownerTeamId",
          "createdAt",
        ],
        include: {
          notes: {
            select: ["id", "body", "kind", "createdAt"],
            orderBy: { createdAt: "desc" },
            limit: 5,
          },
        },
        optional: true,
      },
    )
    .orThrow();

  if (!customer) {
    return null;
  }

  return {
    ...customer,
    logoUrl: customer.logoPath
      ? db.$buckets.logos.publicUrl(customer.logoPath, { transform: "square" })
          .data
      : null,
  };
}
