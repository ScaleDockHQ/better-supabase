import type { AccessRequestStatus } from "better-supabase/blocks/access-requests";

import { InboxIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden, unstable_rethrow } from "next/navigation";

import type { BadgeProps } from "@/components/reui/badge";

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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import type { AccessRequestsData } from "../access-requests-queries";

import { refreshAccessRequests } from "../access-requests-actions";
import { loadAccessRequests } from "../access-requests-queries";
import {
  AccessRequestActions,
  RequestAccessForm,
} from "./access-request-controls";

async function loadInbox(): Promise<
  { kind: "ok"; data: AccessRequestsData | null } | { kind: "error" }
> {
  try {
    return { kind: "ok", data: await loadAccessRequests() };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

const STATUS_VARIANT: Record<AccessRequestStatus, BadgeProps["variant"]> = {
  pending: "warning-light",
  granted: "success-light",
  rejected: "destructive-light",
  cancelled: "secondary",
  expired: "secondary",
  ended: "secondary",
};

// #region recipe:access-requests-inbox
/**
 * Requests for a temporary role in the active organization. Members ask for
 * one; members with `members.update_role` approve or deny it, and the role goes
 * back to the previous one when the duration runs out.
 */
export async function AccessRequestsInbox() {
  if (!can(await getSession(), "access_requests.create")) {
    forbidden();
  }

  const [t, format, result] = await Promise.all([
    getExtracted("accessRequests"),
    getFormatter(),
    loadInbox(),
  ]);

  if (result.kind === "error") {
    return (
      <Alert variant="destructive" data-recipe="access-requests-inbox">
        <TriangleAlertIcon />
        <AlertTitle>{t("Access requests could not be loaded")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <form action={refreshAccessRequests}>
            <Button size="sm" variant="outline" type="submit">
              {t("Retry")}
            </Button>
          </form>
        </AlertAction>
      </Alert>
    );
  }

  if (result.data === null) {
    return (
      <p
        className="text-sm text-muted-foreground"
        data-recipe="access-requests-inbox"
      >
        {t("Pick an organization to see its access requests.")}
      </p>
    );
  }

  const { requests, role, userId, canDecide } = result.data;
  const canRequest = role !== undefined && role !== "owner";

  const statusLabel = (status: AccessRequestStatus) => {
    switch (status) {
      case "pending": {
        return t("Pending");
      }

      case "granted": {
        return t("Granted");
      }

      case "rejected": {
        return t("Denied");
      }

      case "cancelled": {
        return t("Withdrawn");
      }

      case "expired": {
        return t("Expired");
      }

      case "ended": {
        return t("Ended");
      }

      default: {
        const unknown: never = status;

        return unknown;
      }
    }
  };

  const roleLabel = (value: string) =>
    value === "admin" ? t("Admin") : value === "member" ? t("Member") : value;

  const durationLabel = (value: string | null) => {
    switch (value) {
      case null: {
        return t("Until revoked");
      }

      case "PT1H": {
        return t("1 hour");
      }

      case "P1D": {
        return t("1 day");
      }

      case "P7D": {
        return t("7 days");
      }

      default: {
        return value;
      }
    }
  };

  const date = (value: string) =>
    format.dateTime(new Date(value), {
      dateStyle: "medium",
      timeStyle: "short",
    });

  return (
    <div className="flex flex-col gap-6" data-recipe="access-requests-inbox">
      {canRequest ? (
        <Card id="request-access">
          <CardHeader>
            <CardTitle>{t("Request access")}</CardTitle>
            <CardDescription>
              {t(
                "Ask for a higher role for a limited time. An admin or owner approves it.",
              )}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <RequestAccessForm currentRole={role} />
          </CardContent>
        </Card>
      ) : null}
      <Card>
        <CardHeader>
          <CardTitle>{t("Requests")}</CardTitle>
          <CardDescription>
            {canDecide
              ? t("Approve or deny what members asked for.")
              : t("The requests you sent and what happened to them.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {requests.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <InboxIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No access requests")}</EmptyTitle>
                <EmptyDescription>
                  {canRequest
                    ? t("Requests you and other members send show up here.")
                    : t(
                        "Requests from members show up here for you to decide.",
                      )}
                </EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                {canRequest ? (
                  <a
                    href="#request-access"
                    className={buttonVariants({ variant: "outline" })}
                  >
                    {t("Request a role")}
                  </a>
                ) : (
                  <Link
                    href="/settings/members"
                    className={buttonVariants({ variant: "outline" })}
                  >
                    {t("View members")}
                  </Link>
                )}
              </EmptyContent>
            </Empty>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("Member")}</TableHead>
                  <TableHead>{t("Role")}</TableHead>
                  <TableHead className="hidden md:table-cell">
                    {t("Duration")}
                  </TableHead>
                  <TableHead>{t("Status")}</TableHead>
                  <TableHead className="text-right">
                    <span className="sr-only">{t("Actions")}</span>
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {requests.map((request) => (
                  <TableRow key={request.id}>
                    <TableCell>
                      <div className="flex flex-col gap-1">
                        <span className="font-medium">
                          {request.userId === userId
                            ? t("You")
                            : request.requester}
                        </span>
                        <span className="text-xs text-muted-foreground">
                          {request.reason ?? date(request.createdAt)}
                        </span>
                      </div>
                    </TableCell>
                    <TableCell>{roleLabel(request.role)}</TableCell>
                    <TableCell className="hidden text-muted-foreground md:table-cell">
                      {request.status === "granted" && request.expiresAt
                        ? t("Until {date}", { date: date(request.expiresAt) })
                        : durationLabel(request.duration)}
                    </TableCell>
                    <TableCell>
                      <Badge variant={STATUS_VARIANT[request.status]}>
                        {statusLabel(request.status)}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      <AccessRequestActions
                        request={request}
                        mine={request.userId === userId}
                        canDecide={canDecide}
                      />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
// #endregion recipe:access-requests-inbox

export function AccessRequestsInboxSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Skeleton className="h-56 rounded-xl" />
      <Skeleton className="h-64 rounded-xl" />
    </div>
  );
}
