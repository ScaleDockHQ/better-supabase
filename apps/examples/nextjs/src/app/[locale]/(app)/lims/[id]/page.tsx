import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  SampleDetail,
  SampleDetailSkeleton,
} from "@/features/lims/components/sample-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the sample streams in behind it.
export const instant = true;

export default function SamplePage({
  params,
  searchParams,
}: PageProps<"/[locale]/lims/[id]">) {
  const t = useExtracted("lims");

  return (
    <>
      <Link
        href="/lims"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All samples")}
      </Link>
      <Suspense fallback={<SampleDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <SampleDetail
            id={id}
            tab={activeTab(raw, ["results", "nonconformities", "details"])}
          />
        ))}
      </Suspense>
    </>
  );
}
