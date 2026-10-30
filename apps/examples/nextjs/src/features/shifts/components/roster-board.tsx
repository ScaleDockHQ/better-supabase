import type { ShiftStatus } from "better-supabase/blocks/shifts";

import { CalendarDaysIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";
import { connection } from "next/server";
import { Temporal } from "temporal-polyfill";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
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

import { getRoster } from "../shifts-queries";

// #region recipe:roster-board
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

const STATUS_VARIANT = {
  draft: "secondary",
  published: "success-light",
  canceled: "destructive-light",
} as const satisfies Record<ShiftStatus, string>;

/**
 * Render inside `<Suspense>`: this week's shifts in a column per day, each with
 * its times, status and how many of its places are filled. Members see the
 * published shifts; planners with `shifts.write` also the drafts.
 */
export async function RosterBoard() {
  await connection();
  const today = Temporal.Now.plainDateISO("UTC");
  const monday = today.subtract({ days: today.dayOfWeek - 1 });

  const days = Array.from({ length: 7 }, (_, index) =>
    monday.add({ days: index }).toString(),
  );

  const [state, t, format] = await Promise.all([
    getRoster(monday.toString()),
    getExtracted("shifts"),
    getFormatter(),
  ]);

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="roster-board">
        <TriangleAlertIcon />
        <AlertTitle>{t("The roster didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={retry}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  const shifts = state.data;

  if (shifts.length === 0) {
    return (
      <Empty className="border" data-recipe="roster-board">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <CalendarDaysIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No shifts this week")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Save a shift template, generate the week's shifts from it, then publish them.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <a
            className="text-sm underline underline-offset-4"
            href="https://bettersupabase.com/docs/blocks/shifts"
          >
            {t("Read the shifts guide")}
          </a>
        </EmptyContent>
      </Empty>
    );
  }

  const label = (status: ShiftStatus) => {
    switch (status) {
      case "draft": {
        return t("Draft");
      }

      case "published": {
        return t("Published");
      }

      case "canceled": {
        return t("Canceled");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };

  const dayLabel = (date: string) =>
    format.dateTime(new Date(`${date}T12:00:00Z`), {
      weekday: "short",
      day: "numeric",
      timeZone: "UTC",
    });

  const time = (instant: string) =>
    format.dateTime(new Date(instant), { timeStyle: "short", timeZone: "UTC" });

  return (
    <Card data-recipe="roster-board">
      <CardHeader>
        <CardTitle>{t("This week's roster")}</CardTitle>
        <CardDescription>
          {t("The shifts of each day and how many of their places are filled.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="grid grid-cols-1 gap-4 md:grid-cols-7">
        {days.map((day) => (
          <div key={day} className="flex flex-col gap-2">
            <span className="text-sm font-medium">{dayLabel(day)}</span>
            {shifts
              .filter((shift) => shift.day === day)
              .map((shift) => (
                <div
                  key={shift.id}
                  className="flex flex-col gap-2 rounded-md border p-2"
                >
                  <span className="text-sm">
                    {time(shift.startsAt)} – {time(shift.endsAt)}
                  </span>
                  <div className="flex flex-wrap gap-1">
                    <Badge variant={STATUS_VARIANT[shift.status]}>
                      {label(shift.status)}
                    </Badge>
                    <Badge
                      variant={
                        shift.assigned < shift.headcount
                          ? "warning-light"
                          : "secondary"
                      }
                    >
                      {t("{assigned}/{headcount} filled", {
                        assigned: String(shift.assigned),
                        headcount: String(shift.headcount),
                      })}
                    </Badge>
                  </div>
                  {shift.requested > 0 ? (
                    <span className="text-xs text-muted-foreground">
                      {t("{count} requested", {
                        count: String(shift.requested),
                      })}
                    </span>
                  ) : null}
                </div>
              ))}
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

export function RosterBoardSkeleton() {
  return <Skeleton className="h-64" aria-busy="true" />;
}
// #endregion recipe:roster-board
