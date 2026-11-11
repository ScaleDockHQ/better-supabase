"use client";

import type { CellContext } from "@tanstack/react-table";

import { FileStackIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { useBlockListState } from "@/components/record-list/use-block-list-state";
import { Link } from "@/i18n/navigation";

import type { TemplateRow } from "../document-templates-list";

import { templateList } from "../document-templates-list";
import {
  TemplateActiveBadge,
  useTemplateActiveLabel,
} from "./template-active-badge";

type TemplateCell = CellContext<ReadOnlyGridFeatures, TemplateRow>;

function NameCell({ row }: TemplateCell) {
  return (
    <Link
      href={`/documents/templates/${row.original.id}`}
      className="font-medium hover:underline"
    >
      {row.original.name}
    </Link>
  );
}

function ActiveCell({ row }: TemplateCell) {
  return <TemplateActiveBadge active={row.original.active} />;
}

/** Document templates on the list kit, filtered by type and state. */
export function TemplateRecordList({
  initial,
  types,
}: {
  initial: RecordListPage<TemplateRow>;
  types: readonly string[];
}) {
  const t = useExtracted("documents");
  const activeLabel = useTemplateActiveLabel();
  const list = useBlockListState(templateList);

  const columns: RecordListColumns<TemplateRow> = [
    { accessorKey: "name", header: t("Name"), size: 240, cell: NameCell },
    { accessorKey: "documentType", header: t("Document type"), size: 180 },
    { accessorKey: "language", header: t("Language"), size: 120 },
    { accessorKey: "version", header: t("Version"), size: 100 },
    { id: "active", header: t("State"), size: 120, cell: ActiveCell },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/document-templates/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "type",
          label: t("Document type"),
          valueLabel: (value) => value,
          values: types,
        },
        { key: "active", label: t("State"), valueLabel: activeLabel },
      ]}
      sorts={[
        { value: "name", label: t("Name") },
        { value: "newest", label: t("Recently changed") },
      ]}
      searchLabel={t("Search templates")}
      emptyIcon={<FileStackIcon />}
      emptyTitle={t("No templates found")}
      emptyDescription={t("Add a template, or change the filters.")}
    />
  );
}
