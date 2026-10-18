import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  ContactDetail,
  ContactDetailSkeleton,
} from "@/features/crm/components/contact-detail";
import { Link } from "@/i18n/navigation";

export const instant = true;

/** The back link is the static shell; the contact streams in. */
export default function ContactPage({
  params,
}: PageProps<"/[locale]/crm/contacts/[id]">) {
  const t = useExtracted("crm");

  return (
    <>
      <Link
        href="/crm/contacts"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All contacts")}
      </Link>
      <Suspense fallback={<ContactDetailSkeleton />}>
        <ContactDetail params={params} />
      </Suspense>
    </>
  );
}
