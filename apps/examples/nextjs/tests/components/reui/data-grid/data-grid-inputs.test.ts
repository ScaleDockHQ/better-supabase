import { describe, expect, it } from "vitest";

import {
  getDataGridCallbackInputs,
  getDataGridStateInputs,
  isSameDataGridInputs,
} from "@/components/reui/data-grid/data-grid-inputs";

type Task = { readonly id: string; readonly title: string };

type GridState = {
  readonly sorting?: readonly Task[];
  readonly cellSelection?: { readonly a: number };
  readonly columnResizing?: { readonly isResizingColumn: string };
};

const columns = [{ accessorKey: "title" }];

const tableWith = (data: readonly Task[], state: GridState = {}) => ({
  options: { data, columns },
  state,
});

describe("getDataGridStateInputs", () => {
  it("changes when the data changes but recordCount stays the same", () => {
    const props = { recordCount: 1 };

    const before = getDataGridStateInputs(
      tableWith([{ id: "1", title: "Draft" }]),
      props,
      false,
    );

    const after = getDataGridStateInputs(
      tableWith([{ id: "1", title: "Final" }]),
      props,
      false,
    );

    expect(isSameDataGridInputs(before, after)).toBe(false);
  });

  it("stays the same for the same data, columns and props", () => {
    const data = [{ id: "1", title: "Draft" }];

    expect(
      isSameDataGridInputs(
        getDataGridStateInputs(tableWith(data), { recordCount: 1 }, false),
        getDataGridStateInputs(tableWith(data), { recordCount: 1 }, false),
      ),
    ).toBe(true);
  });

  it("ignores cell selection and column resizing", () => {
    const data: Task[] = [];
    const sorting: Task[] = [];

    const before = getDataGridStateInputs(
      tableWith(data, { sorting, cellSelection: { a: 1 } }),
      {},
      false,
    );

    const after = getDataGridStateInputs(
      tableWith(data, {
        sorting,
        cellSelection: { a: 2 },
        columnResizing: { isResizingColumn: "title" },
      }),
      {},
      false,
    );

    expect(isSameDataGridInputs(before, after)).toBe(true);
  });
});

describe("getDataGridCallbackInputs", () => {
  it("keeps functions and drops plain values", () => {
    const onRowClick = (): void => undefined;

    expect(
      getDataGridCallbackInputs({ onRowClick, recordCount: 3 }),
    ).toStrictEqual([onRowClick]);
  });
});
