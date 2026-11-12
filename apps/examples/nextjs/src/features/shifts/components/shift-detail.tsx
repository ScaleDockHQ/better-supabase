import type { ShiftStatus } from "better-supabase/blocks/shifts";

import { getExtracted, getFormatter } from "next-intl/server";
import { io } from "next/cache";
import { notFound } from "next/navigation";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { Badge } from "@/components/reui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PeopleLoadError } from "@/features/people/components/people-load-error";

import { getShift } from "../shifts-queries";

const DayParam = v.pipe(v.string(), v.regex(/^\d{4}-\d{2}-\d{2}$/));

const SEARCH_BEFORE_DAYS = 30;
const SEARCH_AFTER_DAYS = 60;

const STATUS_VARIANT = {
  draft: "secondary",
  published: "success-light",
  canceled: "destructive-light",
} as const satisfies Record<ShiftStatus, string>;

/**
 * Render inside `<Suspense>`: one shift with its times, places and the people
 * on it. `on` is the day the roster link names; without it the shift is looked
 * up in a window around today.
 */
export async function ShiftDetail({
  id: idPromise,
  on,
}: {
  id: Promise<string>;
  on: Promise<string | string[] | undefined>;
}) {
  await io();
  const today = Temporal.Now.plainDateISO("UTC");
  const [id, onValue] = await Promise.all([idPromise, on]);
  const parsed = v.safeParse(DayParam, onValue);
  const day = parsed.success ? parsed.output : null;

  const [t, format, loaded] = await Promise.all([
    getExtracted("shifts"),
    getFormatter(),
    getShift(
      id,
      day ?? today.subtract({ days: SEARCH_BEFORE_DAYS }).toString(),
      day ?? today.add({ days: SEARCH_AFTER_DAYS }).toString(),
    ),
  ]);

  if (loaded.kind === "no-organization") {
    return null;
  }

  if (loaded.kind === "error") {
    return <PeopleLoadError title={t("This shift didn't load")} />;
  }

  if (loaded.data === "not-found") {
    notFound();
  }

  const shift = loaded.data;

  const assigned = shift.people.filter(
    (person) => person.status === "assigned",
  );

  const requested = shift.people.filter(
    (person) => person.status === "requested",
  );

  const statusLabel = (status: ShiftStatus) => {
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

  const start = new Date(shift.startsAt);
  const end = new Date(shift.endsAt);

  return (
    <RecordDetailFrame
      title={format.dateTime(start, {
        weekday: "long",
        day: "numeric",
        month: "long",
        timeZone: "UTC",
      })}
      description={`${format.dateTime(start, { timeStyle: "short", timeZone: "UTC" })} – ${format.dateTime(end, { timeStyle: "short", timeZone: "UTC" })}`}
      status={
        <Badge variant={STATUS_VARIANT[shift.status]}>
          {statusLabel(shift.status)}
        </Badge>
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Requirements")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2 text-sm">
            <span>
              {t("{assigned}/{headcount} places filled", {
                assigned: String(assigned.length),
                headcount: String(shift.headcount),
              })}
            </span>
            <span className="text-muted-foreground">
              {t("{minutes} minutes break", {
                minutes: String(shift.breakMinutes),
              })}
            </span>
            {shift.requiredQualifications.length === 0 ? (
              <span className="text-muted-foreground">
                {t("No qualifications required")}
              </span>
            ) : (
              <div className="flex flex-wrap gap-1">
                {shift.requiredQualifications.map((key) => (
                  <Badge key={key} variant="outline">
                    {key}
                  </Badge>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      }
    >
      {shift.note === null ? null : (
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Note")}</CardTitle>
          </CardHeader>
          <CardContent className="text-sm">{shift.note}</CardContent>
        </Card>
      )}
      <Card size="sm">
        <CardHeader>
          <CardTitle>{t("People on this shift")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {shift.people.length === 0 ? (
            <span className="text-muted-foreground">
              {t("Nobody is assigned or has asked for this shift yet.")}
            </span>
          ) : (
            [...assigned, ...requested].map((person) => (
              <div
                key={person.id}
                className="flex items-center justify-between gap-2"
              >
                <span className="font-medium">{person.name}</span>
                <Badge
                  variant={
                    person.status === "assigned"
                      ? "success-light"
                      : "warning-light"
                  }
                >
                  {person.status === "assigned"
                    ? t("Assigned")
                    : t("Requested")}
                </Badge>
              </div>
            ))
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function ShiftDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-12" />
      <RecordSectionSkeleton rows={3} />
    </div>
  );
}
