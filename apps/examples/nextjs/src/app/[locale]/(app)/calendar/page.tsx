import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CalendarView,
  CalendarViewSkeleton,
} from "@/features/calendar/components/calendar-view";
import {
  RemindersList,
  RemindersListSkeleton,
} from "@/features/calendar/components/reminders-list";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function CalendarPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("calendar");

  return (
    <>
      <PageHeader
        title={t("Calendar")}
        description={t("Your organization's events by month.")}
      />
      <Suspense fallback={<CalendarViewSkeleton />}>
        {searchParams.then((query) => (
          <CalendarView query={query} />
        ))}
      </Suspense>
      <Suspense fallback={<RemindersListSkeleton />}>
        {searchParams.then((query) => (
          <RemindersList query={query} />
        ))}
      </Suspense>
    </>
  );
}
