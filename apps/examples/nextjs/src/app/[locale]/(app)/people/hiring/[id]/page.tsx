import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  ApplicationDetail,
  ApplicationDetailSkeleton,
} from "@/features/people/components/application-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the application desk streams in.
export const instant = true;

export default function ApplicationPage({
  params,
  searchParams,
}: PageProps<"/[locale]/people/hiring/[id]">) {
  const t = useExtracted("people");

  return (
    <>
      <Link
        href="/people/hiring?view=table"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All applications")}
      </Link>
      <Suspense fallback={<ApplicationDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <ApplicationDetail
            id={id}
            tab={activeTab(raw, ["overview", "activity", "related"])}
          />
        ))}
      </Suspense>
    </>
  );
}
