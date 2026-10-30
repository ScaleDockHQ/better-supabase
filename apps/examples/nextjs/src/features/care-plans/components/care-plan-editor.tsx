// #region recipe:care-plan-editor
"use client";

import type {
  CarePlanActionKind,
  CarePlanActionStatus,
  CarePlanGoalStatus,
  CarePlanStatus,
} from "better-supabase/blocks/care-plans";

import { ClipboardPlusIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useRouter } from "next/navigation";
import { useTransition } from "react";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
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
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";

import type {
  CarePlanActionRow,
  CarePlanGoalRow,
  CarePlanProblemRow,
  CarePlanState,
  CarePlanView,
  Loaded,
} from "../care-plans-queries";

export function PlanStatusBadge({ status }: { status: CarePlanStatus }) {
  const t = useExtracted("care-plans");

  switch (status) {
    case "draft": {
      return <Badge variant="secondary">{t("Draft")}</Badge>;
    }

    case "active": {
      return <Badge variant="success-light">{t("Active")}</Badge>;
    }

    case "archived": {
      return <Badge variant="outline">{t("Archived")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

export function GoalStatusBadge({ status }: { status: CarePlanGoalStatus }) {
  const t = useExtracted("care-plans");

  switch (status) {
    case "planned": {
      return <Badge variant="secondary">{t("Planned")}</Badge>;
    }

    case "in_progress": {
      return <Badge variant="info-light">{t("In progress")}</Badge>;
    }

    case "achieved": {
      return <Badge variant="success-light">{t("Achieved")}</Badge>;
    }

    case "not_achieved": {
      return <Badge variant="warning-light">{t("Not achieved")}</Badge>;
    }

    case "canceled": {
      return <Badge variant="outline">{t("Canceled")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

function ActionKindLabel({ kind }: { kind: CarePlanActionKind }) {
  const t = useExtracted("care-plans");

  switch (kind) {
    case "intervention": {
      return t("Intervention");
    }

    case "appointment": {
      return t("Appointment");
    }

    case "task": {
      return t("Task");
    }

    case "measure": {
      return t("Restrictive measure");
    }

    default: {
      const unknown: never = kind;

      return unknown;
    }
  }
}

function ActionStatusBadge({
  status,
  requiresApproval,
}: {
  status: CarePlanActionStatus;
  requiresApproval: boolean;
}) {
  const t = useExtracted("care-plans");

  switch (status) {
    case "planned": {
      return requiresApproval ? (
        <Badge variant="warning-light">{t("Awaiting approval")}</Badge>
      ) : (
        <Badge variant="secondary">{t("Planned")}</Badge>
      );
    }

    case "active": {
      return <Badge variant="success-light">{t("Running")}</Badge>;
    }

    case "ended": {
      return <Badge variant="outline">{t("Ended")}</Badge>;
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

function ActionItem({ action }: { action: CarePlanActionRow }) {
  return (
    <li className="flex items-center justify-between gap-2 py-1.5">
      <div className="flex min-w-0 flex-col gap-0.5">
        <span className="truncate text-sm">{action.title}</span>
        <span className="text-xs text-muted-foreground">
          <ActionKindLabel kind={action.kind} />
          {action.teamRole === null ? null : ` · ${action.teamRole}`}
        </span>
      </div>
      <ActionStatusBadge
        status={action.status}
        requiresApproval={action.requiresApproval}
      />
    </li>
  );
}

function GoalItem({ goal }: { goal: CarePlanGoalRow }) {
  const t = useExtracted("care-plans");
  const format = useFormatter();

  return (
    <li className="flex flex-col gap-1 border-l pl-3">
      <div className="flex items-center justify-between gap-2">
        <div className="flex min-w-0 flex-col gap-0.5">
          <span className="truncate text-sm font-medium">{goal.title}</span>
          {goal.targetOn === null ? null : (
            <span className="text-xs text-muted-foreground tabular-nums">
              {t("Target {date}", {
                date: format.dateTime(new Date(goal.targetOn), {
                  dateStyle: "medium",
                  timeZone: "UTC",
                }),
              })}
            </span>
          )}
        </div>
        <GoalStatusBadge status={goal.status} />
      </div>
      {goal.actions.length === 0 ? (
        <span className="text-xs text-muted-foreground">
          {t("No actions toward this goal yet.")}
        </span>
      ) : (
        <ul className="flex flex-col divide-y">
          {goal.actions.map((action) => (
            <ActionItem key={action.id} action={action} />
          ))}
        </ul>
      )}
    </li>
  );
}

function ProblemItem({ problem }: { problem: CarePlanProblemRow }) {
  const t = useExtracted("care-plans");

  return (
    <li className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        <div className="flex min-w-0 flex-col gap-0.5">
          <span className="truncate font-medium tracking-tight">
            {problem.title}
          </span>
          {problem.code === null ? null : (
            <span className="font-mono text-xs text-muted-foreground">
              {problem.code}
            </span>
          )}
        </div>
        {problem.status === "resolved" ? (
          <Badge variant="success-light">{t("Resolved")}</Badge>
        ) : (
          <Badge variant="info-light">{t("Active")}</Badge>
        )}
      </div>
      <ul className="flex flex-col gap-3">
        {problem.goals.map((goal) => (
          <GoalItem key={goal.id} goal={goal} />
        ))}
      </ul>
    </li>
  );
}

function PlanTree({ plan }: { plan: CarePlanView }) {
  return (
    <ul className="flex flex-col gap-6">
      {plan.problems.map((problem) => (
        <ProblemItem key={problem.id} problem={problem} />
      ))}
    </ul>
  );
}

function PlanHeader({ plan }: { plan: CarePlanView }) {
  const t = useExtracted("care-plans");
  const format = useFormatter();

  return (
    <FrameHeader className="gap-0.5">
      <div className="flex items-center gap-2">
        <FrameTitle>{plan.title}</FrameTitle>
        <PlanStatusBadge status={plan.status} />
      </div>
      <FrameDescription>
        {plan.reviewOn === null
          ? t("{client}, version {version, number}", {
              client: plan.clientName,
              version: plan.version,
            })
          : t("{client}, version {version, number}, review on {date}", {
              client: plan.clientName,
              version: plan.version,
              date: format.dateTime(new Date(plan.reviewOn), {
                dateStyle: "medium",
                timeZone: "UTC",
              }),
            })}
      </FrameDescription>
    </FrameHeader>
  );
}

/**
 * A client's care plan as a tree: each problem with its code, the goals that
 * answer it and the actions toward each goal, with their status.
 */
export function CarePlanEditor({ state }: { state: Loaded<CarePlanState> }) {
  const t = useExtracted("care-plans");
  const router = useRouter();
  const [retrying, startRetry] = useTransition();

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "ok" && "problems" in state.data) {
    return (
      <Frame spacing="sm" data-recipe="care-plan-editor">
        <PlanHeader plan={state.data} />
        <FramePanel>
          <PlanTree plan={state.data} />
        </FramePanel>
      </Frame>
    );
  }

  return (
    <Frame spacing="sm" data-recipe="care-plan-editor">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{t("Care plan")}</FrameTitle>
        <FrameDescription>
          {t(
            "The client's problems, the goals that answer them and the actions toward each goal.",
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel>
        {state.kind === "error" ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The care plan didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <Button
                size="sm"
                variant="outline"
                type="button"
                disabled={retrying}
                onClick={() => {
                  startRetry(() => {
                    router.refresh();
                  });
                }}
              >
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        ) : (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ClipboardPlusIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No care plan yet")}</EmptyTitle>
              <EmptyDescription>
                {state.data.clientName === null
                  ? t("Add a customer, then draft a care plan for them.")
                  : t(
                      "Draft a plan for {client} with a problem, a goal and an action, then publish it.",
                      { client: state.data.clientName },
                    )}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <a
                className="text-sm underline underline-offset-4"
                href="https://bettersupabase.com/docs/blocks/care-plans"
              >
                {t("Read the care plans guide")}
              </a>
            </EmptyContent>
          </Empty>
        )}
      </FramePanel>
    </Frame>
  );
}

export function CarePlanEditorSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-40" />
        <Skeleton className="h-4 w-72" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-56" />
      </FramePanel>
    </Frame>
  );
}
// #endregion recipe:care-plan-editor
