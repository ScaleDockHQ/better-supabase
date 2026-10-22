import type { DateTimeFormatOptions } from "next-intl";

import { CalendarIcon, ChevronLeftIcon, ChevronRightIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden } from "next/navigation";
import { connection } from "next/server";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { Badge } from "@/components/reui/badge";
import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";
import { cn } from "@/lib/utils";

import type { MonthEvent } from "../calendar-queries";

import { loadCalendarMonth, settle } from "../calendar-queries";
import { CalendarLoadError } from "./calendar-load-error";
import { CreateCalendarButton } from "./create-calendar-button";
import { CreateEventDialog } from "./create-event-dialog";
import { WorkingHoursDialog } from "./working-hours-dialog";

const SHOWN_PER_DAY = 3;

const MonthParam = v.pipe(v.string(), v.regex(/^\d{4}-(0[1-9]|1[0-2])$/));

/** The first day of `?month=YYYY-MM`, else of the current month in `tz`. */
function firstOfMonth(value: string | string[] | undefined, tz: string) {
  const parsed = v.safeParse(MonthParam, value);

  return parsed.success
    ? Temporal.PlainDate.from(`${parsed.output}-01`)
    : Temporal.Now.plainDateISO(tz).with({ day: 1 });
}

/** The Monday-first weeks that cover the month, as 7-day rows. */
function weeksOf(first: Temporal.PlainDate) {
  const start = first.subtract({ days: first.dayOfWeek - 1 });
  const last = first.add({ months: 1 }).subtract({ days: 1 });
  const end = last.add({ days: 7 - last.dayOfWeek });
  const days = Math.round(start.until(end).total({ unit: "days" })) + 1;

  return Array.from({ length: days / 7 }, (_, week) =>
    Array.from({ length: 7 }, (_, day) => start.add({ days: week * 7 + day })),
  );
}

