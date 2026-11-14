import type {
  SequenceStatus,
  SequenceStep,
} from "better-supabase/blocks/sequences";
import type { LucideIcon } from "lucide-react";

import {
  ClockIcon,
  ListChecksIcon,
  MailIcon,
  TriangleAlertIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";
import { refresh } from "next/cache";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getSequence } from "../sequences-queries";
import { AddStepDialog, SequenceStatusButton } from "./sequence-controls";

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
async function retry() {
  "use server";
  refresh();
}

// #region recipe:sequence-builder
const statusVariants = {
  draft: "secondary",
  active: "success-light",
  paused: "warning-light",
  archived: "outline",
} as const satisfies Record<SequenceStatus, string>;

const stepIcons = {
  email: MailIcon,
  wait: ClockIcon,
  task: ListChecksIcon,
} as const satisfies Record<SequenceStep["kind"], LucideIcon>;

/**
 * Render inside `<Suspense>`: one sequence with its steps, the contacts at each
 * stage and the buttons that add a step or start and pause it.
 */
export async function SequenceBuilder({ id }: { id: string }) {
  const [view, t, permissions] = await Promise.all([
    getSequence(id),
    getExtracted("sequences"),
    getPermissions(),
  ]);

  if (view.kind === "no-organization") {
    return null;
  }

  if (view.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The sequence didn't load")}</AlertTitle>
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

  const sequence = view.data;

  if (!sequence) {
    notFound();
  }

  const manage = can(permissions, "sequences.manage");

  const statusLabels: Record<SequenceStatus, string> = {
    draft: t("Draft"),
    active: t("Active"),
    paused: t("Paused"),
    archived: t("Archived"),
  };

  const stepLabel = (step: SequenceStep): string => {
    switch (step.kind) {
      case "email": {
        return step.subject;
      }

      case "wait": {
        return t("Wait {minutes} minutes", { minutes: String(step.minutes) });
      }

      case "task": {
        return step.title;
      }

      default: {
        const unknown: never = step;

        return unknown;
      }
    }
  };

  const counts = [
    { label: t("Active"), value: sequence.counts.active },
    { label: t("Completed"), value: sequence.counts.completed },
    { label: t("Replied"), value: sequence.counts.replied },
  ];

  return (
    <RecordDetailFrame
      title={sequence.name}
      description={t("{count, plural, one {# step} other {# steps}}", {
        count: sequence.steps.length,
      })}
      status={
        <Badge variant={statusVariants[sequence.status]}>
          {statusLabels[sequence.status]}
        </Badge>
      }
      actions={
        manage && sequence.status !== "archived" ? (
          <>
            <AddStepDialog sequenceId={sequence.id} />
            <SequenceStatusButton
              sequenceId={sequence.id}
              active={sequence.status === "active"}
            />
          </>
        ) : undefined
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Enrollments")}</CardTitle>
          </CardHeader>
          <CardContent>
            <dl className="grid gap-3">
              {counts.map((count) => (
                <div key={count.label} className="flex justify-between gap-2">
                  <dt className="text-sm text-muted-foreground">
                    {count.label}
                  </dt>
                  <dd className="text-sm font-medium tabular-nums">
                    {count.value}
                  </dd>
                </div>
              ))}
            </dl>
          </CardContent>
        </Card>
      }
    >
      <Card>
        <CardHeader>
          <CardTitle>{t("Steps")}</CardTitle>
        </CardHeader>
        <CardContent>
          {sequence.steps.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("No steps yet.")}
            </p>
          ) : (
            <ol className="flex flex-col gap-2">
              {sequence.steps.map((step, index) => {
                const Icon = stepIcons[step.kind];

                return (
                  <li key={step.id} className="flex items-center gap-2 text-sm">
                    <span className="w-5 text-xs text-muted-foreground tabular-nums">
                      {index + 1}
                    </span>
                    <Icon
                      aria-hidden
                      className="size-4 text-muted-foreground"
                    />
                    <span className="truncate">{stepLabel(step)}</span>
                  </li>
                );
              })}
            </ol>
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}
// #endregion recipe:sequence-builder

export function SequenceBuilderSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
