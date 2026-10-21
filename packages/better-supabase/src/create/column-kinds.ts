import type {
  AppColumn,
  AppColumnType,
  Design,
  NamedDesign,
} from "./design.ts";

import { fitted, withBounds } from "./column-keys.ts";
import { renameColumn, setColumn } from "./design.ts";

/** The groups of the column type picker, in the order it shows them. */
export const KIND_GROUPS = [
  "Text",
  "Number",
  "Date and time",
  "Choice",
  "Relation",
  "Other",
] as const;

export type KindGroup = (typeof KIND_GROUPS)[number];

/**
 * A choice in the column type picker: a Postgres type with the format, options,
 * identity or reference that make it, say, an email or a rating.
 */
export interface ColumnKind {
  readonly id: string;
  readonly label: string;
  readonly group: KindGroup;
  /** What the canvas shows next to the column name. */
  readonly short: string;
  /** The keys the kind sets; the rest of the column is kept where it fits. */
  readonly column: AppColumn;
  /** Set for kinds the picker shows but a drag from the table's handle makes. */
  readonly drawn?: true;
}

const USERS = "auth.users";

/** The first options a new select gets, for the user to rename. */
const STARTER_OPTIONS = ["Option A", "Option B"];

export const COLUMN_KINDS: readonly ColumnKind[] = [
  {
    id: "text",
    label: "Text",
    group: "Text",
    short: "text",
    column: { type: "text" },
  },
  {
    id: "long_text",
    label: "Long text",
    group: "Text",
    short: "long text",
    column: { type: "text", format: "long_text" },
  },
  {
    id: "email",
    label: "Email",
    group: "Text",
    short: "email",
    column: { type: "text", format: "email" },
  },
  {
    id: "url",
    label: "URL",
    group: "Text",
    short: "url",
    column: { type: "text", format: "url" },
  },
  {
    id: "phone",
    label: "Phone",
    group: "Text",
    short: "phone",
    column: { type: "text", format: "phone" },
  },
  {
    id: "color",
    label: "Color",
    group: "Text",
    short: "color",
    column: { type: "text", format: "color" },
  },
  {
    id: "integer",
    label: "Whole number",
    group: "Number",
    short: "integer",
    column: { type: "integer" },
  },
  {
    id: "bigint",
    label: "Large whole number",
    group: "Number",
    short: "bigint",
    column: { type: "bigint" },
  },
  {
    id: "numeric",
    label: "Decimal",
    group: "Number",
    short: "numeric",
    column: { type: "numeric" },
  },
  {
    id: "rating",
    label: "Rating",
    group: "Number",
    short: "rating",
    column: { type: "integer", format: "rating" },
  },
  {
    id: "percent",
    label: "Percent",
    group: "Number",
    short: "percent",
    column: { type: "numeric", format: "percent" },
  },
  {
    id: "currency",
    label: "Currency",
    group: "Number",
    short: "money",
    column: { type: "bigint", format: "currency" },
  },
  {
    id: "autonumber",
    label: "Autonumber",
    group: "Number",
    short: "autonumber",
    column: { type: "bigint", identity: true },
  },
  {
    id: "date",
    label: "Date",
    group: "Date and time",
    short: "date",
    column: { type: "date" },
  },
  {
    id: "timestamptz",
    label: "Date and time",
    group: "Date and time",
    short: "timestamptz",
    column: { type: "timestamptz" },
  },
  {
    id: "boolean",
    label: "Yes or no",
    group: "Choice",
    short: "boolean",
    column: { type: "boolean" },
  },
  {
    id: "single_select",
    label: "Single select",
    group: "Choice",
    short: "select",
    column: { type: "text", options: STARTER_OPTIONS },
  },
  {
    id: "multi_select",
    label: "Multi-select",
    group: "Choice",
    short: "multi-select",
    column: { type: "text[]", options: STARTER_OPTIONS },
  },
  {
    id: "person",
    label: "Person",
    group: "Relation",
    short: "person",
    column: {
      type: "uuid",
      nullable: true,
      references: { table: USERS, onDelete: "set null" },
    },
  },
  {
    id: "reference",
    label: "Link to a table",
    group: "Relation",
    short: "link",
    column: { type: "uuid" },
    drawn: true,
  },
  {
    id: "uuid",
    label: "UUID",
    group: "Other",
    short: "uuid",
    column: { type: "uuid" },
  },
  {
    id: "jsonb",
    label: "JSON",
    group: "Other",
    short: "jsonb",
    column: { type: "jsonb" },
  },
  {
    id: "text_list",
    label: "List of text",
    group: "Other",
    short: "text[]",
    column: { type: "text[]" },
  },
];

