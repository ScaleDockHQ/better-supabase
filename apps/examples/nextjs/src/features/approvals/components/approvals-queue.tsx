import { ShieldCheckIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden } from "next/navigation";

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

import { retryApprovals } from "../approvals-actions";
import { getApprovalsQueue } from "../approvals-queries";
import { ApprovalDecision } from "./approval-decision";
import { RequestApprovalDialog } from "./request-approval-dialog";

// #region recipe:approvals-queue
/**
 * Render inside `<Suspense>`: the organization's pending approval requests,
 * newest first, with Approve and Reject on each. The block checks that the
 * caller is an approver of the current step.
 */
export async function ApprovalsQueue() {
  const [session, t, format] = await Promise.all([
    getSession(),
    getExtracted("approvals"),
    getFormatter(),
  ]);

  if (!can(session, "approvals.read")) {
    forbidden();
  }

  const queue = await getApprovalsQueue();

  if (queue.kind === "no-organization") {
    return null;
  }

  const canRequest = can(session, "approvals.request");
  const canDecide = can(session, "approvals.manage");
  const customers = queue.kind === "ok" ? queue.data.customers : [];

  const actionLabel = (action: string) =>
    action === "discount" ? t("Discount") : action;

  return (
    <Card data-recipe="approvals-queue">
      <CardHeader>
        <CardTitle>{t("Pending requests")}</CardTitle>
        <CardDescription>
          {t("Each request waits for its approvers, one step at a time.")}
        </CardDescription>
        {canRequest && queue.kind === "ok" && queue.data.requests.length > 0 ? (
          <CardAction>
            <RequestApprovalDialog customers={customers} />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {queue.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The requests didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retryApprovals}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : queue.data.requests.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ShieldCheckIcon />
              </EmptyMedia>
              <EmptyTitle>{t("Nothing waiting")}</EmptyTitle>
              <EmptyDescription>
                {canRequest
                  ? t(
                      "Ask for an approval before giving a customer a discount.",
                    )
                  : t("New requests show up here.")}
              </EmptyDescription>
            </EmptyHeader>
            {canRequest ? (
              <EmptyContent>
                <RequestApprovalDialog customers={customers} />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Request")}</TableHead>
                <TableHead>{t("Requested by")}</TableHead>
                <TableHead>{t("Step")}</TableHead>
                <TableHead>{t("Requested")}</TableHead>
                {canDecide ? (
                  <TableHead className="text-right">{t("Decision")}</TableHead>
                ) : null}
              </TableRow>
            </TableHeader>
            <TableBody>
              {queue.data.requests.map((request) => {
                const label = `${actionLabel(request.action)}: ${
                  request.subjectName ?? request.subjectId
                }`;

                return (
                  <TableRow key={request.id}>
                    <TableCell>
                      <div className="flex flex-col gap-1">
                        <span className="font-medium">{label}</span>
                        {request.reason ? (
                          <span className="text-xs text-muted-foreground">
                            {request.reason}
                          </span>
                        ) : null}
                      </div>
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {request.requestedBy ?? t("Unknown")}
                    </TableCell>
                    <TableCell>
                      <Badge variant="warning-light">
                        {t("{step, number} of {steps, number}", {
                          step: request.step + 1,
                          steps: request.steps,
                        })}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {format.dateTime(new Date(request.createdAt), {
                        dateStyle: "medium",
                        timeStyle: "short",
                      })}
                    </TableCell>
                    {canDecide ? (
                      <TableCell>
                        <ApprovalDecision id={request.id} label={label} />
                      </TableCell>
                    ) : null}
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
// #endregion recipe:approvals-queue

export function ApprovalsQueueSkeleton() {
  return <Skeleton className="h-96 rounded-xl" aria-busy="true" />;
}
