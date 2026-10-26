import type { MyWorkKind } from "better-supabase/blocks/subjects";

import { InboxIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
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
import { Link, toAppHref } from "@/i18n/navigation";

import { retryMyWork } from "../my-work-actions";
import { getMyWork } from "../my-work-queries";

const BADGES = {
  assigned: "primary-light",
  approval: "warning-light",
  reminder: "info-light",
  mention: "invert-light",
  sla: "destructive-light",
} as const satisfies Record<MyWorkKind, string>;

// #region recipe:my-work
/**
 * Render inside `<Suspense>`: everything that waits on the caller, from
 * `loadMyWork`, newest first.
 */
export async function MyWorkList() {
  const [work, t, format] = await Promise.all([
    getMyWork(),
    getExtracted("myWork"),
    getFormatter(),
  ]);

  if (work.kind === "no-organization") {
    return null;
  }

  const kindLabel = (kind: MyWorkKind): string => {
    switch (kind) {
      case "assigned": {
        return t("Assigned");
      }

      case "approval": {
        return t("Approval");
      }

      case "reminder": {
        return t("Reminder");
      }

      case "mention": {
        return t("Mention");
      }

      case "sla": {
        return t("SLA warning");
      }

      default: {
        const never: never = kind;

        return never;
      }
    }
  };

  return (
    <Card data-recipe="my-work">
      <CardHeader>
        <CardTitle>{t("Waiting on you")}</CardTitle>
        <CardDescription>
          {t(
            "Assigned work, approvals, due reminders, mentions and SLA warnings.",
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {work.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("My work didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retryMyWork}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : work.data.rows.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <InboxIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Nothing waiting on you")}</EmptyTitle>
              <EmptyDescription>
                {t("Work assigned to you and requests for you show up here.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Link
                href="/work"
                className={buttonVariants({ variant: "outline", size: "sm" })}
              >
                {t("Open the work board")}
              </Link>
            </EmptyContent>
          </Empty>
        ) : (
          <ul className="flex flex-col gap-1">
            {work.data.rows.map((row) => (
              <li key={row.key} className="flex items-center gap-2 text-sm">
                <Badge variant={BADGES[row.kind]}>{kindLabel(row.kind)}</Badge>
                {row.url === null ? (
                  <span className="truncate">{row.title}</span>
                ) : (
                  <Link
                    href={toAppHref(row.url)}
                    className="truncate font-medium underline-offset-4 transition-colors hover:underline"
                  >
                    {row.title}
                  </Link>
                )}
                {row.at === null ? null : (
                  <time
                    dateTime={new Date(row.at).toISOString()}
                    className="ml-auto shrink-0 text-xs text-muted-foreground tabular-nums"
                  >
                    {format.relativeTime(row.at)}
                  </time>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:my-work

export function MyWorkListSkeleton() {
  return (
    <Card aria-busy="true">
      <CardHeader>
        <Skeleton className="h-5 w-32" />
        <Skeleton className="h-4 w-64" />
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {Array.from({ length: 5 }, (_, index) => (
          <Skeleton key={index} className="h-6" />
        ))}
      </CardContent>
    </Card>
  );
}
