import { GitPullRequestArrowIcon, TriangleAlertIcon } from "lucide-react";
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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import type { ChangeStage } from "../change-request-lifecycle";

import { getChangeRequests } from "../change-requests-queries";
import { MoveChangeRequestMenu } from "./move-change-request-menu";
import { NewChangeRequestDialog } from "./new-change-request-dialog";
import { SetUpChangeWorkflowButton } from "./set-up-change-workflow-button";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

type StageVariant = "info-light" | "secondary" | "success-light";

/** Render inside `<Suspense>`: the change requests and the moves each may make. */
export async function ChangeRequestList() {
  const [data, t, format, permissions] = await Promise.all([
    getChangeRequests().then(
      (value) => ({ ok: true as const, value }),
      () => ({ ok: false as const }),
    ),
    getExtracted("changeRequests"),
    getFormatter(),
    getPermissions(),
  ]);

  if (!data.ok) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The change requests didn't load")}</AlertTitle>
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

  if (data.value === null) {
    return null;
  }

  const { lifecycle, rows } = data.value;

  if (lifecycle === null) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <GitPullRequestArrowIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No change workflow yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Change requests move through the stages of the organization's change workflow. Publish the default one (submitted, CAB review, scheduled, done) and edit it in the workflow builder later.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          {can(permissions, "workflow_editor.manage") ? (
            <SetUpChangeWorkflowButton />
          ) : (
            <p className="text-sm text-muted-foreground">
              {t("Ask an admin to set up the change workflow.")}
            </p>
          )}
        </EmptyContent>
      </Empty>
    );
  }

  const labels = new Map(
    lifecycle.stages.map((stage) => [stage.id, stage.label]),
  );

  const last = lifecycle.stages.at(-1)?.id;

  const variantOf = (status: string | null): StageVariant => {
    if (status === last) {
      return "success-light";
    }

    return status === lifecycle.initial ? "secondary" : "info-light";
  };

  const movesOf = (status: string | null): readonly ChangeStage[] =>
    (status === null ? [] : (lifecycle.moves[status] ?? [])).map((id) => ({
      id,
      label: labels.get(id) ?? id,
    }));

  if (rows.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <GitPullRequestArrowIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No change requests")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "Submit a change before you make it, so the board can review and schedule it.",
            )}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <NewChangeRequestDialog />
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        <p className="text-xs text-muted-foreground">
          {t("Workflow version {version}: {stages}", {
            version: String(lifecycle.version),
            stages: lifecycle.stages.map((stage) => stage.label).join(", "),
          })}
        </p>
        <NewChangeRequestDialog />
      </div>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t("Change")}</TableHead>
            <TableHead>{t("Stage")}</TableHead>
            <TableHead>{t("Submitted")}</TableHead>
            <TableHead>
              <span className="sr-only">{t("Actions")}</span>
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => (
            <TableRow key={row.id}>
              <TableCell className="font-medium">{row.title}</TableCell>
              <TableCell>
                <Badge variant={variantOf(row.status)}>
                  {row.status === null
                    ? t("No stage")
                    : (labels.get(row.status) ?? row.status)}
                </Badge>
              </TableCell>
              <TableCell className="text-xs text-muted-foreground">
                {format.dateTime(new Date(row.createdAt), {
                  dateStyle: "medium",
                })}
              </TableCell>
              <TableCell className="text-right">
                <MoveChangeRequestMenu
                  id={row.id}
                  title={row.title}
                  moves={movesOf(row.status)}
                />
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

export function ChangeRequestListSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
