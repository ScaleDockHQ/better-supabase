import { useTable } from "@tanstack/react-table";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import {
  DataGrid,
  DataGridContainer,
} from "@/components/reui/data-grid/data-grid";
import { dataGridFeatures } from "@/components/reui/data-grid/data-grid-features";
import { readOnlyGridFeatures } from "@/components/reui/data-grid/data-grid-features-read-only";
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table";

interface Row {
  readonly id: string;
  readonly name: string;
  readonly status: string;
}

const rows: readonly Row[] = [
  { id: "1", name: "Alpha", status: "open" },
  { id: "2", name: "Beta", status: "closed" },
];

const columns = [
  { accessorKey: "name", header: "Name", size: 200 },
  { accessorKey: "status", header: "Status", size: 120 },
];

const common = { columns, data: [...rows], getRowId: (row: Row) => row.id };

function Body({ table }: { table: unknown }) {
  return createElement(
    DataGrid,
    {
      // SAFETY: DataGrid takes any feature bundle; the prop type only names the full one.
      table: table as never,
      recordCount: rows.length,
      tableLayout: { dense: true },
    },
    createElement(
      DataGridContainer,
      null,
      createElement(DataGridScrollArea, null, createElement(DataGridTable)),
    ),
  );
}

function LeanGrid() {
  const table = useTable({ ...common, features: readOnlyGridFeatures });

  return createElement(Body, { table });
}

function FullGrid() {
  const table = useTable({ ...common, features: dataGridFeatures });

  return createElement(Body, { table });
}

describe("readOnlyGridFeatures", () => {
  it("renders the same table as the full feature bundle", () => {
    const lean = renderToStaticMarkup(createElement(LeanGrid));
    const full = renderToStaticMarkup(createElement(FullGrid));

    expect(lean).toContain("Alpha");
    expect(lean).toContain("Beta");
    expect(lean).toContain("Status");
    expect(lean).toBe(full);
  });
});
