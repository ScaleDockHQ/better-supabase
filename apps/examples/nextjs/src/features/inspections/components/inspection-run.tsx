"use client";

import { useAction } from "better-supabase/react";
import {
  CircleCheckIcon,
  CircleDotIcon,
  SearchCheckIcon,
  TriangleAlertIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { useTransition } from "react";
import { toast } from "sonner";

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
  FrameFooter,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import type { InspectionRunView, Loaded } from "../inspections-queries";

import { closeInspection, raiseFindingCase } from "../inspections-actions";
import {
  InspectionStatusBadge,
  useFindingTypeLabel,
  useKindLabel,
  useRoleLabel,
} from "./inspection-labels";

// #region recipe:inspection-run
/**
 * One inspection with its team, checklist and findings. A finding that needs a
 * case gets a Raise case button, and Close is enabled once each one has its
 * case; the database checks again when it runs.
 */
export function InspectionRun({
  state,
  canWork,
}: {
  state: Loaded<InspectionRunView>;
  canWork: boolean;
}) {
  const t = useExtracted("inspections");
  const router = useRouter();
  const [retrying, startRetry] = useTransition();
  const errorMessage = useErrorMessage();
  const kind = useKindLabel();
  const findingType = useFindingTypeLabel();
  const role = useRoleLabel();

  const raise = useAction(raiseFindingCase, {
    onSuccess: () => {
      toast.success(t("Case raised"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const close = useAction(closeInspection, {
    onSuccess: ({ number }) => {
      toast.success(t("Closed {number}", { number }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  if (state.kind === "no-organization") {
    return null;
  }

  if (state.kind === "error") {
    return (
      <Frame spacing="sm">
        <FramePanel>
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The inspection didn't load")}</AlertTitle>
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
        </FramePanel>
      </Frame>
    );
  }

  const run = state.data;

  const waiting = run.findings.filter(
    (finding) => finding.needsCase && finding.caseId === null,
  ).length;

  const working = run.status === "in_progress" || run.status === "reporting";

  return (
    <Frame spacing="sm" data-recipe="inspection-run">
      <FrameHeader className="gap-0.5">
        <FrameTitle>
          {t("{number}: {title}", { number: run.number, title: run.title })}
        </FrameTitle>
        <FrameDescription>{kind(run.kind)}</FrameDescription>
      </FrameHeader>
      <FramePanel className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-2">
          <InspectionStatusBadge status={run.status} />
          {run.checklist === null ? null : run.checklist === "submitted" ? (
            <Badge variant="success-light">{t("Checklist submitted")}</Badge>
          ) : (
            <Badge variant="warning-light">{t("Checklist in draft")}</Badge>
          )}
          <span className="text-xs text-muted-foreground">
            {t(
              "{count, plural, =0 {No team yet} one {# team member} other {# team members}}",
              { count: run.team.length },
            )}
            {run.team.length === 0
              ? ""
              : ` (${run.team.map((member) => role(member.role)).join(", ")})`}
          </span>
        </div>
        {working && waiting > 0 ? (
          <Alert variant="warning">
            <CircleDotIcon />
            <AlertTitle>
              {t(
                "{count, plural, one {# finding needs a case} other {# findings need a case}} before this inspection can close",
                { count: waiting },
              )}
            </AlertTitle>
          </Alert>
        ) : run.status === "reporting" ? (
          <Alert variant="success">
            <CircleCheckIcon />
            <AlertTitle>{t("Every nonconformity has its case")}</AlertTitle>
          </Alert>
        ) : null}
        {run.findings.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <SearchCheckIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No findings yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "The lead and auditors record findings while the inspection is in progress.",
                )}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ul className="flex flex-col gap-2">
            {run.findings.map((finding) => (
              <li
                key={finding.id}
                className="flex items-center justify-between gap-2 text-sm"
              >
                <span className="flex items-center gap-2">
                  <span className="font-mono text-xs text-muted-foreground tabular-nums">
                    {finding.number}
                  </span>
                  <Badge
                    variant={
                      finding.needsCase ? "destructive-light" : "outline"
                    }
                  >
                    {findingType(finding.type)}
                  </Badge>
                  {finding.title}
                  {finding.clause === null ? null : (
                    <span className="text-xs text-muted-foreground">
                      {finding.clause}
                    </span>
                  )}
                </span>
                {finding.caseId === null ? (
                  finding.needsCase && working && canWork ? (
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      disabled={raise.pending}
                      onClick={() => {
                        void raise.run({ findingId: finding.id });
                      }}
                    >
                      {t("Raise case")}
                    </Button>
                  ) : null
                ) : (
                  <Link
                    href={`/cases?case=${finding.caseId}`}
                    className="text-sm underline-offset-4 transition-colors hover:underline"
                  >
                    {t("Open case")}
                  </Link>
                )}
              </li>
            ))}
          </ul>
        )}
      </FramePanel>
      {run.status === "reporting" && canWork ? (
        <FrameFooter>
          <Button
            type="button"
            size="sm"
            disabled={waiting > 0 || close.pending}
            onClick={() => {
              void close.run({ inspectionId: run.id });
            }}
          >
            {t("Close inspection")}
          </Button>
        </FrameFooter>
      ) : null}
    </Frame>
  );
}
// #endregion recipe:inspection-run

export function InspectionRunSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-48" />
        <Skeleton className="h-4 w-32" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-32" />
      </FramePanel>
    </Frame>
  );
}
