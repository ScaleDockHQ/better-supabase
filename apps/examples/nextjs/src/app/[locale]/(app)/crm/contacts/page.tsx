import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { CreateContactDialog } from "@/features/crm/components/create-contact-dialog";
import {
  ContactOverview,
  SalesListSkeleton,
} from "@/features/sales/components/crm-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function ContactsPage({
  searchParams,
}: PageProps<"/[locale]/crm/contacts">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Contacts")}
        description={t("The companies you sell to and the people you talk to.")}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="contacts.write">
              <CreateContactDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <ContactOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
