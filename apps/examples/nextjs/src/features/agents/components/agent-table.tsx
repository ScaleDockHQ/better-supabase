"use client";

import type { CellContext } from "@tanstack/react-table";

import { NetworkIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { OpsList } from "@/components/ops-list/ops-list";
import { Badge } from "@/components/reui/badge";
import { Link } from "@/i18n/navigation";

import type { AgentRow } from "../agents-queries";

import { PlaybookWizard } from "./playbook-wizard";

type AgentCell = CellContext<ReadOnlyGridFeatures, AgentRow>;

function NameCell({ row }: AgentCell) {
  const { id, name, description } = row.original;

  return (
    <Link
      href={`/assistant/agents/${id}`}
      prefetch
      className="flex min-w-0 flex-col font-medium hover:underline"
    >
      <span className="truncate">{name}</span>
      {description === "" ? null : (
        <span className="truncate text-xs font-normal text-muted-foreground">
          {description}
        </span>
      )}
    </Link>
  );
}

function VisibilityCell({ row }: AgentCell) {
  const { visibility } = row.original;

  return (
    <Badge
      variant={
        visibility === "public"
          ? "success-light"
          : visibility === "organization"
            ? "info-light"
            : "secondary"
      }
    >
      {visibility}
    </Badge>
  );
}

function ModelCell({ row }: AgentCell) {
  const { model } = row.original;

  return <span className="text-muted-foreground">{model ?? "–"}</span>;
}

function ToolsCell({ row }: AgentCell) {
  return <span className="tabular-nums">{row.original.tools}</span>;
}

function InstallsCell({ row }: AgentCell) {
  const t = useExtracted("agents");
  const { installs, installed } = row.original;

  return (
    <span className="tabular-nums">
      {installs}
      {installed ? ` · ${t("Installed")}` : ""}
    </span>
  );
}

function UpdatedCell({ row }: AgentCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground tabular-nums">
      {format.dateTime(new Date(row.original.updatedAt), {
        dateStyle: "medium",
      })}
    </span>
  );
}

/**
 * The fleet overview: the URL holds the search, the filter, the sort and the
 * page.
 */
export function AgentTable({
  items,
  nextCursor,
  canWrite,
}: {
  items: readonly AgentRow[];
  nextCursor: string | null;
  canWrite: boolean;
}) {
  const t = useExtracted("agents");

  const columns: RecordListColumns<AgentRow> = [
    { accessorKey: "name", header: t("Agent"), size: 300, cell: NameCell },
    {
      accessorKey: "visibility",
      header: t("Visibility"),
      size: 130,
      cell: VisibilityCell,
    },
    { accessorKey: "model", header: t("Model"), size: 200, cell: ModelCell },
    { accessorKey: "tools", header: t("Tools"), size: 80, cell: ToolsCell },
    {
      accessorKey: "installs",
      header: t("Installs"),
      size: 130,
      cell: InstallsCell,
    },
    {
      accessorKey: "updatedAt",
      header: t("Updated"),
      size: 130,
      cell: UpdatedCell,
    },
  ];

  return (
    <OpsList
      rows={items}
      columns={columns}
      nextCursor={nextCursor}
      filter={{
        label: t("The store"),
        options: [
          { value: "mine", label: t("My agents") },
          { value: "installed", label: t("Installed") },
        ],
      }}
      sorts={[
        { value: "updated", label: t("Recently updated") },
        { value: "popular", label: t("Most installed") },
        { value: "name", label: t("Name") },
      ]}
      searchLabel={t("Search agents")}
      emptyIcon={<NetworkIcon />}
      emptyTitle={t("No agents found")}
      emptyDescription={
        canWrite
          ? t("Start from a playbook, or change the filters.")
          : t("Change the filters to see more.")
      }
      emptyAction={canWrite ? <PlaybookWizard /> : undefined}
    />
  );
}
