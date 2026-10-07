import { getExtracted } from "next-intl/server";

import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getCustomers } from "../customer-queries";
import { CustomerTable } from "./customer-table";

/** Render inside `<Suspense>`; the fallback is `CustomerListSkeleton`. */
export async function CustomerList() {
  const [session, page, t] = await Promise.all([
    getSession(),
    getCustomers(),
    getExtracted("customers"),
  ]);
  const writer = can(session, "customers.write");
  return (
    <div className="space-y-4">
      <CustomerTable
        customers={page.items.map((customer) => ({
          id: customer.id,
          name: customer.name,
          status: customer.status,
          logoUrl: customer.logoUrl,
          notes: customer._count.notes,
          lastNoteAt: customer._max.notes.createdAt,
        }))}
        statusCounts={page.facetCounts.status}
        canWrite={writer}
      />
      {writer ? null : (
        <p className="text-muted-foreground text-sm">
          {t("Only admins can add customers.")}
        </p>
      )}
    </div>
  );
}

export function CustomerListSkeleton() {
  return (
    <div className="space-y-3" aria-busy="true">
      <Skeleton className="h-9 w-full max-w-sm" />
      {Array.from({ length: 5 }, (_, index) => (
        <Skeleton key={index} className="h-12 w-full" />
      ))}
    </div>
  );
}
