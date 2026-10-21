/**
 * What decides when `DataGridProvider` publishes a new context value. The
 * published value changes only when these inputs do, so a missing input means
 * cells keep painting stale rows.
 */

/** The parts of a TanStack table the inputs read. */
export type DataGridInputsTable = {
  readonly options: { readonly data: unknown; readonly columns: unknown };
  readonly state: object;
};

// Slices kept out of the inputs: cells paint cell selection through their
// own Subscribe, and a resize drag paints through useDataGridAtom.
const DATA_GRID_UNPUBLISHED_STATE = new Set([
  "cellSelection",
  "columnResizing",
]);

const isDataGridPropNode = (value: unknown) =>
  value !== null &&
  typeof value === "object" &&
  !Array.isArray(value) &&
  ("$$typeof" in value || Object.getPrototypeOf(value) !== Object.prototype);

// Functions and React nodes count by presence here; their identity is a
// callback input.
function dataGridPropsSignatureReplacer(_key: string, value: unknown) {
  if (typeof value === "function") return "fn";
  if (isDataGridPropNode(value)) return "node";
  return value;
}

/**
 * Inputs that always publish: every state slice but the two above, `data`
 * and `columns` (TanStack needs both stable already), and props by value.
 * `data` must stay in: an edit in place keeps `recordCount`, so without it
 * the grid keeps showing the old row.
 */
export function getDataGridStateInputs(
  table: DataGridInputsTable,
  props: object,
  autoSize: unknown,
): unknown[] {
  const inputs: unknown[] = [
    autoSize,
    table.options.data,
    table.options.columns,
    JSON.stringify(props, dataGridPropsSignatureReplacer),
  ];
  for (const [key, slice] of Object.entries(table.state)) {
    if (!DATA_GRID_UNPUBLISHED_STATE.has(key)) inputs.push(key, slice);
  }
  return inputs;
}

/** Every callback and React node prop, compared by identity. */
export function getDataGridCallbackInputs(props: object): unknown[] {
  return Object.values(props).filter(
    (value) => typeof value === "function" || isDataGridPropNode(value),
  );
}

export const isSameDataGridInputs = (previous: unknown[], next: unknown[]) =>
  previous.length === next.length &&
  next.every((input, index) => Object.is(input, previous[index]));
