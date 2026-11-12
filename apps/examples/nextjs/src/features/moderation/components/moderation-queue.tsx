import type { ModerationStatus } from "better-supabase/blocks/moderation";

import { ShieldCheckIcon, TriangleAlertIcon } from "lucide-react";
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
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { Link } from "@/i18n/navigation";

import { getBans, getQueue } from "../moderation-queries";
import { DecideButtons } from "./decide-buttons";
import { LiftBanButton } from "./lift-ban-button";
import { STATUS_VARIANT } from "./moderation-labels";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: what needs a moderator, and the active bans. */
export async function ModerationQueue() {
  const [queue, bans, permissions, t, format] = await Promise.all([
    getQueue().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getBans().catch(() => []),
    getPermissions(),
    getExtracted("moderation"),
    getFormatter(),
  ]);

  if (!queue.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The queue didn't load")}</AlertTitle>
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

  if (queue.data === null) {
    return null;
  }

  const day = (value: string) =>
    format.dateTime(new Date(value), {
      dateStyle: "medium",
      timeStyle: "short",
    });

  const statusLabels: Record<ModerationStatus, string> = {
    pending: t("Pending"),
    visible: t("Visible"),
    hidden: t("Hidden"),
    removed: t("Removed"),
  };

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>{t("Review queue")}</CardTitle>
          <CardDescription>
            {t(
              "Content waiting for a first decision and content with open reports, most recently changed first.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {queue.data.length === 0 ? (
            <Empty className="border">
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <ShieldCheckIcon />
                </EmptyMedia>
                <EmptyTitle>{t("Nothing to review")}</EmptyTitle>
                <EmptyDescription>
                  {t(
                    "Reported reviews, comments and posts appear here until a moderator decides.",
                  )}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Content")}</TableHead>
                  <TableHead>{t("Status")}</TableHead>
                  <TableHead className="text-right">{t("Reports")}</TableHead>
                  <TableHead>{t("Changed")}</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {queue.data.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell className="font-medium">
                      <Link
                        href={`/moderation/${row.subjectType}/${row.subjectId}`}
                        className="hover:underline"
                      >
                        {row.subjectType} {row.subjectId.slice(0, 8)}
                      </Link>
                    </TableCell>
                    <TableCell>
                      <Badge variant={STATUS_VARIANT[row.status]}>
                        {statusLabels[row.status]}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {row.openReports}
                    </TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      {day(row.updatedAt)}
                    </TableCell>
                    <TableCell>
                      {can(permissions, "moderation.manage") ? (
                        <DecideButtons
                          itemId={row.id}
                          decisions={
                            row.status === "hidden" || row.status === "removed"
                              ? ["restore"]
                              : ["approve", "hide", "remove"]
                          }
                        />
                      ) : null}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Bans")}</CardTitle>
          <CardDescription>
            {t(
              "Members who can't post, until the ban ends or a moderator lifts it.",
            )}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {bans.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("Nobody is banned.")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Member")}</TableHead>
                  <TableHead>{t("Reason")}</TableHead>
                  <TableHead>{t("Until")}</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {bans.map((ban) => (
                  <TableRow key={ban.id}>
                    <TableCell className="font-medium">
                      {ban.userId.slice(0, 8)}
                    </TableCell>
                    <TableCell>{ban.reason ?? "–"}</TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      {ban.expiresAt ? day(ban.expiresAt) : t("No end")}
                    </TableCell>
                    <TableCell className="text-right">
                      {can(permissions, "moderation.ban") ? (
                        <LiftBanButton banId={ban.id} />
                      ) : null}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </>
  );
}

export function ModerationQueueSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
