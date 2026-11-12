import type { AnnouncementSeverity } from "better-supabase/blocks/announcements";

import { TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

import { getAnnouncements } from "../announcements-queries";
import { ANNOUNCEMENT_VARIANT } from "./announcement-labels";
import { DismissButton } from "./dismiss-button";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** One live announcement with its dates, link and dismiss action. */
export async function AnnouncementDetail({ id }: { id: string }) {
  const [result, t, format] = await Promise.all([
    getAnnouncements().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("announcements"),
    getFormatter(),
  ]);

  if (!result.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The announcement didn't load")}</AlertTitle>
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

  const announcement = result.data.find((row) => row.id === id);

  if (!announcement) {
    notFound();
  }

  const when = (value: string) =>
    format.dateTime(new Date(value), {
      dateStyle: "medium",
      timeStyle: "short",
    });

  const severityLabels: Record<AnnouncementSeverity, string> = {
    info: t("Info"),
    success: t("Success"),
    warning: t("Warning"),
    critical: t("Critical"),
  };

  return (
    <RecordDetailFrame
      title={announcement.title}
      description={
        announcement.endsAt
          ? t("Live from {from} until {until}", {
              from: when(announcement.startsAt),
              until: when(announcement.endsAt),
            })
          : t("Live since {from}", { from: when(announcement.startsAt) })
      }
      status={
        <Badge variant={ANNOUNCEMENT_VARIANT[announcement.severity]}>
          {severityLabels[announcement.severity]}
        </Badge>
      }
      actions={
        announcement.dismissible ? <DismissButton id={announcement.id} /> : null
      }
    >
      <p className="text-sm whitespace-pre-line">{announcement.body}</p>
      {announcement.href ? (
        <a
          className="text-sm underline underline-offset-4"
          href={announcement.href}
        >
          {t("Learn more")}
        </a>
      ) : null}
    </RecordDetailFrame>
  );
}

export function AnnouncementDetailSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
