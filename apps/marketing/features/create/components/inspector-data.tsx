"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";
import type { ReactElement } from "react";

import { useTable } from "@tanstack/react-table";
import { Columns3Icon, TableIcon } from "lucide-react";

import type { SchemaTable } from "@/lib/schema";

import {
  DataGrid,
  DataGridContainer,
  type DataGridFeatures,
  dataGridFeatures,
} from "@/components/reui/data-grid/data-grid";
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
import { isAppTable } from "@/lib/design";
import { type SampleRow, sampleRows } from "@/lib/sample-rows";

import type { InspectorTab } from "./schema-nodes";

import { useDesign } from "./design-provider";

function SampleCell({
  getValue,
}: CellContext<DataGridFeatures, SampleRow>): ReactElement {
  const value = getValue<string | null>();

  return value === null ? (
    <span className="text-muted-foreground">null</span>
  ) : (
    <span className="truncate">{value}</span>
  );
}

function SampleGrid({
  columns,
  rows,
}: {
  columns: readonly string[];
  rows: readonly SampleRow[];
}): ReactElement {
  const definitions: ColumnDef<DataGridFeatures, SampleRow>[] = columns.map(
    (column) => ({
      id: column,
      accessorFn: (row) => row[column] ?? null,
      header: column,
      cell: SampleCell,
      size: 160,
    }),
  );

  const table = useTable({
    features: dataGridFeatures,
    columns: definitions,
    data: [...rows],
  });

  return (
    <DataGrid table={table} recordCount={rows.length}>
      <DataGridContainer>
        <DataGridScrollArea>
          <DataGridTable />
        </DataGridScrollArea>
      </DataGridContainer>
    </DataGrid>
  );
}

/**
 * Sample rows for an app table, built in the browser from its columns'
 * types, formats, options and references. Nothing is written anywhere.
 */
export function DataTab({
  table,
  onTab,
}: {
  table: SchemaTable;
  onTab: (tab: InspectorTab) => void;
}): ReactElement {
  const { state } = useDesign();

  if (!isAppTable(table)) {
    return (
      <Empty className="border border-dashed p-6">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <TableIcon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>No sample rows</EmptyTitle>
          <EmptyDescription>
            Sample rows are for app tables. The {table.module} block&apos;s page
            describes what this table stores.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  const sample = sampleRows(state.design, table.name);

  if (sample.columns.length === 0) {
    return (
      <Empty className="border border-dashed p-6">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <Columns3Icon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>No columns yet</EmptyTitle>
          <EmptyDescription>
            Add a column and the sample rows follow its type, format and
            options.
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => {
              onTab("columns");
            }}
          >
            Open Columns
          </Button>
        </EmptyContent>
      </Empty>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm text-muted-foreground">
        Made-up rows that follow each column&apos;s type, format, options and
        references, so you can check the design reads well. They stay in this
        browser.
      </p>
      <SampleGrid
        key={sample.columns.join(",")}
        columns={sample.columns}
        rows={sample.rows}
      />
    </div>
  );
}
