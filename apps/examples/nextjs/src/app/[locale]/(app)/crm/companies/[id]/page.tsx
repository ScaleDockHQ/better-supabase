import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  ContactDetail,
  ContactDetailSkeleton,
} from "@/features/crm/components/contact-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the company streams in and
// its timeline and sales panel wait for `navigation()`.
export const instant = true;

/** The back link is the static shell; the company streams in. */
export default function CompanyPage({
  params,
  searchParams,
}: PageProps<"/[locale]/crm/companies/[id]">) {
  const t = useExtracted("crm");

  return (
    <>
      <Link
        href="/crm/companies"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All companies")}
      </Link>
      <Suspense fallback={<ContactDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <ContactDetail
            id={id}
            kind="company"
            tab={activeTab(raw, ["overview", "activity", "related"])}
          />
        ))}
      </Suspense>
    </>
  );
}
