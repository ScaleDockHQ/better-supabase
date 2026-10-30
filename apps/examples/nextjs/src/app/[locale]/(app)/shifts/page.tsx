import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  RosterBoard,
  RosterBoardSkeleton,
} from "@/features/shifts/components/roster-board";

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
