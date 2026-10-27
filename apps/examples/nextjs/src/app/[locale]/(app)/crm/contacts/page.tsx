import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ContactList,
  ContactListSkeleton,
} from "@/features/crm/components/contact-list";
import { CreateContactDialog } from "@/features/crm/components/create-contact-dialog";

export default function ContactsPage() {
  const t = useExtracted("crm");

  return (
    <>
      <PageHeader
        title={t("Contacts")}
        description={t("The companies you sell to and the people you talk to.")}
        actions={<CreateContactDialog />}
      />
      <Suspense fallback={<ContactListSkeleton />}>
        <ContactList />
      </Suspense>
    </>
  );
}
