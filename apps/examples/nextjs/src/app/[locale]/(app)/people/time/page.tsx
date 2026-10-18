import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  Timesheet,
  TimesheetSkeleton,
} from "@/features/people/components/timesheet";

export const instant = true;

export default function TimePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("people");

  return (
    <>
      <PageHeader
        title={t("Time")}
        description={t(
          "Log your hours for the week and send them for approval.",
        )}
      />
      <Suspense fallback={<TimesheetSkeleton />}>
        <Timesheet searchParams={searchParams} />
      </Suspense>
    </>
  );
}
