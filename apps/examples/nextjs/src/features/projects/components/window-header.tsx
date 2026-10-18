import type { Temporal } from "temporal-polyfill";

import { ChevronLeftIcon, ChevronRightIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import { buttonVariants } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";
import { cn } from "@/lib/utils";

import { WINDOW_DAYS } from "../task-dates";

/** The arrows that move a timeline or gantt window by two weeks. */
export async function WindowNav({
  from,
  today,
  windowHref,
}: {
  from: Temporal.PlainDate;
  today: Temporal.PlainDate;
  windowHref: (from: string) => string;
}) {
  const t = await getExtracted("projects");

  return (
    <div className="flex items-center gap-2">
      <Link
        href={windowHref(from.subtract({ days: 14 }).toString())}
        aria-label={t("Earlier")}
        className={buttonVariants({ variant: "outline", size: "icon-sm" })}
      >
        <ChevronLeftIcon />
      </Link>
      <Link
        href={windowHref(today.toString())}
        className={buttonVariants({ variant: "outline", size: "sm" })}
      >
        {t("Today")}
      </Link>
      <Link
        href={windowHref(from.add({ days: 14 }).toString())}
        aria-label={t("Later")}
        className={buttonVariants({ variant: "outline", size: "icon-sm" })}
      >
        <ChevronRightIcon />
      </Link>
    </div>
  );
}

/** The day columns of the window, Mondays marked by their date. */
export async function WindowDays({
  from,
  today,
}: {
  from: Temporal.PlainDate;
  today: Temporal.PlainDate;
}) {
  const format = await getFormatter();

  const days = Array.from({ length: WINDOW_DAYS }, (_, index) =>
    from.add({ days: index }),
  );

  return (
    <div aria-hidden="true" className="grid grid-cols-28 border-b bg-muted/50">
      {days.map((day) => (
        <span
          key={day.toString()}
          className={cn(
            "py-1.5 text-center text-xs text-muted-foreground tabular-nums",
            day.dayOfWeek === 1 && "border-s",
            day.equals(today) && "font-medium text-foreground",
          )}
        >
          {day.dayOfWeek === 1
            ? format.dateTime(new Date(`${day.toString()}T12:00:00Z`), {
                day: "numeric",
                month: "short",
                timeZone: "UTC",
              })
            : day.day}
        </span>
      ))}
    </div>
  );
}
