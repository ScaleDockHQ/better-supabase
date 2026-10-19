import {
  type AppTable,
  addTable,
  type Design,
  freeTableName,
} from "better-supabase/create";

export type PrimitiveKind = "table" | "lookup" | "tree";

/** The drag data type of a primitive dragged from the side menu onto the canvas. */
export const PRIMITIVE_DRAG_TYPE = "application/x-better-supabase-primitive";

interface Primitive {
  readonly kind: PrimitiveKind;
  readonly title: string;
  readonly description: string;
  /** The name of the first table of this kind; later ones get `_2`, `_3`. */
  readonly base: string;
  readonly table: AppTable;
}

export const PRIMITIVES: readonly Primitive[] = [
  {
    kind: "table",
    title: "Table",
    description: "An app table with an id and timestamps.",
    base: "items",
    table: {},
  },
  {
    kind: "lookup",
    title: "Lookup table",
    description:
      "A unique code and a label, for statuses and other fixed lists.",
    base: "lookups",
    table: {
      columns: {
        code: { type: "text", nullable: false, unique: true },
        label: { type: "text", nullable: false },
      },
    },
  },
  {
    kind: "tree",
    title: "Tree",
    description:
      "Rows that nest under a parent row of the same table, for folders and categories.",
    base: "categories",
    table: { columns: { name: { type: "text", nullable: false } } },
  },
];

/** The table of a primitive under its final name: a tree's `parent_id` references the table itself. */
function tableOf(primitive: Primitive, name: string, idType: string): AppTable {
  const id = idType === "bigint" ? "bigint" : "uuid";

  const table: AppTable =
    id === "bigint" ? { ...primitive.table, id } : primitive.table;

  if (primitive.kind !== "tree") {
    return table;
  }

  return {
    ...table,
    columns: {
      ...table.columns,
      parent_id: {
        type: id,
        references: { table: name, onDelete: "cascade" },
      },
    },
  };
}

export function isPrimitiveKind(value: string): value is PrimitiveKind {
  return PRIMITIVES.some((primitive) => primitive.kind === value);
}

export interface AddedPrimitive {
  readonly design: Design;
  /** The name the new table got. */
  readonly name: string;
}

/**
 * Adds an app table of one kind at a top-left corner, under the first free
 * name. A preset with bigint ids gives the table a bigint id.
 */
export function addPrimitive(
  design: Design,
  taken: ReadonlySet<string>,
  kind: PrimitiveKind,
  position: readonly [number, number],
  idType = "uuid",
): AddedPrimitive {
  const primitive =
    PRIMITIVES.find((each) => each.kind === kind) ?? PRIMITIVES[0];

  if (primitive === undefined) {
    return { design, name: "" };
  }

  const name = freeTableName(design, taken, primitive.base);

  return {
    design: addTable(design, name, tableOf(primitive, name, idType), position),
    name,
  };
}
