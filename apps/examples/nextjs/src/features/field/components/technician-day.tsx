import type { WorkOrderStatus } from "better-supabase/blocks/dispatch";

import { ChevronLeftIcon, ChevronRightIcon, RouteIcon } from "lucide-react";
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
import { settle } from "@/features/people/people-queries";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import { loadTechnicianDay } from "../field-queries";
import { AdvanceWorkOrderButton } from "./advance-work-order-button";
import { FieldLoadError } from "./field-load-error";
import { WorkOrderStatusBadge } from "./work-order-badges";

const DateParam = v.pipe(v.string(), v.isoDate());

function dayOf(value: string | string[] | undefined): Temporal.PlainDate {
  const parsed = v.safeParse(DateParam, value);

  return parsed.success
    ? Temporal.PlainDate.from(parsed.output, { overflow: "constrain" })
    : Temporal.Now.plainDateISO("UTC");
}

/** The status a technician moves a stop to next, if any. */
function nextStep(
  status: WorkOrderStatus,
): "en_route" | "on_site" | "done" | null {
  switch (status) {
    case "scheduled": {
      return "en_route";
    }

    case "en_route": {
      return "on_site";
    }

    case "on_site": {
      return "done";
    }

    case "unscheduled":
    case "done":
    case "cancelled": {
      return null;
    }

    default: {
      const unhandled: never = status;

      return unhandled;
    }
  }
}

// #region recipe:technician-day
/**
 * Render inside `<Suspense>`: the caller's stops for a day in route order, each
 * with the button that moves it on. `?day=YYYY-MM-DD` picks the day.
 */
export async function TechnicianDay({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [session, t, format, query] = await Promise.all([
    getSession(),
    getExtracted("field"),
    getFormatter(),
    searchParams,
    connection(),
  ]);

  if (!can(session, "dispatch.work")) {
    forbidden();
  }

  const day = dayOf(query["day"]);
  const plan = await settle(() => loadTechnicianDay(day.toString()));

  if (plan.kind === "no-organization") {
    return null;
  }

  const title = format.dateTime(new Date(`${day.toString()}T12:00:00Z`), {
    dateStyle: "full",
    timeZone: "UTC",
  });

  const time = (instant: string | null) =>
    instant ? format.dateTime(new Date(instant), { timeStyle: "short" }) : null;

  return (
    <Card data-recipe="technician-day">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>
          {plan.kind === "ok" && plan.data.planned
            ? t("Your stops in the order of the planned route.")
            : t("Your stops by start time.")}
        </CardDescription>
        <CardAction className="flex items-center gap-2">
          <Link
            href={`/field/day?day=${day.subtract({ days: 1 }).toString()}`}
            className={buttonVariants({ variant: "outline", size: "icon-sm" })}
            aria-label={t("Previous day")}
          >
            <ChevronLeftIcon />
          </Link>
          <Link
            href={`/field/day?day=${day.add({ days: 1 }).toString()}`}
            className={buttonVariants({ variant: "outline", size: "icon-sm" })}
            aria-label={t("Next day")}
          >
            <ChevronRightIcon />
          </Link>
        </CardAction>
      </CardHeader>
      <CardContent>
        {plan.kind === "error" ? (
          <FieldLoadError title={t("Your day didn't load")} />
        ) : plan.data.stops.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <RouteIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No stops on this day")}</EmptyTitle>
              <EmptyDescription>
                {t("Work orders scheduled for you show here.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link
                href={`/field/day?day=${day.add({ days: 1 }).toString()}`}
                className={buttonVariants({ variant: "outline" })}
              >
                {t("Show the next day")}
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <ol className="flex flex-col divide-y">
            {plan.data.stops.map(({ position, workOrder }) => {
              const next = nextStep(workOrder.status);
              const from = time(workOrder.startsAt);
              const to = time(workOrder.endsAt);

              return (
                <li
                  key={workOrder.id}
                  className="flex flex-wrap items-center gap-3 py-3"
                >
                  <Badge variant="outline" className="tabular-nums">
                    {position}
                  </Badge>
                  <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="text-sm font-medium">
                      {workOrder.title}
                    </span>
                    <span className="text-xs text-muted-foreground tabular-nums">
                      {[
                        from && to ? t("{from} to {to}", { from, to }) : from,
                        workOrder.address,
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                    </span>
                  </div>
                  <WorkOrderStatusBadge status={workOrder.status} />
                  {next ? (
                    <AdvanceWorkOrderButton id={workOrder.id} to={next} />
                  ) : null}
                </li>
              );
            })}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:technician-day

export function TechnicianDaySkeleton() {
  return <Skeleton className="h-80 rounded-xl" aria-busy="true" />;
}
