"use client";

import { HashIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";

import { dateCell } from "@/features/admin-lists/admin-cells";
import { AdminRecordList } from "@/features/admin-lists/admin-record-list";

import type { NumberingRow } from "../numbering-list";

import { numberingList } from "../numbering-list";

/** Numbering on the list kit. */
export function NumberingRecordList({
  initial,
}: {
  initial: RecordListPage<NumberingRow>;
}) {
  const t = useExtracted("numbering");

  const columns: RecordListColumns<NumberingRow> = [
    { accessorKey: "entity", header: t("Document"), size: 220 },
    { accessorKey: "period", header: t("Period"), size: 140 },
    { accessorKey: "lastNumber", header: t("Last number"), size: 140 },
    {
      id: "updated",
      header: t("Updated"),
      size: 200,
      cell: dateCell<NumberingRow>((row) => row.updatedAt),
    },
  ];

  return (
    <AdminRecordList
      list={numberingList}
      endpoint="/api/numbering/list"
      initial={initial}
      columns={columns}
      facets={[
        { key: "entity", label: t("Document"), valueLabel: (value) => value },
      ]}
      searchLabel={t("Search sequences")}
      emptyIcon={<HashIcon />}
      emptyTitle={t("No number sequences yet")}
      emptyDescription={t(
        "A sequence appears when the first document number is assigned.",
      )}
    />
  );
}
