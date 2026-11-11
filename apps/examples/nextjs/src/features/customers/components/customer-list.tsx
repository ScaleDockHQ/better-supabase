import { getExtracted } from "next-intl/server";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getCustomers } from "@/features/customers-list/customers-list-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { CustomerRecordList } from "./customer-record-list";

/** Render inside `<Suspense>`; the fallback is `CustomerListSkeleton`. */
export async function CustomerList() {
  const [page, t, permissions] = await Promise.all([
    getCustomers(),
    getExtracted("customers"),
    getPermissions(),
  ]);

  const writer = can(permissions, "customers.write");

  return (
    <div className="flex flex-col gap-4">
      <CustomerRecordList
        initial={{
          items: page.items.map((customer) => ({
            id: customer.id,
            name: customer.name,
            status: customer.status,
            logoUrl: customer.logoUrl,
            notes: customer._count.notes,
            lastNoteAt: customer._max.notes.createdAt,
          })),
          nextCursor: page.nextCursor,
          facetCounts: page.facetCounts,
          facetCountsCapped: page.facetCountsCapped === true,
        }}
        canWrite={writer}
      />
      {writer ? null : (
        <p className="text-sm text-muted-foreground">
          {t("Only admins can add customers.")}
        </p>
      )}
    </div>
  );
}

export function CustomerListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
