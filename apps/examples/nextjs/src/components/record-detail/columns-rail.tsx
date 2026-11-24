import type { EntityColumn } from "better-supabase/list";

import type { Property } from "./properties-rail";

import { PropertiesRail } from "./properties-rail";

export type RailValue = string | number | boolean | null;

const NO_FORMAT: Readonly<Record<string, Property["value"]>> = {};

/**
 * The properties rail of a record, from the page's generated columns: one row
 * per column, labelled as the column is, with the value the caller formats by
 * key. A column the caller leaves out of `formatted` reads the raw value.
 */
export function ColumnsRail({
  title,
  columns,
  row,
  formatted = NO_FORMAT,
}: {
  title: string;
  columns: readonly EntityColumn[];
  row: Readonly<Record<string, RailValue>>;
  formatted?: Readonly<Record<string, Property["value"]>>;
}) {
  const properties = columns.map((column): Property => {
    const raw = row[column.column];

    return {
      label: column.label,
      value:
        formatted[column.key] ??
        (raw === null || raw === undefined ? null : String(raw)),
    };
  });

  return <PropertiesRail title={title} properties={properties} />;
}
