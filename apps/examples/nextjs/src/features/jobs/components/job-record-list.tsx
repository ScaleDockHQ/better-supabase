"use client";

import type { CellContext } from "@tanstack/react-table";

import { ListChecksIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { Badge } from "@/components/reui/badge";
import { AdminRecordList } from "@/features/admin-lists/admin-record-list";
import { Link } from "@/i18n/navigation";

import type { JobRow } from "../jobs-list";

import { jobList } from "../jobs-list";
import { EnqueueTestJobButton } from "./job-run-controls";

type JobCell = CellContext<ReadOnlyGridFeatures, JobRow>;

type BadgeVariant =
  | "info-light"
  | "secondary"
  | "primary-light"
  | "warning-light"
  | "success-light"
  | "destructive-light";

const variants = new Map<string, BadgeVariant>([
  ["queued", "info-light"],
  ["scheduled", "secondary"],
  ["running", "primary-light"],
  ["retrying", "warning-light"],
  ["succeeded", "success-light"],
  ["dead", "destructive-light"],
]);

function useStatusLabel(): (status: string) => string {
  const t = useExtracted("jobs");

  return (status) => {
    switch (status) {
      case "queued": {
        return t("Queued");
      }

      case "scheduled": {
        return t("Scheduled");
      }

      case "running": {
        return t("Running");
      }

      case "retrying": {
        return t("Retrying");
      }

      case "succeeded": {
        return t("Succeeded");
      }

      case "dead": {
        return t("Failed");
      }

      default: {
        return status;
      }
    }
  };
}

function JobCellLink({ row }: JobCell) {
  const { queue, messageId, lastError } = row.original;

  return (
    <div className="flex flex-col gap-1">
      <Link
        href={`/settings/jobs/runs/${queue}/${String(messageId)}`}
        prefetch
        className="font-mono text-sm hover:underline"
      >
        {queue}
      </Link>
      <span className="max-w-xs truncate text-xs text-muted-foreground">
        {lastError ?? `#${String(messageId)}`}
      </span>
    </div>
  );
}

function StatusCell({ row }: JobCell) {
  const label = useStatusLabel();
  const { status } = row.original;

  return (
    <Badge variant={variants.get(status) ?? "secondary"}>{label(status)}</Badge>
  );
}

function WhenCell({ value }: { value: string | null }) {
  const format = useFormatter();

  return (
    <span className="text-xs text-muted-foreground">
      {value
        ? format.dateTime(new Date(value), {
            dateStyle: "medium",
            timeStyle: "short",
          })
        : "–"}
    </span>
  );
}

function EnqueuedCell({ row }: JobCell) {
  return <WhenCell value={row.original.enqueuedAt} />;
}

function FinishedCell({ row }: JobCell) {
  return <WhenCell value={row.original.finishedAt} />;
}

/** The job runs overview on the list kit. */
export function JobRecordList({
  initial,
}: {
  initial: RecordListPage<JobRow>;
}) {
  const t = useExtracted("jobs");
  const statusLabel = useStatusLabel();

  const columns: RecordListColumns<JobRow> = [
    { id: "job", header: t("Job"), size: 280, cell: JobCellLink },
    { accessorKey: "status", header: t("Status"), size: 120, cell: StatusCell },
    { accessorKey: "attempts", header: t("Attempts"), size: 100 },
    { id: "enqueued", header: t("Queued"), size: 170, cell: EnqueuedCell },
    { id: "finished", header: t("Finished"), size: 170, cell: FinishedCell },
  ];

  return (
    <AdminRecordList
      list={jobList}
      endpoint="/api/jobs/list"
      initial={initial}
      columns={columns}
      facets={[
        { key: "status", label: t("Status"), valueLabel: statusLabel },
        { key: "queue", label: t("Queue"), valueLabel: (value) => value },
      ]}
      searchLabel={t("Search jobs")}
      emptyIcon={<ListChecksIcon />}
      emptyTitle={t("No job runs found")}
      emptyDescription={t(
        "Jobs are queued when the app hands work to the background. Queue a test job, or change the filters.",
      )}
      emptyAction={<EnqueueTestJobButton variant="outline" />}
    />
  );
}
