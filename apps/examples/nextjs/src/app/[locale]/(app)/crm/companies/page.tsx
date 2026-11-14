import { UsersIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import { CreateContactDialog } from "@/features/crm/components/create-contact-dialog";
import {
  ContactOverview,
  SalesListSkeleton,
} from "@/features/sales/components/crm-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function CompaniesPage({
  searchParams,
}: PageProps<"/[locale]/crm/companies">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Companies")}
        description={t("The companies you sell to, with the people at each.")}
        actions={
          <>
            <Link
              href="/crm/contacts"
              className={buttonVariants({ variant: "outline" })}
            >
              <UsersIcon />
              {t("All contacts")}
            </Link>
            <Suspense fallback={null}>
              <PermissionGate permission="contacts.write">
                <CreateContactDialog openFromUrl />
              </PermissionGate>
            </Suspense>
          </>
        }
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <ContactOverview query={parseBlockList(raw)} kind="company" />
        ))}
      </Suspense>
    </>
  );
}
