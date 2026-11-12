import { CalendarClockIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { io } from "next/cache";
import { forbidden } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import { Badge } from "@/components/reui/badge";
import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import type { MonthEvent } from "../calendar-queries";

import { loadCalendarMonth, settle } from "../calendar-queries";
import { CalendarLoadError } from "./calendar-load-error";

const AHEAD_DAYS = 6;

/**
 * Render inside `<Suspense>`: what is on today and for the days after it,
 * across the organization's calendars, for whoever staffs the front desk.
 */
export async function FrontDesk() {
  await io();
  const today = Temporal.Now.plainDateISO("UTC");
  const until = today.add({ days: AHEAD_DAYS + 1 });

  const [permissions, t, format, loaded] = await Promise.all([
    getPermissions(),
    getExtracted("calendar"),
    getFormatter(),
    settle(() => loadCalendarMonth(today.toString(), until.toString())),
  ]);

  if (!can(permissions, "calendar.read")) {
    forbidden();
  }

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <CalendarLoadError title={t("The front desk didn't load")} />;
  }

  const { calendars, events } = loaded.data;
  const calendarName = new Map(calendars.map((item) => [item.id, item.name]));

  const byDay = new Map<string, MonthEvent[]>();

  for (const event of events) {
    byDay.set(event.day, [...(byDay.get(event.day) ?? []), event]);
  }

  const days = Array.from({ length: AHEAD_DAYS + 1 }, (_, index) =>
    today.add({ days: index }),
  );

  const dayLabel = (date: Temporal.PlainDate) =>
    format.dateTime(new Date(`${date.toString()}T12:00:00Z`), {
      weekday: "long",
      day: "numeric",
      month: "short",
      timeZone: "UTC",
    });

  const todays = byDay.get(today.toString()) ?? [];

  if (calendars.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <CalendarClockIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No calendar yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Create a calendar to see the day's schedule here.")}
          </EmptyDescription>
        </EmptyHeader>
        <Link href="/calendar" className={buttonVariants({ size: "sm" })}>
          {t("Open the calendar")}
        </Link>
      </Empty>
    );
  }

  return (
    <div className="grid items-start gap-6 lg:grid-cols-3">
      <Card className="lg:col-span-2">
        <CardHeader>
          <CardTitle>{dayLabel(today)}</CardTitle>
          <CardDescription>
            {t(
              "{count, plural, =0 {Nothing is scheduled today} one {# event today} other {# events today}}",
              { count: todays.length },
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-2">
          {todays.map((event) => (
            <div
              key={event.key}
              className="flex items-center justify-between gap-3 rounded-md border p-3"
            >
              <div className="flex flex-col">
                <span className="text-sm font-medium">{event.title}</span>
                <span className="text-xs text-muted-foreground">
                  {calendarName.get(event.calendarId)}
                </span>
              </div>
              <Badge variant="secondary" className="tabular-nums">
                {event.time ?? t("All day")}
              </Badge>
            </div>
          ))}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("The next days")}</CardTitle>
          <CardDescription>
            {t("Events of the coming week, by day.")}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          {days.slice(1).map((day) => {
            const list = byDay.get(day.toString()) ?? [];

            return (
              <div key={day.toString()} className="flex flex-col gap-1">
                <span className="text-sm font-medium">{dayLabel(day)}</span>
                {list.length === 0 ? (
                  <span className="text-xs text-muted-foreground">
                    {t("Nothing scheduled")}
                  </span>
                ) : (
                  list.map((event) => (
                    <span key={event.key} className="text-sm">
                      <span className="text-muted-foreground tabular-nums">
                        {event.time ?? t("All day")}
                      </span>{" "}
                      {event.title}
                    </span>
                  ))
                )}
              </div>
            );
          })}
        </CardContent>
      </Card>
    </div>
  );
}

export function FrontDeskSkeleton() {
  return (
    <div className="grid gap-6 lg:grid-cols-3" aria-busy="true">
      <Skeleton className="h-64 lg:col-span-2" />
      <Skeleton className="h-64" />
    </div>
  );
}