// #region recipe:calendar-view
export async function CalendarView({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const session = await getSession();

  if (!can(session, "calendar.read")) {
    forbidden();
  }

  const [t, format, query] = await Promise.all([
    getExtracted("calendar"),
    getFormatter(),
    searchParams,
    connection(),
  ]);

  const canWrite = can(session, "calendar.write");
  const canManage = can(session, "calendar.manage");
  const first = firstOfMonth(query["month"], "UTC");
  const weeks = weeksOf(first);
  const from = weeks[0]?.[0] ?? first;
  const until = (weeks.at(-1)?.[6] ?? first).add({ days: 1 });

  const month = await settle(() =>
    loadCalendarMonth(from.toString(), until.toString()),
  );

  const monthKey = (date: Temporal.PlainDate) =>
    date.toPlainYearMonth().toString();

  const label = (date: Temporal.PlainDate, options: DateTimeFormatOptions) =>
    format.dateTime(new Date(`${date.toString()}T12:00:00Z`), {
      ...options,
      timeZone: "UTC",
    });

  const byDay = new Map<string, MonthEvent[]>();

  if (month.kind === "ok") {
    for (const event of month.data.events) {
      byDay.set(event.day, [...(byDay.get(event.day) ?? []), event]);
    }
  }

  const today =
    month.kind === "ok"
      ? Temporal.Now.plainDateISO(month.data.tz).toString()
      : null;

  const calendars = month.kind === "ok" ? month.data.calendars : [];

  return (
    <Card data-recipe="calendar-view">
      <CardHeader>
        <CardTitle>
          {label(first, { month: "long", year: "numeric" })}
        </CardTitle>
        <CardDescription>
          {month.kind === "ok" && calendars.length > 0
            ? t("{count, plural, one {# event} other {# events}} in view", {
                count: month.data.events.length,
              })
            : t("Events of your organization by day.")}
        </CardDescription>
        <CardAction className="flex items-center gap-2">
          <Link
            href={`/calendar?month=${monthKey(first.subtract({ months: 1 }))}`}
            aria-label={t("Previous month")}
            className={buttonVariants({ variant: "outline", size: "icon-sm" })}
          >
            <ChevronLeftIcon />
          </Link>
          <Link
            href="/calendar"
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {t("Today")}
          </Link>
          <Link
            href={`/calendar?month=${monthKey(first.add({ months: 1 }))}`}
            aria-label={t("Next month")}
            className={buttonVariants({ variant: "outline", size: "icon-sm" })}
          >
            <ChevronRightIcon />
          </Link>
          {calendars.length > 0 ? <WorkingHoursDialog /> : null}
          {canWrite && calendars.length > 0 ? (
            <CreateEventDialog
              calendars={calendars}
              defaultDate={today ?? first.toString()}
            />
          ) : null}
        </CardAction>
      </CardHeader>
      <CardContent>
        {month.kind === "error" ? (
          <CalendarLoadError title={t("The calendar didn't load.")} />
        ) : month.kind === "no-organization" || calendars.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <CalendarIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No calendar yet")}</EmptyTitle>
              <EmptyDescription>
                {month.kind === "no-organization"
                  ? t("Pick an organization to see its calendar.")
                  : t("Create the team calendar, then add events to it.")}
              </EmptyDescription>
            </EmptyHeader>
            {month.kind === "ok" && canManage ? (
              <EmptyContent>
                <CreateCalendarButton />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <div className="overflow-x-auto">
            <div className="min-w-[42rem] overflow-hidden rounded-lg border">
              <div
                aria-hidden="true"
                className="grid grid-cols-7 border-b bg-muted/50"
              >
                {weeks[0]?.map((day) => (
                  <span
                    key={day.toString()}
                    className="px-2 py-1.5 text-xs font-medium text-muted-foreground"
                  >
                    {label(day, { weekday: "short" })}
                  </span>
                ))}
              </div>
              <ol
                aria-label={label(first, { month: "long", year: "numeric" })}
                className="grid grid-cols-7"
              >
                {weeks.flat().map((day) => {
                  const key = day.toString();
                  const events = byDay.get(key) ?? [];
                  const outside = day.month !== first.month;

                  return (
                    <li
                      key={key}
                      className={cn(
                        "flex min-h-24 flex-col gap-1 border-e border-b p-1.5 [&:nth-child(7n)]:border-e-0",
                        outside && "bg-muted/30",
                      )}
                    >
                      <span className="sr-only">
                        {label(day, { dateStyle: "full" })}
                      </span>
                      <span
                        aria-hidden="true"
                        className={cn(
                          "text-xs",
                          outside ? "text-muted-foreground" : "font-medium",
                        )}
                      >
                        {key === today ? (
                          <Badge variant="default">{day.day}</Badge>
                        ) : (
                          day.day
                        )}
                      </span>
                      {events.slice(0, SHOWN_PER_DAY).map((event) => (
                        <span
                          key={event.key}
                          title={event.title}
                          className="truncate rounded-sm bg-primary/10 px-1.5 py-0.5 text-xs text-foreground"
                        >
                          {event.time ? (
                            <span className="text-muted-foreground tabular-nums">
                              {event.time}{" "}
                            </span>
                          ) : null}
                          {event.title}
                        </span>
                      ))}
                      {events.length > SHOWN_PER_DAY ? (
                        <span className="text-xs text-muted-foreground">
                          {t("{count} more", {
                            count: String(events.length - SHOWN_PER_DAY),
                          })}
                        </span>
                      ) : null}
                    </li>
                  );
                })}
              </ol>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:calendar-view

export function CalendarViewSkeleton() {
  return (
    <Card>
      <CardHeader>
        <Skeleton className="h-5 w-40" />
        <Skeleton className="h-4 w-56" />
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-7 gap-1">
          {Array.from({ length: 35 }, (_, index) => (
            <Skeleton key={index} className="h-24" />
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
