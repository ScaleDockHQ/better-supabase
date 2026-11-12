import type { AnnouncementSeverity } from "better-supabase/blocks/announcements";

import { MegaphoneIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
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
import { Link } from "@/i18n/navigation";

import { getAnnouncements } from "../announcements-queries";
import { ANNOUNCEMENT_VARIANT } from "./announcement-labels";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the live announcements for the caller. */
export async function AnnouncementList() {
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
        <AlertTitle>{t("The announcements didn't load")}</AlertTitle>
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

  if (result.data.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <MegaphoneIcon />
          </EmptyMedia>
          <EmptyTitle>{t("Nothing new")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Product news and maintenance notices for your organization show up here until you dismiss them.",
            )}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  const severityLabels: Record<AnnouncementSeverity, string> = {
    info: t("Info"),
    success: t("Success"),
    warning: t("Warning"),
    critical: t("Critical"),
  };

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("Announcement")}</TableHead>
          <TableHead>{t("Severity")}</TableHead>
          <TableHead>{t("Since")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {result.data.map((row) => (
          <TableRow key={row.id}>
            <TableCell className="font-medium">
              <Link
                href={`/announcements/${row.id}`}
                className="hover:underline"
              >
                {row.title}
              </Link>
            </TableCell>
            <TableCell>
              <Badge variant={ANNOUNCEMENT_VARIANT[row.severity]}>
                {severityLabels[row.severity]}
              </Badge>
            </TableCell>
            <TableCell className="text-xs text-muted-foreground">
              {format.dateTime(new Date(row.startsAt), {
                dateStyle: "medium",
                timeStyle: "short",
              })}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

export function AnnouncementListSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
