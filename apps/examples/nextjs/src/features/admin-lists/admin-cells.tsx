"use client";

import type { CellContext, RowData } from "@tanstack/react-table";

import { useFormatter } from "next-intl";

import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

type AdminCell<Row extends RowData> = (
  context: CellContext<ReadOnlyGridFeatures, Row>,
) => React.ReactNode;

type Read<Row, Value> = (row: Row) => Value;

/** A timestamp column, or a dash while the row has none. */
export function dateCell<Row extends RowData>(
  pick: Read<Row, string | null>,
): AdminCell<Row> {
  return function DateCell({ row }) {
    const format = useFormatter();
    const value = pick(row.original);

    return (
      <span className="text-xs text-muted-foreground">
        {value
          ? format.dateTime(new Date(value), {
              dateStyle: "medium",
              timeStyle: "short",
            })
          : "–"}
      </span>
    );
  };
}

/** A short list of values, joined with commas. */
export function listCell<Row extends RowData>(
  pick: Read<Row, readonly string[]>,
): AdminCell<Row> {
  return function ListCell({ row }) {
    const values = pick(row.original);

    return (
      <span className="truncate text-xs text-muted-foreground">
        {values.length > 0 ? values.join(", ") : "–"}
      </span>
    );
  };
}
