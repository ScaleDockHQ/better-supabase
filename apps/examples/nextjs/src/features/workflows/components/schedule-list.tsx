import { getExtracted, getFormatter } from "next-intl/server";

import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";

import { getSchedules } from "../workflows-queries";
import { ScheduleControls } from "./schedule-controls";

/** Render inside `<Suspense>`. */
export async function ScheduleList() {
  const [schedules, t, format] = await Promise.all([
    getSchedules(),
    getExtracted("workflows"),
    getFormatter(),
  ]);
  if (schedules.length === 0) {
    return (
      <p className="text-muted-foreground text-sm">
        {t("No schedules. Admins can add one below.")}
      </p>
    );
  }
  return (
    <ul className="divide-y rounded-xl border">
      {schedules.map((schedule) => (
        <li
          key={schedule.id}
          className="flex flex-wrap items-center gap-3 px-4 py-3 text-sm"
        >
          <span className="font-medium">{schedule.name}</span>
          <span className="text-muted-foreground">{schedule.workflow}</span>
          <code className="text-xs">{schedule.cron}</code>
          {schedule.paused ? (
            <Badge variant="outline">{t("Paused")}</Badge>
          ) : null}
          <span className="text-muted-foreground ml-auto text-xs tabular-nums">
            {t("Next: {time}", {
              time: format.dateTime(new Date(schedule.nextRunAt), {
                dateStyle: "medium",
                timeStyle: "short",
              }),
            })}
          </span>
          <ScheduleControls id={schedule.id} paused={schedule.paused} />
        </li>
      ))}
    </ul>
  );
}

export function ScheduleListSkeleton() {
  return <Skeleton className="h-24 w-full" aria-busy="true" />;
}
