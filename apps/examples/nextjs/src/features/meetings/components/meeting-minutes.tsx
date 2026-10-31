"use client";

import { useAction } from "better-supabase/react";
import {
  ListChecksIcon,
  MousePointerClickIcon,
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
import { useErrorMessage } from "@/lib/use-error-message";

import type { Loaded, MeetingMinutesView } from "../meetings-queries";

import { holdMeeting, settleDecision, startMeeting } from "../meetings-actions";
import { DecisionStatusBadge, MeetingStatusBadge } from "./meeting-labels";

export function MeetingMinutesPicker() {
  const t = useExtracted("meetings");

  return (
    <Frame spacing="sm">
      <FramePanel>
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <MousePointerClickIcon />
            </EmptyMedia>
            <EmptyTitle>{t("Pick a meeting")}</EmptyTitle>
            <EmptyDescription>
              {t("Open a meeting in the list to see its agenda and decisions.")}
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      </FramePanel>
    </Frame>
  );
}

// #region recipe:meeting-minutes
/**
 * One meeting with the minutes of each agenda item, its decisions with the
 * votes so far, and the tasks it opened. The chair starts and holds the meeting
 * and settles a decision from the votes; the database checks the caller's role
 * again when it runs.
 */
export function MeetingMinutes({
  state,
  canRun,
}: {
  state: Loaded<MeetingMinutesView>;
  canRun: boolean;
}) {
  const t = useExtracted("meetings");
  const router = useRouter();
  const [retrying, startRetry] = useTransition();
  const errorMessage = useErrorMessage();

  const start = useAction(startMeeting, {
    onSuccess: () => {
      toast.success(t("Meeting started"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const hold = useAction(holdMeeting, {
    onSuccess: () => {
      toast.success(t("Meeting held"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const settle = useAction(settleDecision, {
    onSuccess: () => {
      toast.success(t("Decision settled"));
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
            <AlertTitle>{t("The meeting didn't load")}</AlertTitle>
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

  const meeting = state.data;

  return (
    <Frame spacing="sm" data-recipe="meeting-minutes">
      <FrameHeader className="gap-0.5">
        <FrameTitle>{meeting.title}</FrameTitle>
        <FrameDescription>
          {t(
            "{count, plural, =0 {No attendees yet} one {# attendee} other {# attendees}}",
            { count: meeting.attendees.length },
          )}
        </FrameDescription>
      </FrameHeader>
      <FramePanel className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-2">
          <MeetingStatusBadge status={meeting.status} />
        </div>
        {meeting.agenda.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <ListChecksIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No agenda yet")}</EmptyTitle>
              <EmptyDescription>
                {t("The chair adds the agenda items before the meeting.")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ol className="flex flex-col gap-3">
            {meeting.agenda.map((item) => (
              <li key={item.id} className="flex flex-col gap-1 text-sm">
                <span className="flex items-center gap-2 font-medium">
                  <span className="font-mono text-xs text-muted-foreground tabular-nums">
                    {item.ordinal}
                  </span>
                  {item.title}
                </span>
                {item.minutes === null ? null : (
                  <p className="text-muted-foreground">{item.minutes}</p>
                )}
                {item.outcome === null ? null : (
                  <Badge variant="outline">{item.outcome}</Badge>
                )}
              </li>
            ))}
          </ol>
        )}
        {meeting.decisions.length === 0 ? null : (
          <ul className="flex flex-col gap-2">
            {meeting.decisions.map((decision) => (
              <li
                key={decision.id}
                className="flex items-center justify-between gap-2 text-sm"
              >
                <span className="flex items-center gap-2">
                  <DecisionStatusBadge status={decision.status} />
                  {decision.title}
                  <span className="text-xs text-muted-foreground tabular-nums">
                    {t("{up} for, {down} against", {
                      up: String(decision.up),
                      down: String(decision.down),
                    })}
                  </span>
                </span>
                {decision.status === "proposed" && canRun ? (
                  <Button
                    type="button"
                    size="sm"
                    variant="outline"
                    disabled={settle.pending}
                    onClick={() => {
                      void settle.run({ decisionId: decision.id });
                    }}
                  >
                    {t("Settle from votes")}
                  </Button>
                ) : null}
              </li>
            ))}
          </ul>
        )}
        {meeting.actionItems.length === 0 ? null : (
          <ul className="flex flex-col gap-1 text-sm">
            {meeting.actionItems.map((item) => (
              <li key={item.workItemId} className="flex items-center gap-2">
                <Badge variant="secondary">{item.state}</Badge>
                {item.title}
              </li>
            ))}
          </ul>
        )}
      </FramePanel>
      {canRun &&
      (meeting.status === "planned" || meeting.status === "in_progress") ? (
        <FrameFooter>
          {meeting.status === "planned" ? (
            <Button
              type="button"
              size="sm"
              disabled={start.pending}
              onClick={() => {
                void start.run({ meetingId: meeting.id });
              }}
            >
              {t("Start meeting")}
            </Button>
          ) : (
            <Button
              type="button"
              size="sm"
              disabled={hold.pending}
              onClick={() => {
                void hold.run({ meetingId: meeting.id });
              }}
            >
              {t("Hold meeting")}
            </Button>
          )}
        </FrameFooter>
      ) : null}
    </Frame>
  );
}
// #endregion recipe:meeting-minutes

export function MeetingMinutesSkeleton() {
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
