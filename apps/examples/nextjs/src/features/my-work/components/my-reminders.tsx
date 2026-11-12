import { BellIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { io } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button, buttonVariants } from "@/components/ui/button";
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

import { retryMyWork } from "../my-work-actions";
import { getMyReminders } from "../my-work-queries";
import { MyReminderRow } from "./my-reminder-row";

/**
 * Render inside `<Suspense>` and a `PermissionGate` for `reminders.manage`:
 * every reminder the caller set, with the subject it is on.
 */
export async function MyReminders() {
  const [reminders, t, format] = await Promise.all([
    getMyReminders(),
    getExtracted("myWork"),
    getFormatter(),
    io(),
  ]);

  if (reminders.kind === "no-organization") {
    return null;
  }

  return (
    <Card data-recipe="my-reminders">
      <CardHeader>
        <CardTitle>{t("Your reminders")}</CardTitle>
        <CardDescription>
          {t("Reminders you set on events and records. Remove one here.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {reminders.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("Your reminders didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retryMyWork}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : reminders.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <BellIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No reminders set")}</EmptyTitle>
              <EmptyDescription>
                {t("Set a reminder on a calendar event and it shows up here.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link
                href="/calendar"
                className={buttonVariants({ variant: "outline", size: "sm" })}
              >
                {t("Open the calendar")}
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <ul className="flex flex-col gap-2">
            {reminders.data.map((reminder) => (
              <MyReminderRow
                key={reminder.id}
                id={reminder.id}
                subject={`${reminder.subjectType} ${reminder.subjectId.slice(0, 8)}`}
                offsetMinutes={reminder.offsetMinutes}
                at={
                  reminder.remindAt === null
                    ? null
                    : format.dateTime(new Date(reminder.remindAt), {
                        dateStyle: "medium",
                        timeStyle: "short",
                      })
                }
              />
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

export function MyRemindersSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
