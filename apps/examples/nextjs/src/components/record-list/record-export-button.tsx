"use client";

import { DownloadIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";

export interface ExportColumn<Row> {
  readonly header: string;
  readonly value: (row: Row) => string | number | null | undefined;
}

/** One CSV field: quoted when it holds a separator, a quote or a newline. */
export function csvField(value: string | number | null | undefined): string {
  const text = value === null || value === undefined ? "" : String(value);

  return /[",\n\r]/u.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

/** The CSV text of `rows` under `columns`, header line first. */
export function toCsv<Row>(
  rows: readonly Row[],
  columns: readonly ExportColumn<Row>[],
): string {
  const lines = [
    columns.map((column) => csvField(column.header)).join(","),
    ...rows.map((row) =>
      columns.map((column) => csvField(column.value(row))).join(","),
    ),
  ];

  return `${lines.join("\n")}\n`;
}

/** Downloads the rows on screen (or the ticked ones) as a CSV file. */
export function RecordExportButton<Row>({
  rows,
  columns,
  filename,
}: {
  rows: readonly Row[];
  columns: readonly ExportColumn<Row>[];
  filename: string;
}) {
  const t = useExtracted("recordList");

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={rows.length === 0}
      onClick={() => {
        const url = URL.createObjectURL(
          new Blob([toCsv(rows, columns)], { type: "text/csv;charset=utf-8" }),
        );

        const link = document.createElement("a");
        link.href = url;
        link.download = `${filename}.csv`;
        link.click();

        URL.revokeObjectURL(url);
      }}
    >
      <DownloadIcon />
      {t("Export CSV")}
    </Button>
  );
}
