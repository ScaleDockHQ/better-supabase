import { CalendarXIcon, ChevronRightIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

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
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import { loadPublicBooking, settle } from "../bookings-queries";
import { BookingsLoadError } from "./bookings-load-error";
import { SlotPicker } from "./slot-picker";

// #region recipe:booking-page
/** The public page of a booking link: open slots for a week, then a form. */
export async function BookingPage({
  params,
  searchParams,
}: {
  params: Promise<{ token: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ token }, query, t, format] = await Promise.all([
    params,
    searchParams,
    getExtracted("bookings"),
    getFormatter(),
  ]);

  const parsed = v.safeParse(v.pipe(v.string(), v.isoDate()), query["from"]);
  const from = parsed.success ? parsed.output : undefined;
  const page = await settle(() => loadPublicBooking(token, from));

  if (page.kind === "missing") {
    notFound();
  }

  if (page.kind === "error") {
    return (
      <Card data-recipe="booking-page" className="w-full max-w-xl">
        <CardHeader>
          <CardTitle>{t("Book a time")}</CardTitle>
        </CardHeader>
        <CardContent>
          <BookingsLoadError title={t("The open times didn't load.")} />
        </CardContent>
      </Card>
    );
  }

  const { data } = page;

  const next = Temporal.PlainDate.from(data.from).add({ days: 7 }).toString();

  const days = data.days.map((day) => ({
    ...day,
    label: format.dateTime(new Date(`${day.date}T12:00:00Z`), {
      weekday: "long",
      day: "numeric",
      month: "long",
      timeZone: "UTC",
    }),
  }));

  return (
    <Card data-recipe="booking-page" className="w-full max-w-xl">
      <CardHeader>
        <CardTitle>{data.serviceName}</CardTitle>
        <CardDescription>
          {t("{minutes} minutes with {host}. Times are in {tz}.", {
            minutes: String(data.minutes),
            host: data.hostName,
            tz: data.tz,
          })}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        {days.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <CalendarXIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No open times this week")}</EmptyTitle>
              <EmptyDescription>
                {t("Look at the week after for an open time.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link
                href={`/book/${token}?from=${next}`}
                className={buttonVariants({ variant: "outline" })}
              >
                {t("Next week")}
                <ChevronRightIcon />
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <>
            <SlotPicker token={token} days={days} />
            <div className="flex justify-end">
              <Link
                href={`/book/${token}?from=${next}`}
                className={buttonVariants({ variant: "ghost", size: "sm" })}
              >
                {t("Next week")}
                <ChevronRightIcon />
              </Link>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:booking-page

export function BookingPageSkeleton() {
  return (
    <Card className="w-full max-w-xl">
      <CardHeader>
        <Skeleton className="h-5 w-40" />
        <Skeleton className="h-4 w-64" />
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {Array.from({ length: 3 }, (_, index) => (
          <div key={index} className="flex flex-col gap-2">
            <Skeleton className="h-4 w-32" />
            <div className="flex gap-2">
              <Skeleton className="h-8 w-16" />
              <Skeleton className="h-8 w-16" />
              <Skeleton className="h-8 w-16" />
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
