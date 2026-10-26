import type { TimesheetStatus } from "better-supabase/blocks/time-tracking";

import { ChevronLeftIcon, ChevronRightIcon, ClockIcon } from "lucide-react";
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
import {
  Table,
  TableBody,
  TableCell,
  TableFooter,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { TIME_ZONE, loadTimesheet, settle } from "../people-queries";
import { LogTimeDialog } from "./log-time-dialog";
import { PeopleLoadError } from "./people-load-error";
import { SubmitWeekButton, TimerControls } from "./timesheet-controls";

const DateParam = v.pipe(v.string(), v.isoDate());

/** The Monday of the week `value` falls in, or of this week. */
function mondayOf(value: string | string[] | undefined): Temporal.PlainDate {
  const parsed = v.safeParse(DateParam, value);

  const day = parsed.success
    ? Temporal.PlainDate.from(parsed.output, { overflow: "constrain" })
    : Temporal.Now.plainDateISO(TIME_ZONE);

  return day.subtract({ days: day.dayOfWeek - 1 });
}

/** Seconds as hours and minutes, such as `7:30`. */
function hours(seconds: number): string {
  const minutes = Math.round(seconds / 60);

  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}

function StatusBadge({
  status,
  labels,
}: {
  status: TimesheetStatus;
  labels: Record<TimesheetStatus, string>;
}) {
  switch (status) {
    case "open": {
      return <Badge variant="secondary">{labels.open}</Badge>;
    }

    case "submitted": {
      return <Badge variant="info-light">{labels.submitted}</Badge>;
    }

    case "approved": {
      return <Badge variant="success-light">{labels.approved}</Badge>;
    }

    case "rejected": {
      return <Badge variant="destructive-light">{labels.rejected}</Badge>;
    }

    default: {
      const unhandled: never = status;

      return unhandled;
    }
  }
}

// #region recipe:timesheet
/**
 * Render inside `<Suspense>`: the caller's week as one row per project with
 * hours per day and totals, a running timer, and Submit once the week is done.
 * `?week=YYYY-MM-DD` picks the week.
 */
export async function Timesheet({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [t, format, query, permissions] = await Promise.all([
    getExtracted("people"),
    getFormatter(),
    searchParams,
    getPermissions(),
    connection(),
  ]);

  if (!can(permissions, "time_tracking.track")) {
    forbidden();
  }

  const monday = mondayOf(query["week"]);
  const week = monday.toString();
  const sheet = await settle(() => loadTimesheet(week));

  if (sheet.kind === "no-organization") {
    return null;
  }

  const dayLabel = (date: string) =>
    format.dateTime(new Date(`${date}T12:00:00Z`), {
      weekday: "short",
      day: "numeric",
      timeZone: "UTC",
    });

  const range = format.dateTimeRange(
    new Date(`${week}T12:00:00Z`),
    new Date(`${monday.add({ days: 6 }).toString()}T12:00:00Z`),
    { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" },
  );

  const locked =
    sheet.kind === "ok" &&
    (sheet.data.status === "submitted" || sheet.data.status === "approved");

  const logTime = locked ? null : <LogTimeDialog week={week} />;

  return (
    <Card data-recipe="timesheet">
      <CardHeader>
        <CardTitle>{t("Week of {range}", { range })}</CardTitle>
        <CardDescription>
          {t("Hours per project and day, in {zone}.", { zone: TIME_ZONE })}
        </CardDescription>
        <CardAction className="flex items-center gap-2">
          <Link
            href={`/people/time?week=${monday.subtract({ weeks: 1 }).toString()}`}
            className={buttonVariants({ variant: "outline", size: "icon-sm" })}
            aria-label={t("Previous week")}
          >
            <ChevronLeftIcon />
          </Link>
          <Link
            href={`/people/time?week=${monday.add({ weeks: 1 }).toString()}`}
            className={buttonVariants({ variant: "outline", size: "icon-sm" })}
            aria-label={t("Next week")}
          >
            <ChevronRightIcon />
          </Link>
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {sheet.kind === "error" ? (
          <PeopleLoadError title={t("The timesheet didn't load")} />
        ) : (
          <>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <StatusBadge
                  status={sheet.data.status}
                  labels={{
                    open: t("Open"),
                    submitted: t("Submitted"),
                    approved: t("Approved"),
                    rejected: t("Rejected"),
                  }}
                />
                <span className="text-sm text-muted-foreground tabular-nums">
                  {t("{total} logged, {billable} billable", {
                    total: hours(sheet.data.seconds),
                    billable: hours(sheet.data.billableSeconds),
                  })}
                </span>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                {locked ? null : (
                  <TimerControls
                    running={
                      sheet.data.running
                        ? {
                            project: sheet.data.running.note ?? "",
                            since: format.dateTime(
                              new Date(sheet.data.running.startedAt),
                              { timeStyle: "short" },
                            ),
                          }
                        : null
                    }
                  />
                )}
                {sheet.data.rows.length > 0 ? logTime : null}
                {locked || sheet.data.rows.length === 0 ? null : (
                  <SubmitWeekButton week={week} />
                )}
              </div>
            </div>
            {sheet.data.rows.length === 0 ? (
              <Empty className="border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <ClockIcon />
                  </EmptyMedia>
                  <EmptyTitle>{t("Nothing logged this week")}</EmptyTitle>
                  <EmptyDescription>
                    {locked
                      ? t("This week is locked.")
                      : t(
                          "Log a block of time or start the timer on a project.",
                        )}
                  </EmptyDescription>
                </EmptyHeader>
                {logTime ? <EmptyContent>{logTime}</EmptyContent> : null}
              </Empty>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t("Project")}</TableHead>
                    {sheet.data.days.map((day) => (
                      <TableHead key={day.date} className="text-right">
                        {dayLabel(day.date)}
                      </TableHead>
                    ))}
                    <TableHead className="text-right">{t("Total")}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sheet.data.rows.map((row) => (
                    <TableRow key={row.id}>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-medium">
                            {row.label === "" ? t("No project") : row.label}
                          </span>
                          {row.billable ? (
                            <Badge variant="outline">{t("Billable")}</Badge>
                          ) : null}
                        </div>
                      </TableCell>
                      {row.days.map((seconds, index) => (
                        <TableCell
                          // oxlint-disable-next-line react-doctor/no-array-index-as-key -- the columns are a fixed week keyed by date; the index only covers a missing day
                          key={sheet.data.days[index]?.date ?? index}
                          className="text-right tabular-nums"
                        >
                          {seconds === 0 ? "" : hours(seconds)}
                        </TableCell>
                      ))}
                      <TableCell className="text-right font-medium tabular-nums">
                        {hours(row.seconds)}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
                <TableFooter>
                  <TableRow>
                    <TableCell>{t("Total")}</TableCell>
                    {sheet.data.days.map((day) => (
                      <TableCell
                        key={day.date}
                        className="text-right tabular-nums"
                      >
                        {hours(day.seconds)}
                      </TableCell>
                    ))}
                    <TableCell className="text-right tabular-nums">
                      {hours(sheet.data.seconds)}
                    </TableCell>
                  </TableRow>
                </TableFooter>
              </Table>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:timesheet

export function TimesheetSkeleton() {
  return <Skeleton className="h-80 rounded-xl" aria-busy="true" />;
}
