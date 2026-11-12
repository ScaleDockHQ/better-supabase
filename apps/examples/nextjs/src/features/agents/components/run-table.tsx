"use client";

import type { CellContext } from "@tanstack/react-table";

import { ActivityIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { OpsList } from "@/components/ops-list/ops-list";
import { Link } from "@/i18n/navigation";

import type { RunRow } from "../agents-queries";

import { RunStateBadge } from "./run-state-badge";

type RunCell = CellContext<ReadOnlyGridFeatures, RunRow>;

function StartedCell({ row }: RunCell) {
  const format = useFormatter();
  const { id, startedAt } = row.original;

  return (
    <Link
      href={`/assistant/agents/runs/${id}`}
      prefetch
      className="font-medium tabular-nums hover:underline"
    >
      {format.dateTime(new Date(startedAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </Link>
  );
}

function StatusCell({ row }: RunCell) {
  return <RunStateBadge status={row.original.status} />;
}

function ModelCell({ row }: RunCell) {
  return (
    <span className="text-muted-foreground">{row.original.model ?? "–"}</span>
  );
}

function DurationCell({ row }: RunCell) {
  const { seconds } = row.original;

  return (
    <span className="text-muted-foreground tabular-nums">
      {seconds === undefined ? "–" : `${seconds} s`}
    </span>
  );
}

function CostCell({ row }: RunCell) {
  const format = useFormatter();
  const { costMicroUsd } = row.original;

  return (
    <span className="text-muted-foreground tabular-nums">
      {costMicroUsd === undefined
        ? "–"
        : format.number(costMicroUsd / 1_000_000, {
            style: "currency",
            currency: "USD",
            maximumFractionDigits: 4,
          })}
    </span>
  );
}

/** The run queue: state filter, search, sort and keyset-style paging in the URL. */
export function RunTable({
  items,
  nextCursor,
}: {
  items: readonly RunRow[];
  nextCursor: string | null;
}) {
  const t = useExtracted("agents");

  const columns: RecordListColumns<RunRow> = [
    {
      accessorKey: "startedAt",
      header: t("Started"),
      size: 200,
      cell: StartedCell,
    },
    { accessorKey: "status", header: t("State"), size: 130, cell: StatusCell },
    { accessorKey: "model", header: t("Model"), size: 220, cell: ModelCell },
    {
      accessorKey: "seconds",
      header: t("Duration"),
      size: 100,
      cell: DurationCell,
    },
    {
      accessorKey: "costMicroUsd",
      header: t("Cost"),
      size: 110,
      cell: CostCell,
    },
  ];

  return (
    <OpsList
      rows={items}
      columns={columns}
      nextCursor={nextCursor}
      filter={{
        label: t("Every state"),
        options: [
          { value: "queued", label: t("Queued") },
          { value: "running", label: t("Running") },
          { value: "failed", label: t("Failed") },
          { value: "completed", label: t("Completed") },
          { value: "cancelled", label: t("Cancelled") },
        ],
      }}
      sorts={[
        { value: "newest", label: t("Newest first") },
        { value: "oldest", label: t("Oldest first") },
        { value: "cost", label: t("Highest cost") },
      ]}
      searchLabel={t("Search by model or id")}
      emptyIcon={<ActivityIcon />}
      emptyTitle={t("No runs found")}
      emptyDescription={t(
        "Runs appear after the first answer. Change the filters to see more.",
      )}
    />
  );
}
