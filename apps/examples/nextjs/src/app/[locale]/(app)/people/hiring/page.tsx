import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  HiringBoard,
  HiringBoardSkeleton,
} from "@/features/people/components/hiring-board";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function HiringPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("people");

  return (
    <>
      <PageHeader
        title={t("Hiring")}
        description={t("Openings and their candidates by interview stage.")}
      />
      <Suspense fallback={<HiringBoardSkeleton />}>
        {searchParams.then((query) => (
          <HiringBoard query={query} />
        ))}
      </Suspense>
    </>
  );
}
