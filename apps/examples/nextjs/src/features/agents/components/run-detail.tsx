import {
  CheckIcon,
  CircleAlertIcon,
  CircleDashedIcon,
  LoaderCircleIcon,
} from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Trace,
  TraceDescription,
  TraceIcon,
  TraceLine,
  TraceTitle,
} from "@/components/ui/trace";
import { Link } from "@/i18n/navigation";

import { getRun } from "../agents-queries";
import { CancelRunButton } from "./cancel-run-button";
import { RunStateBadge } from "./run-state-badge";

/** Render inside `<Suspense>`: reads the `id` param, the run and its steps. */
export async function RunDetail({ id }: { id: string }) {
  const [detail, t, format] = await Promise.all([
    getRun(id),
    getExtracted("agents"),
    getFormatter(),
  ]);

  if (detail === undefined) {
    notFound();
  }

  const { run, steps, chatTitle } = detail;
  const active = run.status === "queued" || run.status === "running";

  return (
    <RecordDetailFrame
      title={t("Run {id}", { id: run.id.slice(0, 8) })}
      description={format.dateTime(new Date(run.startedAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
      status={<RunStateBadge status={run.status} />}
      actions={
        <>
          <Link
            href={`/assistant/${run.chatId}`}
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {chatTitle === "" ? t("Open the chat") : chatTitle}
          </Link>
          {active ? <CancelRunButton chatId={run.chatId} /> : null}
        </>
      }
      aside={
        <Card size="sm">
          <CardHeader>
            <CardTitle>{t("Details")}</CardTitle>
            <CardDescription>{t("What the run used.")}</CardDescription>
          </CardHeader>
          <CardContent>
            <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              <dt className="text-muted-foreground">{t("Engine")}</dt>
              <dd>{run.engine}</dd>
              <dt className="text-muted-foreground">{t("Model")}</dt>
              <dd className="break-all">{run.model ?? "–"}</dd>
              <dt className="text-muted-foreground">{t("Duration")}</dt>
              <dd className="tabular-nums">
                {run.seconds === undefined ? "–" : `${run.seconds} s`}
              </dd>
              <dt className="text-muted-foreground">{t("Usage")}</dt>
              <dd className="font-mono text-xs break-all">{run.usage}</dd>
            </dl>
          </CardContent>
        </Card>
      }
    >
      {run.error === undefined ? null : (
        <Alert variant="destructive">
          <CircleAlertIcon />
          <AlertTitle>{t("The run failed")}</AlertTitle>
          <AlertDescription>{run.error}</AlertDescription>
        </Alert>
      )}
      <Card>
        <CardHeader>
          <CardTitle>{t("Steps")}</CardTitle>
          <CardDescription>
            {t("Each step a durable run recorded, in order.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {steps.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("This run recorded no steps. Only durable runs do.")}
            </p>
          ) : (
            <Trace>
              {steps.map((step) => (
                <TraceLine
                  key={step.key}
                  {...(step.status === "error"
                    ? { status: "error" as const }
                    : step.status === "running"
                      ? { status: "running" as const }
                      : {})}
                >
                  <TraceIcon>
                    {step.status === "error" ? (
                      <CircleAlertIcon />
                    ) : step.status === "running" ? (
                      <LoaderCircleIcon className="animate-spin motion-reduce:animate-none" />
                    ) : step.status === "done" ? (
                      <CheckIcon />
                    ) : (
                      <CircleDashedIcon />
                    )}
                  </TraceIcon>
                  <TraceTitle>{step.label}</TraceTitle>
                  <TraceDescription>
                    {step.seconds === undefined ? "" : `${step.seconds} s`}
                  </TraceDescription>
                </TraceLine>
              ))}
            </Trace>
          )}
        </CardContent>
      </Card>
    </RecordDetailFrame>
  );
}

export function RunDetailSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-4 lg:col-span-2">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-56 w-full" />
      </div>
      <Skeleton className="h-40 w-full" />
    </div>
  );
}
