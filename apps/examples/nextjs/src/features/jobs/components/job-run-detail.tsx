import { getExtracted, getFormatter } from "next-intl/server";
import { forbidden, notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Badge } from "@/components/reui/badge";
import { Skeleton } from "@/components/ui/skeleton";

import { getJobRunDetail } from "../jobs-run-reads";
import { RetryJobButton } from "./job-run-controls";

/** Render inside `<Suspense>`; the fallback is `JobRunDetailSkeleton`. */
export async function JobRunDetail({
  queue,
  id,
}: {
  queue: string;
  id: number;
}) {
  const [run, t, format] = await Promise.all([
    getJobRunDetail(queue, id),
    getExtracted("jobs"),
    getFormatter(),
  ]);

  if (!Number.isInteger(id)) {
    notFound();
  }

  if (!run) {
    forbidden();
  }

  const when = (iso: string | null) =>
    iso
      ? format.dateTime(new Date(iso), {
          dateStyle: "medium",
          timeStyle: "medium",
        })
      : "–";

  return (
    <RecordDetailFrame
      title={`${run.queue} #${String(run.messageId)}`}
      description={t("Queued {when}", { when: when(run.enqueuedAt) })}
      status={<Badge variant="secondary">{run.status}</Badge>}
      actions={
        run.status === "dead" ? (
          <RetryJobButton queue={run.queue} id={run.messageId} />
        ) : undefined
      }
    >
      <dl className="grid gap-4 text-sm sm:grid-cols-3">
        <div className="flex flex-col gap-1">
          <dt className="text-xs text-muted-foreground">{t("Attempts")}</dt>
          <dd className="tabular-nums">{run.attempts}</dd>
        </div>
        <div className="flex flex-col gap-1">
          <dt className="text-xs text-muted-foreground">{t("Finished")}</dt>
          <dd>{when(run.finishedAt)}</dd>
        </div>
        <div className="flex flex-col gap-1">
          <dt className="text-xs text-muted-foreground">{t("Last error")}</dt>
          <dd>{run.lastError ?? "–"}</dd>
        </div>
      </dl>
      <div className="flex flex-col gap-2">
        <h2 className="text-sm font-medium">{t("Message")}</h2>
        <pre className="max-h-96 overflow-auto rounded-xl border p-3 text-xs">
          {JSON.stringify(run.payload, null, 2)}
        </pre>
      </div>
    </RecordDetailFrame>
  );
}

export function JobRunDetailSkeleton() {
  return <Skeleton className="h-64 rounded-xl" aria-busy="true" />;
}
