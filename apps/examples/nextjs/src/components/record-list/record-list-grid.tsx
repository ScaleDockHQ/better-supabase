"use client";

import type { ColumnDef, RowData } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import {
  DataGrid,
  DataGridContainer,
} from "@/components/reui/data-grid/data-grid";
import { readOnlyGridFeatures } from "@/components/reui/data-grid/data-grid-features-read-only";
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";

export type RecordListColumns<Row extends RowData> = ColumnDef<
  ReadOnlyGridFeatures,
  Row
>[];

/**
 * The rows of a list in a read-only data grid. The server sorts, filters and
 * pages, so the grid registers no sorted, filtered or paginated row model. A
 * failed read shows an inline error with Retry; an empty result shows the
 * entity's empty state with its action.
 */
export function RecordListGrid<Row extends RowData & { readonly id: string }>({
  rows,
  columns,
  failed,
  pending,
  emptyIcon,
  emptyTitle,
  emptyDescription,
  emptyAction,
  onRetry,
}: {
  rows: readonly Row[];
  columns: RecordListColumns<Row>;
  failed: boolean;
  pending: boolean;
  emptyIcon: React.ReactNode;
  emptyTitle: string;
  emptyDescription: string;
  /** The action of the empty state: reset the filters or create a record. */
  emptyAction: React.ReactNode;
  onRetry: () => void;
}) {
  const t = useExtracted("recordList");

  const table = useTable({
    features: readOnlyGridFeatures,
    columns,
    data: [...rows],
    getRowId: (row) => row.id,
  });

  if (failed) {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The list did not load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <Button size="sm" variant="outline" onClick={onRetry}>
            {t("Retry")}
          </Button>
        </AlertAction>
      </Alert>
    );
  }

  if (rows.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">{emptyIcon}</EmptyMedia>
          <EmptyTitle>{emptyTitle}</EmptyTitle>
          <EmptyDescription>{emptyDescription}</EmptyDescription>
        </EmptyHeader>
        <EmptyContent>{emptyAction}</EmptyContent>
      </Empty>
    );
  }

  return (
    <div
      className="transition-opacity duration-200 aria-busy:opacity-60 motion-reduce:transition-none"
      aria-busy={pending}
    >
      <DataGrid
        table={table}
        recordCount={rows.length}
        tableLayout={{ dense: true }}
      >
        <DataGridContainer>
          <DataGridScrollArea>
            <DataGridTable />
          </DataGridScrollArea>
        </DataGridContainer>
      </DataGrid>
    </div>
  );
}
