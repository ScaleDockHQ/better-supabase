import type {
  SequenceStatus,
  SequenceStep,
} from "better-supabase/blocks/sequences";
import type { LucideIcon } from "lucide-react";

import {
  ClockIcon,
  ListChecksIcon,
  MailIcon,
  SendIcon,
  TriangleAlertIcon,
} from "lucide-react";
import { getExtracted } from "next-intl/server";
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
  CardAction,
  CardContent,
  CardFooter,
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
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getSequences } from "../sequences-queries";
import {
  AddStepDialog,
  SampleSequenceButton,
  SequenceStatusButton,
} from "./sequence-controls";

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

/** Render inside `<Suspense>`: the organization's sequences and their steps. */
export async function SequenceBuilder() {
  const [view, t, permissions] = await Promise.all([
    getSequences(),
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
        <AlertTitle>{t("The sequences didn't load")}</AlertTitle>
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

  const manage = can(permissions, "sequences.manage");

  if (view.data.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <SendIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No sequences yet")}</EmptyTitle>
          <EmptyDescription>
            {manage
              ? t(
                  "Create a sample sequence, then activate it to enroll contacts.",
                )
              : t(
                  "An admin sets up the sequences your team enrolls contacts in.",
                )}
          </EmptyDescription>
        </EmptyHeader>
        {manage ? (
          <EmptyContent>
            <SampleSequenceButton />
          </EmptyContent>
        ) : null}
      </Empty>
    );
  }

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

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {view.data.map((sequence) => (
        <Card key={sequence.id}>
          <CardHeader>
            <div className="flex items-center gap-2">
              <CardTitle>{sequence.name}</CardTitle>
              <Badge variant={statusVariants[sequence.status]}>
                {statusLabels[sequence.status]}
              </Badge>
            </div>
            {manage && sequence.status !== "archived" ? (
              <CardAction className="flex gap-2">
                <AddStepDialog sequenceId={sequence.id} />
                <SequenceStatusButton
                  sequenceId={sequence.id}
                  active={sequence.status === "active"}
                />
              </CardAction>
            ) : null}
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
                    <li
                      key={step.id}
                      className="flex items-center gap-2 text-sm"
                    >
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
          <CardFooter className="gap-4 text-xs text-muted-foreground tabular-nums">
            <span>
              {t("{count} active", { count: String(sequence.counts.active) })}
            </span>
            <span>
              {t("{count} completed", {
                count: String(sequence.counts.completed),
              })}
            </span>
            <span>
              {t("{count} replied", { count: String(sequence.counts.replied) })}
            </span>
          </CardFooter>
        </Card>
      ))}
    </div>
  );
}
// #endregion recipe:sequence-builder

export function SequenceBuilderSkeleton() {
  return <Skeleton className="h-48 rounded-xl" aria-busy="true" />;
}
