"use client";

import type { CellContext } from "@tanstack/react-table";

import { useQueryClient } from "@tanstack/react-query";
import { WorkflowIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useEffect, useRef } from "react";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useSimpleListState } from "@/components/record-list/use-simple-list-state";
import { Badge } from "@/components/reui/badge";
import { useWorkflowRuns } from "@/hooks/use-workflows";
import { Link, useRouter } from "@/i18n/navigation";

import type { RunListRow } from "../workflow-lists";
import type { RunDefinitionOption } from "../workflows-list-data";

import { formatDuration, statusBadge } from "../workflow-labels";
import { RUN_MODES, RUN_SINCE, RUN_STATUSES, runList } from "../workflow-lists";

type Cell = CellContext<ReadOnlyGridFeatures, RunListRow>;

const ENDPOINT = "/api/workflows/runs/list";

function NameCell({ row }: Cell) {
  const { id, name } = row.original;

  return (
    <Link
      href={`/workflows/runs/${id}`}
      prefetch
      className="font-medium hover:underline"
    >
      {name}
    </Link>
  );
}

function StatusCell({ row }: Cell) {
  const { status, mode } = row.original;

  return (
    <span className="flex items-center gap-2">
      <Badge variant={statusBadge(status)}>{status}</Badge>
      {mode === "test" ? <Badge variant="outline">test</Badge> : null}
    </span>
  );
}

function StartedCell({ row }: Cell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground tabular-nums">
      {format.dateTime(new Date(row.original.createdAt), {
        dateStyle: "medium",
        timeStyle: "short",
      })}
    </span>
  );
}

function DurationCell({ row }: Cell) {
  const { durationMs } = row.original;

  return (
    <span className="text-muted-foreground tabular-nums">
      {durationMs === null ? "–" : formatDuration(durationMs)}
    </span>
  );
}

/**
 * Reloads the list when a run in the organization changes status
 * (`workflow-runs:<tenant>` over Realtime): the server page and the cached
 * pages of the list route are both refreshed.
 */
function LiveRuns({ tenant }: { tenant: string }) {
  const router = useRouter();
  const client = useQueryClient();
  const { runs } = useWorkflowRuns({ tenant, schema: "api", limit: 5 });
  const seen = useRef<string | undefined>(undefined);

  const signature = runs?.map((run) => `${run.id}:${run.status}`).join(",");

  useEffect(() => {
    if (signature === undefined) {
      return;
    }

    if (seen.current !== undefined && seen.current !== signature) {
      void client.invalidateQueries({ queryKey: ["record-list", ENDPOINT] });
      router.refresh();
    }

    seen.current = signature;
  }, [signature, client, router]);

  return null;
}

/**
 * The runs overview on the list kit: the URL holds the search, the status,
 * mode, workflow and time filters and the page; the list route serves every
 * state but the default, which the server renders. It reloads while runs
 * change.
 */
export function RunsRecordList({
  initial,
  definitions,
  tenant,
}: {
  initial: RecordListPage<RunListRow>;
  definitions: readonly RunDefinitionOption[];
  tenant: string | null;
}) {
  const t = useExtracted("workflows");
  const list = useSimpleListState(runList);

  const sinceLabel = (value: string): string => {
    switch (value) {
      case "hour": {
        return t("Last hour");
      }

      case "day": {
        return t("Last 24 hours");
      }

      default: {
        return t("Last 7 days");
      }
    }
  };

  const columns: RecordListColumns<RunListRow> = [
    { accessorKey: "name", header: t("Workflow"), size: 300, cell: NameCell },
    { accessorKey: "status", header: t("Status"), size: 200, cell: StatusCell },
    {
      accessorKey: "createdAt",
      header: t("Started"),
      size: 200,
      cell: StartedCell,
    },
    {
      accessorKey: "durationMs",
      header: t("Duration"),
      size: 120,
      cell: DurationCell,
    },
  ];

  const names = new Map(definitions.map((item) => [item.value, item.label]));

  return (
    <>
      {tenant === null ? null : <LiveRuns tenant={tenant} />}
      <RecordListView
        list={list}
        endpoint={ENDPOINT}
        initial={initial}
        columns={columns}
        facets={[
          {
            key: "status",
            label: t("Status"),
            valueLabel: (value) => value,
            values: RUN_STATUSES,
          },
          {
            key: "mode",
            label: t("Mode"),
            valueLabel: (value) => value,
            values: RUN_MODES,
          },
          {
            key: "definition",
            label: t("Workflow"),
            valueLabel: (value) => names.get(value) ?? value,
            values: definitions.map((item) => item.value),
          },
          {
            key: "since",
            label: t("Started"),
            valueLabel: sinceLabel,
            values: Object.keys(RUN_SINCE),
          },
        ]}
        sorts={[{ value: "newest", label: t("Newest first") }]}
        searchLabel={t("Search runs")}
        emptyIcon={<WorkflowIcon />}
        emptyTitle={t("No runs found")}
        emptyDescription={t(
          "Start a sample workflow, run one from the editor, or change the filters.",
        )}
      />
    </>
  );
}
