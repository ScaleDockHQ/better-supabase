import { ListChecksIcon, TriangleAlertIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { refresh } from "next/cache";
import { forbidden, unstable_rethrow } from "next/navigation";

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

import {
  type JobRunRow,
  type JobRunStatus,
  loadJobRuns,
} from "../jobs-queries";
import { JOBS_PERMISSION } from "../jobs-server";
import { EnqueueTestJobButton, RetryJobButton } from "./job-run-controls";

// #region recipe:job-runs-table
type JobRunsState =
  | { readonly kind: "ok"; readonly runs: readonly JobRunRow[] }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

async function loadJobRunsState(): Promise<JobRunsState> {
  try {
    const runs = await loadJobRuns();

    return runs ? { kind: "ok", runs } : { kind: "no-organization" };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

type Translate = Awaited<ReturnType<typeof getExtracted>>;

function JobStatusBadge({ status, t }: { status: JobRunStatus; t: Translate }) {
  switch (status) {
    case "queued": {
      return <Badge variant="info-light">{t("Queued")}</Badge>;
    }

    case "scheduled": {
      return <Badge variant="secondary">{t("Scheduled")}</Badge>;
    }

    case "running": {
      return <Badge variant="primary-light">{t("Running")}</Badge>;
    }

    case "retrying": {
      return <Badge variant="warning-light">{t("Retrying")}</Badge>;
    }

    case "succeeded": {
      return <Badge variant="success-light">{t("Succeeded")}</Badge>;
    }

    case "dead": {
      return <Badge variant="destructive-light">{t("Failed")}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

/**
 * Render inside `<Suspense>`: the organization's latest background jobs
 * across every queue, with a retry button on failed runs. Gated by
 * `audit.read`, since it reads with the database owner.
 */
export async function JobRunsTable() {
  const [session, t, format] = await Promise.all([
    getSession(),
    getExtracted("jobs"),
    getFormatter(),
  ]);

  if (!can(session, JOBS_PERMISSION)) {
    forbidden();
  }

  const state = await loadJobRunsState();

  if (state.kind === "no-organization") {
    return null;
  }

  const when = (iso: string) =>
    format.dateTime(new Date(iso), { dateStyle: "medium", timeStyle: "short" });

  return (
    <Card data-recipe="job-runs-table">
      <CardHeader>
        <CardTitle>{t("Job runs")}</CardTitle>
        <CardDescription>
          {t(
            "Background work queued for this organization, newest first. Failed jobs retry with backoff before they stop.",
          )}
        </CardDescription>
        {state.kind === "ok" && state.runs.length > 0 ? (
          <CardAction>
            <EnqueueTestJobButton variant="outline" />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The job runs didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <form action={retry}>
                <Button size="sm" variant="outline" type="submit">
                  {t("Retry")}
                </Button>
              </form>
            </AlertAction>
          </Alert>
        ) : state.runs.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ListChecksIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No job runs yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Jobs are queued when the app hands work to the background, such as a webhook delivery or an import. Queue a test job to see one here.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <EnqueueTestJobButton />
            </EmptyContent>
          </Empty>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("Job")}</TableHead>
                <TableHead>{t("Status")}</TableHead>
                <TableHead>{t("Attempts")}</TableHead>
                <TableHead>{t("Queued")}</TableHead>
                <TableHead>{t("Finished")}</TableHead>
                <TableHead className="text-right">{t("Actions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {state.runs.map((run) => (
                <TableRow key={`${run.queue}:${String(run.id)}`}>
                  <TableCell>
                    <div className="flex flex-col gap-1">
                      <span className="font-mono text-sm">{run.queue}</span>
                      <span
                        className="max-w-xs truncate text-xs text-muted-foreground"
                        title={run.lastError ?? undefined}
                      >
                        {run.lastError ?? `#${String(run.id)}`}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell>
                    <JobStatusBadge status={run.status} t={t} />
                  </TableCell>
                  <TableCell className="tabular-nums">{run.attempts}</TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {when(run.enqueuedAt)}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {run.finishedAt ? when(run.finishedAt) : "–"}
                  </TableCell>
                  <TableCell className="text-right">
                    {run.status === "dead" ? (
                      <RetryJobButton queue={run.queue} id={run.id} />
                    ) : null}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

export function JobRunsTableSkeleton() {
  return <Skeleton className="h-40 rounded-xl" aria-busy="true" />;
}
// #endregion recipe:job-runs-table
