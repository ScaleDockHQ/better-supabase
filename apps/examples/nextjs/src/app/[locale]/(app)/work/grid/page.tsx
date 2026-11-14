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

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
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
        {searchParams.then((query) => (
          <WorkGrid query={query} />
        ))}
      </Suspense>
    </>
  );
}
