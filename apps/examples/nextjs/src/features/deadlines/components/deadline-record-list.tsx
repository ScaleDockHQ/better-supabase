"use client";

import type { CellContext } from "@tanstack/react-table";

import { useAction } from "better-supabase/react";
import { HourglassIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { DeadlineRow } from "../deadlines-list";

import { satisfyDeadline } from "../deadlines-actions";
import { deadlineList } from "../deadlines-list";
import { DeadlineStateBadge, useDeadlineLabel } from "./deadline-badges";

type DeadlineCell = CellContext<ReadOnlyGridFeatures, DeadlineRow>;

function StateCell({ row }: DeadlineCell) {
  return <DeadlineStateBadge state={row.original.state} />;
}

function DueCell({ row }: DeadlineCell) {
  const t = useExtracted("work");
  const { dueOn, provisional } = row.original;

  if (dueOn === null) {
    return <span className="text-muted-foreground">{t("No date")}</span>;
  }

  return (
    <span className="tabular-nums">
      {dueOn}
      {provisional ? ` (${t("provisional")})` : ""}
    </span>
  );
}

function DoneCell({ row }: DeadlineCell) {
  const t = useExtracted("work");
  const errorMessage = useErrorMessage();

  const satisfy = useAction(satisfyDeadline, {
    onSuccess: () => {
      toast.success(t("Deadline marked done"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  if (row.original.state === "satisfied") {
    return null;
  }

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={satisfy.pending}
      onClick={() => {
        void satisfy.run({ deadlineId: row.original.id });
      }}
    >
      {t("Mark done")}
    </Button>
  );
}

/** Deadlines on the list kit; the URL holds search, filters, sort and page. */
export function DeadlineRecordList({
  initial,
  kinds,
}: {
  initial: RecordListPage<DeadlineRow>;
  kinds: readonly string[];
}) {
  const t = useExtracted("work");
  const label = useDeadlineLabel();
  const list = useBlockListState(deadlineList);

  const columns: RecordListColumns<DeadlineRow> = [
    { accessorKey: "kind", header: t("Deadline"), size: 220 },
    { accessorKey: "groupKey", header: t("Group"), size: 160 },
    { accessorKey: "subjectType", header: t("Record"), size: 140 },
    { id: "due", header: t("Due"), size: 180, cell: DueCell },
    { accessorKey: "result", header: t("Result"), size: 140 },
    { accessorKey: "state", header: t("State"), size: 120, cell: StateCell },
    { id: "done", header: "", size: 120, cell: DoneCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/deadlines/list"
      initial={initial}
      columns={columns}
      facets={[
        { key: "state", label: t("State"), valueLabel: label },
        { key: "result", label: t("Result"), valueLabel: label },
        {
          key: "kind",
          label: t("Deadline"),
          valueLabel: (value) => value,
          values: kinds,
        },
      ]}
      sorts={[
        { value: "due", label: t("Nearest due") },
        { value: "newest", label: t("Newest") },
        { value: "kind", label: t("Deadline") },
      ]}
      searchLabel={t("Search deadlines")}
      emptyIcon={<HourglassIcon />}
      emptyTitle={t("No deadlines found")}
      emptyDescription={t(
        "Deadlines appear when a record's rules compute them, or change the filters.",
      )}
    />
  );
}
