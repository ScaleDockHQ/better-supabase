"use client";

import type { WorkflowNodeRun } from "better-supabase/blocks/workflow-editor";

import { useAction } from "better-supabase/react";
import {
  CheckIcon,
  CircleStopIcon,
  PencilRulerIcon,
  WorkflowIcon,
  XIcon,
} from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import * as v from "valibot";

import { Badge } from "@/components/reui/badge";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Button } from "@/components/ui/button";
import {
  CodeBlock,
  CodeBlockContent,
  CodeBlockHeader,
  CodeBlockTitle,
} from "@/components/ui/code-block";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Trace,
  TraceCollapsible,
  TraceCollapsibleContent,
  TraceCollapsibleTrigger,
  TraceDescription,
  TraceIcon,
  TraceLine,
  TraceTitle,
} from "@/components/ui/trace";
import { useWorkflowCanvasRun } from "@/hooks/use-workflow-editor";
import { Link } from "@/i18n/navigation";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { JsonObject, JsonValue } from "../builder/config-templates";
import type { RunDetailData, RunStepNode } from "../workflows-queries";

import { decideNode } from "../builder/builder-actions";
import { JsonSchema } from "../builder/config-templates";
import { KindIcon } from "../kind-icon";
import {
  formatDuration,
  isExpenseApproval,
  isFinished,
  statusBadge,
} from "../workflow-labels";
import { cancelRun, decideApproval } from "../workflows-actions";

type StepState = WorkflowNodeRun["status"] | "pending";

const traceStatus = (
  state: StepState,
): "running" | "error" | "pending" | undefined => {
  switch (state) {
    case "running": {
      return "running";
    }

    case "failed": {
      return "error";
    }

    case "waiting":
    case "pending":
    case "skipped": {
      return "pending";
    }

    case "completed": {
      return undefined;
    }

    default: {
      const unknown: never = state;

      return unknown;
    }
  }
};

const lineStatus = (state: StepState) => {
  const status = traceStatus(state);

  return status === undefined ? {} : { status };
};

/** A node's recorded output as JSON; a value that is not JSON reads as null. */
const outputOf = (output: WorkflowNodeRun["output"]): JsonValue => {
  const parsed = v.safeParse(JsonSchema, output);

  return parsed.success ? parsed.output : null;
};

/** A node's stored value as indented JSON text. */
const json = (value: JsonValue): string => JSON.stringify(value, null, 2);

const hasKeys = (value: JsonObject): boolean => Object.keys(value).length > 0;

function StepItem({
  step,
  record,
  runFinished,
  canDecide,
  onDecide,
}: {
  step: RunStepNode;
  record: WorkflowNodeRun | undefined;
  runFinished: boolean;
  canDecide: boolean;
  onDecide: (node: string, approved: boolean) => void;
}) {
  const t = useExtracted("workflows");

  const state: StepState =
    record?.status ??
    (step.kind === "trigger" && runFinished ? "completed" : "pending");

  const took =
    record?.startedAt !== undefined && record.endedAt !== undefined
      ? record.endedAt.epochMilliseconds - record.startedAt.epochMilliseconds
      : null;

  const attempts = record?.attempts ?? 0;

  return (
    <TraceCollapsible data-testid={`run-step-${step.id}`} data-state={state}>
      <TraceCollapsibleTrigger>
        <TraceLine {...lineStatus(state)}>
          <TraceIcon>
            <KindIcon kind={step.kind} />
          </TraceIcon>
          <TraceTitle>{step.label}</TraceTitle>
          <TraceDescription>
            {[
              step.step ?? step.kind,
              state,
              attempts > 1 ? t("{n} attempts", { n: String(attempts) }) : null,
              took === null ? null : formatDuration(took),
            ]
              .filter((part) => part !== null)
              .join(" · ")}
          </TraceDescription>
        </TraceLine>
      </TraceCollapsibleTrigger>
      <TraceCollapsibleContent>
        <div className="flex flex-col gap-3 text-foreground">
          {hasKeys(step.config) ? (
            <CodeBlock size="sm">
              <CodeBlockHeader>
                <CodeBlockTitle>
                  {t("Input (the node's config)")}
                </CodeBlockTitle>
              </CodeBlockHeader>
              <CodeBlockContent wrap>{json(step.config)}</CodeBlockContent>
            </CodeBlock>
          ) : null}
          {record?.output === undefined || record.output === null ? null : (
            <CodeBlock size="sm">
              <CodeBlockHeader>
                <CodeBlockTitle>{t("Output")}</CodeBlockTitle>
              </CodeBlockHeader>
              <CodeBlockContent wrap>
                {json(outputOf(record.output))}
              </CodeBlockContent>
            </CodeBlock>
          )}
          {record?.error ? (
            <CodeBlock size="sm" variant="destructive">
              <CodeBlockHeader>
                <CodeBlockTitle>{t("Error")}</CodeBlockTitle>
              </CodeBlockHeader>
              <CodeBlockContent wrap>{record.error}</CodeBlockContent>
            </CodeBlock>
          ) : null}
          {record === undefined && step.kind !== "trigger" ? (
            <p className="text-sm text-muted-foreground">
              {runFinished
                ? t("The run did not reach this node.")
                : t("This node has not run yet.")}
            </p>
          ) : null}
          {step.kind === "approval" && state === "waiting" && canDecide ? (
            <div className="flex gap-2">
              <Button
                size="sm"
                onClick={() => {
                  onDecide(step.id, true);
                }}
              >
                <CheckIcon />
                {t("Approve")}
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => {
                  onDecide(step.id, false);
                }}
              >
                <XIcon />
                {t("Reject")}
              </Button>
            </div>
          ) : null}
        </div>
      </TraceCollapsibleContent>
    </TraceCollapsible>
  );
}

