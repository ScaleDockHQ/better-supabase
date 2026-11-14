import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  RosterBoard,
  RosterBoardSkeleton,
} from "@/features/shifts/components/roster-board";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ShiftsPage() {
  const t = useExtracted("shifts");

  return (
    <>
      <PageHeader
        title={t("Shifts")}
        description={t(
          "Who works when this week, with the open places on each shift.",
        )}
      />
      <Suspense fallback={<RosterBoardSkeleton />}>
        <RosterBoard />
      </Suspense>
    </>
  );
}
