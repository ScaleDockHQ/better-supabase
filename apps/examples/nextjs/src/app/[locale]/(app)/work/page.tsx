import { TableIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import { ConnectivityFallback } from "@/features/offline/components/connectivity-fallback";
import {
  WorkBoard,
  WorkBoardSkeleton,
} from "@/features/work/components/work-board";
import { Link } from "@/i18n/navigation";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function WorkPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("work");

  return (
    <>
      <PageHeader
        title={t("Work")}
        description={t(
          "Work items by state. Moves follow the workflow's allowed transitions.",
        )}
        actions={
          <Link
            href="/work/grid"
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            <TableIcon />
            {t("Grid")}
          </Link>
        }
      />
      <Suspense
        fallback={
          <ConnectivityFallback>
            <WorkBoardSkeleton />
          </ConnectivityFallback>
        }
      >
        {searchParams.then((query) => (
          <WorkBoard query={query} />
        ))}
      </Suspense>
    </>
  );
}