const BY_ID = new Map(COLUMN_KINDS.map((kind) => [kind.id, kind]));

const BY_FORMAT = new Map(
  COLUMN_KINDS.filter((kind) => kind.column.format !== undefined).map(
    (kind) => [kind.column.format, kind],
  ),
);

const PLAIN: Readonly<Record<AppColumnType, string>> = {
  text: "text",
  uuid: "uuid",
  integer: "integer",
  bigint: "bigint",
  numeric: "numeric",
  boolean: "boolean",
  timestamptz: "timestamptz",
  date: "date",
  jsonb: "jsonb",
  "text[]": "text_list",
};

export function kindById(id: string): ColumnKind | undefined {
  return BY_ID.get(id);
}

/**
 * The kind a column's identity, reference or options make it, before its format
 * and type.
 */
function structuralKind(column: AppColumn): string | undefined {
  if (column.identity === true) {
    return "autonumber";
  }

  if (column.references !== undefined) {
    return column.references.block === undefined &&
      column.references.table === USERS
      ? "person"
      : "reference";
  }

  if (column.options === undefined) {
    return undefined;
  }

  return column.type === "text[]" ? "multi_select" : "single_select";
}

/** The picker choice a column reads as. */
export function kindOf(column: AppColumn): ColumnKind {
  const id = structuralKind(column);

  const kind =
    (id === undefined ? undefined : BY_ID.get(id)) ??
    (column.format === undefined ? undefined : BY_FORMAT.get(column.format)) ??
    BY_ID.get(PLAIN[column.type]);

  // SAFETY: PLAIN names a kind for every column type.
  return kind!;
}

/**
 * `column` as `kind`: the kind's keys, with the column's name-independent
 * settings (required, unique, comment, a default and bounds that still fit)
 * kept, and a select's options kept when it turns into the other select.
 */
export function withKind(column: AppColumn, kind: ColumnKind): AppColumn {
  const {
    format: _format,
    options,
    identity: _identity,
    references: _references,
    min,
    max,
    ...rest
  } = column;

  const kept =
    kind.column.options === undefined || options === undefined
      ? kind.column
      : { ...kind.column, options };

  return fitted(
    withBounds(
      { ...rest, ...kept },
      column.type === kind.column.type ? { min, max } : {},
    ),
  );
}

/** The two columns a currency amount is stored in (ADR 0037). */
interface MoneyColumns {
  readonly minor: string;
  readonly currency: string;
}

/** The money columns of `name`: `<stem>_minor` and `<stem>_currency`. */
function moneyColumns(name: string): MoneyColumns {
  const stem = name.replace(/_minor$/u, "");

  return { minor: `${stem}_minor`, currency: `${stem}_currency` };
}

/**
 * Sets an app table column to `kind`. Currency keeps money as two columns: the
 * column becomes `<name>_minor` (unless the name is taken) and a
 * `<name>_currency` text column of 3 characters joins it. Returns the column's
 * name after the change.
 */
export function setColumnKind(
  design: Design,
  table: string,
  name: string,
  kind: ColumnKind,
): NamedDesign {
  const columns = design.appTables?.[table]?.columns ?? {};
  const column = columns[name];

  if (column === undefined) {
    return { design, name };
  }

  const next = withKind(column, kind);

  if (kind.id !== "currency") {
    return { design: setColumn(design, table, name, next), name };
  }

  const { minor, currency } = moneyColumns(name);

  const renamed = minor === name || columns[minor] === undefined ? minor : name;

  const moved = setColumn(
    renameColumn(design, table, name, renamed),
    table,
    renamed,
    next,
  );

  if (columns[currency] !== undefined) {
    return { design: moved, name: renamed };
  }

  const code: AppColumn =
    next.nullable === false
      ? { type: "text", nullable: false, min: 3, max: 3 }
      : { type: "text", min: 3, max: 3 };

  return { design: setColumn(moved, table, currency, code), name: renamed };
}
