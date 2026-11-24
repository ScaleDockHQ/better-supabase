import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  ContentDetail,
  ContentDetailSkeleton,
} from "@/features/content/components/content-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the entry streams in.
export const instant = true;

export default function ContentEntryPage({
  params,
  searchParams,
}: PageProps<"/[locale]/content/[id]">) {
  const t = useExtracted("content");

  return (
    <>
      <Link
        href="/content"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All content")}
      </Link>
      <Suspense fallback={<ContentDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <ContentDetail
            id={id}
            tab={activeTab(raw, ["overview", "activity", "related"])}
          />
        ))}
      </Suspense>
    </>
  );
}