/**
 * One run: its facts and, for a graph run, the step trace with each node's
 * config, output, attempts and timing. The run and its node records update over
 * Realtime (`workflow-run:<id>`); `detail` is what the server read first.
 */
export function WorkflowRunDetail({ detail }: { detail: RunDetailData }) {
  const t = useExtracted("workflows");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const live = useWorkflowCanvasRun(detail.id, { schema: "api" });
  const { run } = live;

  const handlers = {
    onSuccess: () => {
      void live.refresh();
    },
    onError: (error: Parameters<typeof errorMessage>[0]) => {
      toast.error(errorMessage(error));
    },
  };

  const cancel = useAction(cancelRun, handlers);
  const decide = useAction(decideApproval, handlers);
  const decideStep = useAction(decideNode, handlers);

  const status = run?.status ?? detail.status;
  const error = run?.error ?? detail.error;
  const createdAt = run?.createdAt.epochMilliseconds ?? detail.createdAt;
  const startedAt = run?.startedAt?.epochMilliseconds ?? detail.startedAt;
  const completedAt = run?.completedAt?.epochMilliseconds ?? detail.completedAt;
  const finished = isFinished(status);

  const time = (epoch: number | null) =>
    epoch === null
      ? "–"
      : format.dateTime(new Date(epoch), {
          dateStyle: "medium",
          timeStyle: "medium",
        });

  const facts = [
    [t("Created"), time(createdAt)],
    [t("Started"), time(startedAt)],
    [t("Finished"), time(completedAt)],
    [
      t("Duration"),
      completedAt === null
        ? "–"
        : formatDuration(completedAt - (startedAt ?? createdAt)),
    ],
    [t("Mode"), detail.mode === "test" ? t("Test run") : t("Live run")],
    [
      t("Version"),
      detail.version === null
        ? "–"
        : t("v{version}", { version: String(detail.version) }),
    ],
  ] as const;

  const canCancel = !finished;

  return (
    <div className="flex flex-col gap-4">
      <Frame>
        <FramePanel>
          <FrameHeader>
            <FrameTitle className="flex items-center gap-2">
              {detail.name}
              <Badge variant={statusBadge(status)}>{status}</Badge>
              {detail.mode === "test" ? (
                <Badge variant="outline">{t("test")}</Badge>
              ) : null}
            </FrameTitle>
            <FrameDescription className="font-mono text-xs">
              {detail.externalId}
            </FrameDescription>
          </FrameHeader>
          <dl className="grid grid-cols-1 gap-x-8 gap-y-2 text-sm sm:grid-cols-2">
            {facts.map(([label, value]) => (
              <div key={label} className="flex justify-between gap-4">
                <dt className="text-muted-foreground">{label}</dt>
                <dd className="tabular-nums">{value}</dd>
              </div>
            ))}
          </dl>
          {error ? (
            <p className="mt-3 text-sm text-destructive" role="alert">
              {error}
            </p>
          ) : null}
          <div className="mt-4 flex flex-wrap gap-2">
            {detail.definitionId === null ? null : (
              <Link
                href={`/workflows/builder/${detail.definitionId}`}
                className="inline-flex h-8 items-center gap-1 text-sm text-primary hover:underline"
              >
                <PencilRulerIcon className="size-4" />
                {t("Open in the editor")}
              </Link>
            )}
            {finished || !isExpenseApproval(run?.definition ?? "") ? null : (
              <>
                <Button
                  size="sm"
                  disabled={decide.pending}
                  onClick={() => {
                    void decide.run({ run: detail.externalId, approved: true });
                  }}
                >
                  <CheckIcon />
                  {t("Approve")}
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={decide.pending}
                  onClick={() => {
                    void decide.run({
                      run: detail.externalId,
                      approved: false,
                    });
                  }}
                >
                  <XIcon />
                  {t("Reject")}
                </Button>
              </>
            )}
            {canCancel ? (
              <Button
                size="sm"
                variant="destructive"
                disabled={
                  cancel.pending || run?.cancelRequestedAt !== undefined
                }
                onClick={() => {
                  void cancel.run({ run: detail.id });
                }}
              >
                <CircleStopIcon />
                {t("Cancel run")}
              </Button>
            ) : null}
          </div>
        </FramePanel>
      </Frame>
      <Frame>
        <FramePanel>
          <FrameHeader>
            <FrameTitle>{t("Steps")}</FrameTitle>
            <FrameDescription>
              {detail.mode === "test"
                ? t(
                    "A test run returns each node's stub and keeps no step records, so the nodes stay pending.",
                  )
                : t(
                    "Each node of the version this run started on, with what it did.",
                  )}
            </FrameDescription>
          </FrameHeader>
          {detail.steps.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <WorkflowIcon />
                </EmptyMedia>
                <EmptyTitle>{t("No step records")}</EmptyTitle>
                <EmptyDescription>
                  {t("Only workflows drawn in the editor record each step.")}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <Trace data-testid="run-steps">
              {detail.steps.map((step) => (
                <StepItem
                  key={step.id}
                  step={step}
                  record={live.nodes[step.id]}
                  runFinished={finished}
                  canDecide={!finished}
                  onDecide={(node, approved) => {
                    void decideStep.run({ run: detail.id, node, approved });
                  }}
                />
              ))}
            </Trace>
          )}
        </FramePanel>
      </Frame>
    </div>
  );
}
