"use client";

import type { CellContext } from "@tanstack/react-table";

import { FileCodeIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { OpsList } from "@/components/ops-list/ops-list";
import { Badge } from "@/components/reui/badge";
import { Link } from "@/i18n/navigation";

import type { PromptRow } from "../prompts-queries";

type PromptCell = CellContext<ReadOnlyGridFeatures, PromptRow>;

function NameCell({ row }: PromptCell) {
  const { id, title } = row.original;

  return (
    <Link
      href={`/assistant/prompts/${encodeURIComponent(id)}`}
      prefetch
      className="flex min-w-0 flex-col font-medium hover:underline"
    >
      <span>{title}</span>
      <span className="font-mono text-xs font-normal text-muted-foreground">
        {id}
      </span>
    </Link>
  );
}

function ProductionCell({ row }: PromptCell) {
  const t = useExtracted("prompts");
  const { production } = row.original;

  return production === undefined ? (
    <Badge variant="secondary">{t("Built-in text")}</Badge>
  ) : (
    <Badge variant="success-light">
      {t("v{version, number} live", { version: production })}
    </Badge>
  );
}

function VersionsCell({ row }: PromptCell) {
  return <span className="tabular-nums">{row.original.versions}</span>;
}

function UpdatedCell({ row }: PromptCell) {
  const format = useFormatter();
  const { updatedAt } = row.original;

  return (
    <span className="text-muted-foreground tabular-nums">
      {updatedAt === undefined
        ? "–"
        : format.dateTime(new Date(updatedAt), { dateStyle: "medium" })}
    </span>
  );
}

/** The prompt registry overview, driven by the URL. */
export function PromptTable({
  items,
  nextCursor,
}: {
  items: readonly PromptRow[];
  nextCursor: string | null;
}) {
  const t = useExtracted("prompts");

  const columns: RecordListColumns<PromptRow> = [
    { accessorKey: "title", header: t("Prompt"), size: 340, cell: NameCell },
    {
      accessorKey: "production",
      header: t("Live version"),
      size: 160,
      cell: ProductionCell,
    },
    {
      accessorKey: "versions",
      header: t("Versions"),
      size: 100,
      cell: VersionsCell,
    },
    {
      accessorKey: "updatedAt",
      header: t("Updated"),
      size: 140,
      cell: UpdatedCell,
    },
  ];

  return (
    <OpsList
      rows={items}
      columns={columns}
      nextCursor={nextCursor}
      filter={{
        label: t("Every prompt"),
        options: [
          { value: "live", label: t("Has a live version") },
          { value: "unversioned", label: t("No versions yet") },
        ],
      }}
      sorts={[
        { value: "name", label: t("Name") },
        { value: "updated", label: t("Recently updated") },
      ]}
      searchLabel={t("Search prompts")}
      emptyIcon={<FileCodeIcon />}
      emptyTitle={t("No prompts found")}
      emptyDescription={t("Change the search or the filter.")}
    />
  );
}
