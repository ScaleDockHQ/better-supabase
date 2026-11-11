"use client";

import { SearchIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";

import { dateCell } from "@/features/admin-lists/admin-cells";
import { AdminRecordList } from "@/features/admin-lists/admin-record-list";

import type { SearchDocumentRow } from "../search-settings-list";

import { searchDocumentList } from "../search-settings-list";

/** Search index on the list kit. */
export function SearchDocumentRecordList({
  initial,
}: {
  initial: RecordListPage<SearchDocumentRow>;
}) {
  const t = useExtracted("searchSettings");

  const columns: RecordListColumns<SearchDocumentRow> = [
    { accessorKey: "title", header: t("Title"), size: 300 },
    { accessorKey: "subjectType", header: t("Record type"), size: 160 },
    { accessorKey: "url", header: t("Link"), size: 260 },
    {
      id: "updated",
      header: t("Indexed"),
      size: 200,
      cell: dateCell<SearchDocumentRow>((row) => row.updatedAt),
    },
  ];

  return (
    <AdminRecordList
      list={searchDocumentList}
      endpoint="/api/search-documents/list"
      initial={initial}
      columns={columns}
      facets={[
        { key: "type", label: t("Record type"), valueLabel: (value) => value },
      ]}
      searchLabel={t("Search the index")}
      emptyIcon={<SearchIcon />}
      emptyTitle={t("No indexed records found")}
      emptyDescription={t(
        "Records join the search index when they are saved; change the filters to see more.",
      )}
    />
  );
}
