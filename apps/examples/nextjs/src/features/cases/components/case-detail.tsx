"use client";

import { useAction } from "better-supabase/react";
import { CircleCheckIcon, CircleDotIcon, ListChecksIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
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
import { useErrorMessage } from "@/lib/use-error-message";

import type { CaseDetailView } from "../cases-queries";

import { closeCase } from "../cases-actions";
import {
  severityVariant,
  useActionTypeLabel,
  useBlockerLabel,
  useSeverityLabel,
} from "./case-labels";

// #region recipe:case-detail
/**
 * One case with what still stops it from closing and its actions. Close is
 * enabled once nothing blocks it; the database checks again when it runs.
 */
export function CaseDetail({
  detail,
  canClose,
}: {
  detail: CaseDetailView;
  canClose: boolean;
}) {
  const t = useExtracted("cases");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const blocker = useBlockerLabel();
  const actionType = useActionTypeLabel();
  const severity = useSeverityLabel();

  const close = useAction(closeCase, {
    onSuccess: ({ number }) => {
      toast.success(t("Closed {number}", { number }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const open = detail.status === "open";

  return (
    <Frame spacing="sm" data-recipe="case-detail">
      <FrameHeader className="gap-0.5">
        <FrameTitle>
          {t("{number}: {title}", {
            number: detail.number,
            title: detail.title,
          })}
        </FrameTitle>
        <FrameDescription>
          {detail.stage === null
            ? detail.kind
            : t("{kind} in {stage}", {
                kind: detail.kind,
                stage: detail.stage,
              })}
        </FrameDescription>
      </FrameHeader>
      <FramePanel className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-2">
          {detail.severity === null ? null : (
            <Badge variant={severityVariant(detail.severity)}>
              {severity(detail.severity)}
            </Badge>
          )}
          {detail.effectivenessDueOn === null ? null : (
            <Badge variant="info-light">
              {t("Effectiveness check due {date}", {
                date: format.dateTime(new Date(detail.effectivenessDueOn), {
                  dateStyle: "medium",
                  timeZone: "UTC",
                }),
              })}
            </Badge>
          )}
        </div>
        <p className="text-sm">
          {detail.rootCause ?? (
            <span className="text-muted-foreground">
              {t("No root cause recorded yet.")}
            </span>
          )}
        </p>
        {open && detail.blockers.length > 0 ? (
          <Alert variant="warning">
            <CircleDotIcon />
            <AlertTitle>{t("Before this case can close")}</AlertTitle>
            <AlertDescription>
              <ul className="flex list-disc flex-col gap-1 pl-4">
                {detail.blockers.map((code) => (
                  <li key={code}>{blocker(code)}</li>
                ))}
              </ul>
            </AlertDescription>
          </Alert>
        ) : open ? (
          <Alert variant="success">
            <CircleCheckIcon />
            <AlertTitle>{t("Nothing blocks closing this case")}</AlertTitle>
          </Alert>
        ) : null}
        {detail.actions.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ListChecksIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No actions yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Containment and corrective actions are tasks; add them from the case's work items.",
                )}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ul className="flex flex-col gap-2">
            {detail.actions.map((action) => (
              <li
                key={action.id}
                className="flex items-center justify-between gap-2 text-sm"
              >
                <span className="flex items-center gap-2">
                  <Badge variant="outline">{actionType(action.type)}</Badge>
                  {action.title}
                </span>
                {action.done ? (
                  <Badge variant="success-light">{t("Done")}</Badge>
                ) : (
                  <Badge variant="secondary">
                    {action.required ? t("Open, required") : t("Open")}
                  </Badge>
                )}
              </li>
            ))}
          </ul>
        )}
      </FramePanel>
      {open && canClose ? (
        <FrameFooter>
          <Button
            type="button"
            size="sm"
            disabled={detail.blockers.length > 0 || close.pending}
            onClick={() => {
              void close.run({ caseId: detail.id });
            }}
          >
            {t("Close case")}
          </Button>
        </FrameFooter>
      ) : null}
    </Frame>
  );
}
// #endregion recipe:case-detail
