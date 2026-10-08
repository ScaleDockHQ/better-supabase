"use client";

import type { WorkflowRun } from "better-supabase/blocks/workflows";

import { useWorkflowRun } from "better-supabase/blocks/workflows/react";
import { useAction } from "better-supabase/react";
import { CheckIcon, CircleStopIcon, XIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { use } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  isExpenseApproval,
  isFinished,
  statusVariant,
  workflowName,
} from "../workflow-labels";
import { cancelRun, decideApproval } from "../workflows-actions";

/** Render inside `<Suspense>`: reads the `run` param. */
export function WorkflowRunDetail({
  params,
}: {
  params: Promise<{ run: string }>;
}) {
  const { run: id } = use(params);
  const { run, refresh } = useWorkflowRun(id, { schema: "api" });
  if (run === undefined) return <WorkflowRunDetailSkeleton />;
  return <RunCard run={run} onChange={refresh} />;
}

function RunCard({
  run,
  onChange,
}: {
  run: WorkflowRun;
  onChange: () => Promise<void>;
}) {
  const t = useExtracted("workflows");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const handlers = {
    onSuccess: () => {
      void onChange();
    },
    onError: (error: Parameters<typeof errorMessage>[0]) => {
      toast.error(errorMessage(error));
    },
  };
  const cancel = useAction(cancelRun, handlers);
  const decide = useAction(decideApproval, handlers);
  const finished = isFinished(run.status);
  const time = (instant: { epochMilliseconds: number } | undefined) =>
    instant === undefined
      ? "–"
      : format.dateTime(new Date(instant.epochMilliseconds), {
          dateStyle: "medium",
          timeStyle: "medium",
        });
  const steps = [
    [t("Created"), run.createdAt],
    [t("Started"), run.startedAt],
    [t("Finished"), run.completedAt],
  ] as const;
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          {workflowName(run.definition)}
          <Badge variant={statusVariant(run.status)}>{run.status}</Badge>
        </CardTitle>
        <CardDescription className="font-mono text-xs">
          {run.externalId}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <ol className="space-y-2 text-sm">
          {steps.map(([label, instant]) => (
            <li key={label} className="flex justify-between gap-4">
              <span className={instant ? undefined : "text-muted-foreground"}>
                {label}
              </span>
              <span className="text-muted-foreground tabular-nums">
                {time(instant)}
              </span>
            </li>
          ))}
        </ol>
        {run.error ? (
          <p className="text-destructive text-sm">{run.error}</p>
        ) : null}
        {finished ? null : (
          <div className="flex flex-wrap gap-2">
            {isExpenseApproval(run.definition) ? (
              <>
                <Button
                  disabled={decide.pending}
                  onClick={() => {
                    void decide.run({ run: run.externalId, approved: true });
                  }}
                >
                  <CheckIcon />
                  {t("Approve")}
                </Button>
                <Button
                  variant="outline"
                  disabled={decide.pending}
                  onClick={() => {
                    void decide.run({ run: run.externalId, approved: false });
                  }}
                >
                  <XIcon />
                  {t("Reject")}
                </Button>
              </>
            ) : null}
            <Button
              variant="destructive"
              disabled={cancel.pending || run.cancelRequestedAt !== undefined}
              onClick={() => {
                void cancel.run({ run: run.id });
              }}
            >
              <CircleStopIcon />
              {t("Cancel run")}
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export function WorkflowRunDetailSkeleton() {
  return <Skeleton className="h-64 w-full" aria-busy="true" />;
}
