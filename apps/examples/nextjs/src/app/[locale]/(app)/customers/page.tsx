import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CustomerList,
  CustomerListSkeleton,
} from "@/features/customers/components/customer-list";
import { CustomerWriterActions } from "@/features/customers/components/customer-writer-actions";
import {
  SimilarNotes,
  SimilarNotesSkeleton,
} from "@/features/notes/components/similar-notes";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function CustomersPage() {
  const t = useExtracted("customers");
  return (
    <>
      <PageHeader
        title={t("Customers")}
        description={t("Everyone your organization works with.")}
        actions={
          <Suspense fallback={null}>
            <CustomerWriterActions />
          </Suspense>
        }
      />
      <Suspense fallback={<CustomerListSkeleton />}>
        <PermissionGate permission="customers.read">
          <CustomerList />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<SimilarNotesSkeleton />}>
        <PermissionGate permission="customers.read">
          <SimilarNotes />
        </PermissionGate>
      </Suspense>
    </>
  );
}
