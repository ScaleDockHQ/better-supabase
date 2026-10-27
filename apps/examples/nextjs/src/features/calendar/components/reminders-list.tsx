import { BellIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { connection } from "next/server";
import { Temporal } from "temporal-polyfill";

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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { loadUpcomingReminders, settle } from "../calendar-queries";
import { CalendarLoadError } from "./calendar-load-error";
import { CreateEventDialog } from "./create-event-dialog";
import { EventReminders } from "./event-reminders";

// #region recipe:reminders-list
/**
 * The next events with the caller's reminders on each. A reminder fires its
 * offset before every occurrence of the event, once per occurrence.
 */
export async function RemindersList() {
  // The read starts with the permission check; RLS guards it either way.
  const [permissions, t, format, upcoming] = await Promise.all([
    getPermissions(),
    getExtracted("calendar"),
    getFormatter(),
    settle(loadUpcomingReminders),
    connection(),
  ]);

  if (!can(permissions, "reminders.manage")) {
    return null;
  }

  if (upcoming.kind === "no-organization") {
    return null;
  }

  const calendars = upcoming.kind === "ok" ? upcoming.data.calendars : [];

  const defaultDate = Temporal.Now.plainDateISO(
    calendars[0]?.tz ?? "UTC",
  ).toString();

  return (
    <Card data-recipe="reminders-list">
      <CardHeader>
        <CardTitle>{t("Upcoming reminders")}</CardTitle>
        <CardDescription>
          {t("Get a notification before the events of the next two weeks.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {upcoming.kind === "error" ? (
          <CalendarLoadError title={t("Your reminders didn't load.")} />
        ) : upcoming.data.events.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <BellIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No events coming up")}</EmptyTitle>
              <EmptyDescription>
                {t("Add an event, then set a reminder for it here.")}
              </EmptyDescription>
            </EmptyHeader>
            {calendars.length > 0 && can(permissions, "calendar.write") ? (
              <EmptyContent>
                <CreateEventDialog
                  calendars={calendars}
                  defaultDate={defaultDate}
                />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <ul className="flex flex-col gap-2">
            {upcoming.data.events.map((event) => (
              <EventReminders
                key={event.id}
                eventId={event.id}
                title={event.title}
                when={format.dateTime(
                  new Date(event.startsAt),
                  event.allDay
                    ? { dateStyle: "medium" }
                    : { dateStyle: "medium", timeStyle: "short" },
                )}
                reminders={event.reminders}
              />
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:reminders-list

export function RemindersListSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
