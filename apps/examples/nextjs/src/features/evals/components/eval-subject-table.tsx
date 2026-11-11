"use client";

import type { CellContext } from "@tanstack/react-table";

import { FlaskConicalIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { OpsList } from "@/components/ops-list/ops-list";
import { Link } from "@/i18n/navigation";

import type { EvalSubjectRow } from "../evals-queries";

function NameCell({ row }: CellContext<ReadOnlyGridFeatures, EvalSubjectRow>) {
  const { id, title } = row.original;

  return (
    <Link
      href={`/assistant/evals/${encodeURIComponent(id)}`}
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

/** The prompts that have an eval workspace. */
export function EvalSubjectTable({
  items,
  nextCursor,
}: {
  items: readonly EvalSubjectRow[];
  nextCursor: string | null;
}) {
  const t = useExtracted("evals");

  const columns: RecordListColumns<EvalSubjectRow> = [
    {
      accessorKey: "title",
      header: t("Prompt under test"),
      size: 480,
      cell: NameCell,
    },
  ];

  return (
    <OpsList
      rows={items}
      columns={columns}
      nextCursor={nextCursor}
      sorts={[{ value: "name", label: t("Name") }]}
      searchLabel={t("Search prompts")}
      emptyIcon={<FlaskConicalIcon />}
      emptyTitle={t("No prompts found")}
      emptyDescription={t("Change the search.")}
    />
  );
}
