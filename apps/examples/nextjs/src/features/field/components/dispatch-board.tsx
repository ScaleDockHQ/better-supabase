import {
  CalendarRangeIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  InboxIcon,
} from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden } from "next/navigation";
import { connection } from "next/server";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

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
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { settle } from "@/features/people/people-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { loadDispatchWeek } from "../field-queries";
import { FieldLoadError } from "./field-load-error";
import { NewWorkOrderDialog } from "./new-work-order-dialog";
import {
  WorkOrderPriorityBadge,
  WorkOrderStatusBadge,
} from "./work-order-badges";

const DateParam = v.pipe(v.string(), v.isoDate());

/** The Monday of the week `value` falls in, or of this week. */
function mondayOf(value: string | string[] | undefined): Temporal.PlainDate {
  const parsed = v.safeParse(DateParam, value);

  const day = parsed.success
    ? Temporal.PlainDate.from(parsed.output, { overflow: "constrain" })
    : Temporal.Now.plainDateISO("UTC");

  return day.subtract({ days: day.dayOfWeek - 1 });
}

// #region recipe:dispatch-board
/**
 * Render inside `<Suspense>`: a week of technicians by day with their scheduled
 * work orders, and the unscheduled backlog below. `?week=YYYY-MM-DD` picks the
 * week.
 */
export async function DispatchBoard({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [t, format, query, permissions] = await Promise.all([
    getExtracted("field"),
    getFormatter(),
    searchParams,
    getPermissions(),
    connection(),
  ]);

  if (!can(permissions, "dispatch.read")) {
    forbidden();
  }

  const manage = can(permissions, "dispatch.manage");
  const monday = mondayOf(query["week"]);
  const board = await settle(() => loadDispatchWeek(monday.toString()));

  if (board.kind === "no-organization") {
    return null;
  }

  const dayLabel = (date: string) =>
    format.dateTime(new Date(`${date}T12:00:00Z`), {
      weekday: "short",
      day: "numeric",
      timeZone: "UTC",
    });

  const range = format.dateTimeRange(
    new Date(`${monday.toString()}T12:00:00Z`),
    new Date(`${monday.add({ days: 6 }).toString()}T12:00:00Z`),
    { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" },
  );

  const newWorkOrder = manage ? <NewWorkOrderDialog /> : null;

  return (
    <div data-recipe="dispatch-board" className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("Week of {range}", { range })}</CardTitle>
          <CardDescription>
            {board.kind === "ok"
              ? t("Scheduled work per technician, in {zone}.", {
                  zone: board.data.timeZone,
                })
              : t("Scheduled work per technician.")}
          </CardDescription>
          <CardAction className="flex items-center gap-2">
            <Link
              href={`/field/dispatch?week=${monday.subtract({ weeks: 1 }).toString()}`}
              className={buttonVariants({
                variant: "outline",
                size: "icon-sm",
              })}
              aria-label={t("Previous week")}
            >
              <ChevronLeftIcon />
            </Link>
            <Link
              href={`/field/dispatch?week=${monday.add({ weeks: 1 }).toString()}`}
              className={buttonVariants({
                variant: "outline",
                size: "icon-sm",
              })}
              aria-label={t("Next week")}
            >
              <ChevronRightIcon />
            </Link>
          </CardAction>
        </CardHeader>
        <CardContent>
          {board.kind === "error" ? (
            <FieldLoadError title={t("The schedule board didn't load")} />
          ) : board.data.rows.length === 0 ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <CalendarRangeIcon />
                </EmptyMedia>
                <EmptyTitle>{t("Nothing scheduled this week")}</EmptyTitle>
                <EmptyDescription>
                  {t("Work orders show here once they have a technician.")}
                </EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                <Link
                  href={`/field/dispatch?week=${monday.add({ weeks: 1 }).toString()}`}
                  className={buttonVariants({ variant: "outline" })}
                >
                  {t("Show next week")}
                </Link>
              </EmptyContent>
            </Empty>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Technician")}</TableHead>
                  {board.data.days.map((day) => (
                    <TableHead key={day}>{dayLabel(day)}</TableHead>
                  ))}
                </TableRow>
              </TableHeader>
              <TableBody>
                {board.data.rows.map((row) => (
                  <TableRow key={row.technicianId}>
                    <TableCell className="align-top text-sm font-medium">
                      {row.name}
                    </TableCell>
                    {row.days.map(({ date, orders }) => (
                      <TableCell key={date} className="align-top">
                        <div className="flex flex-col gap-2">
                          {orders.map((order) => (
                            <div key={order.id} className="flex flex-col gap-1">
                              <span className="text-sm font-medium">
                                {order.title}
                              </span>
                              <span className="text-xs text-muted-foreground tabular-nums">
                                {order.startsAt
                                  ? format.dateTime(new Date(order.startsAt), {
                                      timeStyle: "short",
                                      timeZone: board.data.timeZone,
                                    })
                                  : null}
                              </span>
                              <WorkOrderStatusBadge status={order.status} />
                            </div>
                          ))}
                        </div>
                      </TableCell>
                    ))}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Backlog")}</CardTitle>
          <CardDescription>
            {t("Work orders without a slot, most urgent first.")}
          </CardDescription>
          {newWorkOrder ? <CardAction>{newWorkOrder}</CardAction> : null}
        </CardHeader>
        <CardContent>
          {board.kind === "error" ? (
            <FieldLoadError title={t("The backlog didn't load")} />
          ) : board.data.backlog.length === 0 ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <InboxIcon />
                </EmptyMedia>
                <EmptyTitle>{t("The backlog is empty")}</EmptyTitle>
                <EmptyDescription>
                  {t("Every open work order has a slot.")}
                </EmptyDescription>
              </EmptyHeader>
              {newWorkOrder ? (
                <EmptyContent>{newWorkOrder}</EmptyContent>
              ) : null}
            </Empty>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Job")}</TableHead>
                  <TableHead>{t("Address")}</TableHead>
                  <TableHead>{t("Priority")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {board.data.backlog.map((order) => (
                  <TableRow key={order.id}>
                    <TableCell className="text-sm font-medium">
                      {order.title}
                    </TableCell>
                    <TableCell className="text-sm text-muted-foreground">
                      {order.address ?? ""}
                    </TableCell>
                    <TableCell>
                      <WorkOrderPriorityBadge priority={order.priority} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
// #endregion recipe:dispatch-board

export function DispatchBoardSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-80 rounded-xl" />
      <Skeleton className="h-48 rounded-xl" />
    </div>
  );
}
