import { LifeBuoyIcon, TriangleAlertIcon } from "lucide-react";
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
import { PermissionGate } from "@/features/user/components/permission-gate";

import { getSupportSessions } from "../support-queries";
import { EndSupportSessionButton } from "./end-session-button";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

/** Render inside `<Suspense>`: the support sessions platform staff opened. */
export async function SupportSessions() {
  const [result, t, format] = await Promise.all([
    getSupportSessions().then(
      (data) => ({ ok: true as const, data }),
      () => ({ ok: false as const }),
    ),
    getExtracted("support"),
    getFormatter(),
  ]);

  if (!result.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The support sessions didn't load")}</AlertTitle>
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
            <LifeBuoyIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No support sessions")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Platform staff see the sessions they opened here. Request one to view the app as a user.",
            )}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  const now = Date.now();

  const when = (value: string) =>
    format.dateTime(new Date(value), {
      dateStyle: "medium",
      timeStyle: "short",
    });

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("User")}</TableHead>
          <TableHead>{t("Reason")}</TableHead>
          <TableHead>{t("Started")}</TableHead>
          <TableHead>{t("State")}</TableHead>
          <TableHead className="text-right">{t("Actions")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {result.data.map((session) => {
          const live =
            session.endedAt === null && Date.parse(session.expiresAt) > now;

          return (
            <TableRow key={session.id}>
              <TableCell className="font-mono text-xs">
                {session.targetUserId}
              </TableCell>
              <TableCell>{session.reason ?? "-"}</TableCell>
              <TableCell className="text-xs text-muted-foreground">
                {when(session.startedAt)}
              </TableCell>
              <TableCell>
                <Badge variant={live ? "warning-light" : "secondary"}>
                  {live ? t("Active") : t("Ended")}
                </Badge>
              </TableCell>
              <TableCell className="text-right">
                {live ? (
                  <PermissionGate permission="impersonation.revoke">
                    <EndSupportSessionButton sessionId={session.id} />
                  </PermissionGate>
                ) : null}
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}

export function SupportSessionsSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
