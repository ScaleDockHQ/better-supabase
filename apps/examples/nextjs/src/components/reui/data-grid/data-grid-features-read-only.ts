import {
  cellSelectionFeature,
  columnOrderingFeature,
  columnPinningFeature,
  columnResizingFeature,
  columnSizingFeature,
  columnVisibilityFeature,
  metaHelper,
  rowExpandingFeature,
  rowPinningFeature,
  rowSelectionFeature,
  rowSortingFeature,
  tableFeatures,
} from "@tanstack/react-table";

import type { DataGridColumnMeta } from "./data-grid";

/**
 * The features a grid that only displays rows needs: it renders, sizes, pins
 * and hides columns, but never sorts, filters, facets or pages them. It leaves
 * out the sorted, filtered, faceted and paginated row models and the sort
 * functions, which a route otherwise ships for every table it renders.
 * `rowSortingFeature` stays registered because the header cell reads
 * `column.getIsSorted()` and `column.getCanSort()`; without a sorted row model
 * and sort functions it can only report that nothing sorts.
 *
 * Use it for a table with plain columns and no `state`, `enableRowSelection` or
 * header sort; use `dataGridFeatures` for the rest.
 */
export const readOnlyGridFeatures = tableFeatures({
  columnVisibilityFeature,
  columnOrderingFeature,
  columnPinningFeature,
  columnSizingFeature,
  columnResizingFeature,
  rowSortingFeature,
  rowSelectionFeature,
  rowExpandingFeature,
  rowPinningFeature,
  cellSelectionFeature,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  columnMeta: metaHelper<DataGridColumnMeta<any>>(),
});
