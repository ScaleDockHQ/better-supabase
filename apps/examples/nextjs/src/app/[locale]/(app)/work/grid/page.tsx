import { KanbanIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import {
  WorkGrid,
  WorkGridSkeleton,
} from "@/features/work/components/work-grid";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function WorkGridPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("work");

  return (
    <>
      <PageHeader
        title={t("Work grid")}
        description={t(
          "Search, filter and edit work items in place, or select rows to change many at once.",
        )}
        actions={
          <Link
            href="/work"
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            <KanbanIcon />
            {t("Board")}
          </Link>
        }
      />
      <Suspense fallback={<WorkGridSkeleton />}>
        <WorkGrid searchParams={searchParams} />
      </Suspense>
    </>
  );
}
