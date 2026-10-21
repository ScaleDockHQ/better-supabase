import { CalendarClockIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";
import { forbidden } from "next/navigation";

import { Badge } from "@/components/reui/badge";
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

import { loadBookingSetup, settle } from "../bookings-queries";
import { BookingLinkButton } from "./booking-link-button";
import { BookingsLoadError } from "./bookings-load-error";
import { SetUpBookingButton } from "./set-up-booking-button";
import { WeeklyHoursForm } from "./weekly-hours-form";

// #region recipe:availability-editor
export async function AvailabilityEditor() {
  const session = await getSession();

  if (!can(session, "bookings.manage")) {
    forbidden();
  }

  const [t, setup] = await Promise.all([
    getExtracted("bookings"),
    settle(loadBookingSetup),
  ]);

  const page = setup.kind === "ok" ? setup.data.page : null;

  return (
    <Card data-recipe="availability-editor">
      <CardHeader>
        <CardTitle>{t("Weekly hours")}</CardTitle>
        <CardDescription>
          {page
            ? t(
                "Visitors can book 30 minute slots inside these hours, in {tz}.",
                { tz: page.tz },
              )
            : t("The hours visitors can book you in.")}
        </CardDescription>
        {page ? (
          <CardAction className="flex items-center gap-2">
            <Badge variant={page.liveLinks > 0 ? "success-light" : "secondary"}>
              {t(
                "{count, plural, =0 {No live links} one {# live link} other {# live links}}",
                { count: page.liveLinks },
              )}
            </Badge>
            {can(session, "share_links.create") ? <BookingLinkButton /> : null}
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {setup.kind === "error" ? (
          <BookingsLoadError title={t("Your booking page didn't load.")} />
        ) : page && setup.kind === "ok" ? (
          <WeeklyHoursForm hours={setup.data.hours} />
        ) : (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <CalendarClockIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No booking page yet")}</EmptyTitle>
              <EmptyDescription>
                {setup.kind === "missing"
                  ? t("Pick an organization to set up a booking page.")
                  : t(
                      "Set it up with weekday hours from 09:00 to 17:00, then change them here.",
                    )}
              </EmptyDescription>
            </EmptyHeader>
            {setup.kind === "ok" ? (
              <EmptyContent>
                <SetUpBookingButton />
              </EmptyContent>
            ) : null}
          </Empty>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:availability-editor

export function AvailabilityEditorSkeleton() {
  return (
    <Card>
      <CardHeader>
        <Skeleton className="h-5 w-32" />
        <Skeleton className="h-4 w-72" />
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {Array.from({ length: 7 }, (_, index) => (
          <Skeleton key={index} className="h-8 w-full" />
        ))}
      </CardContent>
    </Card>
  );
}
