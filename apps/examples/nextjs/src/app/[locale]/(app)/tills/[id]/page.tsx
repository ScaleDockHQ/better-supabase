import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  SessionDetail,
  SessionDetailSkeleton,
} from "@/features/tills/components/session-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the session streams in behind it.
export const instant = true;

export default function TillSessionPage({
  params,
  searchParams,
}: PageProps<"/[locale]/tills/[id]">) {
  const t = useExtracted("tills");

  return (
    <>
      <Link
        href="/tills"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All sessions")}
      </Link>
      <Suspense fallback={<SessionDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <SessionDetail
            id={id}
            tab={activeTab(raw, ["movements", "count", "deposits"])}
          />
        ))}
      </Suspense>
    </>
  );
}
