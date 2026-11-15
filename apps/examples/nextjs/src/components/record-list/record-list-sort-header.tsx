"use client";

import type { HeaderContext, RowData } from "@tanstack/react-table";

import { ArrowDownIcon, ArrowUpIcon, ChevronsUpDownIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { Button } from "@/components/ui/button";

/**
 * A column header that sorts through the URL (`RecordListSorting`). A click
 * sorts by this column alone, a second click flips it, and a shift-click adds
 * it to the sort the list already has. The grid sets `aria-sort` on the cell.
 */
export function RecordListSortHeader<Row extends RowData>({
  column,
  title,
}: HeaderContext<ReadOnlyGridFeatures, Row> & { title: string }) {
  const t = useExtracted("recordList");
  const sorted = column.getIsSorted();
  const index = column.getSortIndex();
  const multiple = (column.table.options.state?.sorting?.length ?? 0) > 1;

  return (
    <Button
      type="button"
      variant="ghost"
      size="sm"
      title={t("Shift-click adds this column to the sort")}
      onClick={column.getToggleSortingHandler()}
    >
      {title}
      {sorted === "asc" ? <ArrowUpIcon aria-hidden /> : null}
      {sorted === "desc" ? <ArrowDownIcon aria-hidden /> : null}
      {sorted === false ? <ChevronsUpDownIcon aria-hidden /> : null}
      {sorted !== false && multiple ? (
        <span className="text-xs text-muted-foreground tabular-nums">
          {index + 1}
        </span>
      ) : null}
    </Button>
  );
}
