"use client";

import { useAction } from "better-supabase/react";
import { RotateCwIcon, SparklesIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Alert, AlertAction, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { useErrorMessage } from "@/lib/use-error-message";

import { summarizeThread } from "../chat-actions";

/**
 * A thread's summary for someone who missed it, written on request and saved,
 * so the next reader gets it without a model call until the thread changes.
 */
export function ThreadSummary({ threadId }: { threadId: string }) {
  const t = useExtracted("chat");
  const errorMessage = useErrorMessage();
  const summarize = useAction(summarizeThread);
  const summary = summarize.data;

  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>{t("Summary")}</CardTitle>
        {summary ? (
          <CardAction>
            <Button
              type="button"
              size="icon-sm"
              variant="ghost"
              aria-label={t("Summarize again")}
              disabled={summarize.pending}
              onClick={() => void summarize.run({ threadId, force: true })}
            >
              <RotateCwIcon aria-hidden />
            </Button>
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {summarize.error ? (
          <Alert variant="destructive" aria-live="polite">
            <AlertTitle>{errorMessage(summarize.error)}</AlertTitle>
            <AlertAction>
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => void summarize.run({ threadId })}
              >
                <RotateCwIcon aria-hidden />
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        ) : null}
        {summarize.pending ? (
          <div
            className="flex flex-col gap-2"
            aria-busy="true"
            aria-live="polite"
          >
            <span className="sr-only">{t("Summarizing the thread")}</span>
            <Skeleton className="h-4" />
            <Skeleton className="h-4 w-2/3" />
          </div>
        ) : summary ? (
          <div className="flex flex-col gap-2">
            <p className="text-sm">{summary.summary}</p>
            <div className="flex items-center gap-2">
              <span className="text-xs text-muted-foreground tabular-nums">
                {t("{count, plural, one {# message} other {# messages}}", {
                  count: summary.messageCount,
                })}
              </span>
              {summary.stale ? (
                <Badge variant="warning-light">{t("Out of date")}</Badge>
              ) : null}
            </div>
          </div>
        ) : summarize.error ? null : (
          <Empty>
            <EmptyHeader>
              <EmptyDescription>
                {t("Catch up on this thread without reading every reply.")}
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => void summarize.run({ threadId })}
              >
                <SparklesIcon aria-hidden />
                {t("Summarize")}
              </Button>
            </EmptyContent>
          </Empty>
        )}
      </CardContent>
    </Card>
  );
}
