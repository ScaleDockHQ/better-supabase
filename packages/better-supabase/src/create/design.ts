import type {
  AppColumnAccess,
  AppColumnType,
  AppOnDeleteAction as OnDeleteAction,
} from "../config/index.ts";
import type { AppColumnFormat, Preset } from "../preset/index.ts";
import type { AppLookup, AppRollup } from "./design-computed.ts";
import type { AppEvents, AppSubject } from "./design-subject.ts";
import type { SchemaColumn, SchemaData, SchemaTable } from "./schema.ts";

import {
  appDefaultError,
  appIdentifierError,
  appReservedColumns,
} from "../preset/index.ts";
import { columnLabel, fitted } from "./column-keys.ts";
import {
  computedColumnRenamed,
  computedRows,
  computedTableRenamed,
  prunedComputed,
} from "./design-computed.ts";
import { AUTH_USERS, scopeColumnOf } from "./design-scope.ts";
import {
  eventsColumnsEdited,
  subjectColumns,
  subjectColumnsEdited,
} from "./design-subject.ts";

export { APP_ON_DELETE_ACTIONS as ON_DELETE_ACTIONS } from "../config/index.ts";

export type { AppColumnAccess, AppColumnType, OnDeleteAction };

/**
 * Another app table or `auth.users` (`{ table }`), or a block module's logical
 * table (`{ block, table }`).
 */
export interface AppReference {
  readonly table: string;
  readonly block?: string;
  readonly onDelete?: OnDeleteAction;
}

export interface AppColumn {
  readonly type: AppColumnType;
  readonly nullable?: boolean;
  readonly default?: string;
  readonly unique?: boolean;
  readonly references?: AppReference;
  readonly format?: AppColumnFormat;
  readonly options?: readonly string[];
  readonly min?: number;
  readonly max?: number;
  readonly comment?: string;
  readonly identity?: boolean;
  /**
   * Who reads and writes the column: everyone by default, `read`, or `server`
   * (ADR 0051).
   */
  readonly access?: AppColumnAccess;
  /**
   * Stores ciphertext with the tenant's Vault key; read through
   * `<table>_reveal`.
   */
  readonly encrypted?: boolean;
}

export type AppScope = "inherit" | "user" | "none";

export type AppTableId = "uuid" | "bigint";

export interface AppTable {
  readonly columns?: Readonly<Record<string, AppColumn>>;
  readonly scope?: AppScope;
  readonly timestamps?: boolean;
  readonly id?: AppTableId;
  readonly unique?: readonly (readonly string[])[];
  readonly indexes?: readonly (readonly string[])[];
  readonly comment?: string;
  readonly subject?: AppSubject;
  readonly rollups?: Readonly<Record<string, AppRollup>>;
  readonly lookups?: Readonly<Record<string, AppLookup>>;
  /** Outbox events on insert, update and delete; the shape of `AppTableEvents`. */
  readonly events?: true | AppEvents;
  /** One `read` audit entry per tenant per reveal call. */
  readonly auditReads?: boolean;
}

/**
 * What the canvas adds to a preset: app tables, extra columns on block tables
 * (by module) and the positions of moved tables (by table id). It has the shape
 * of `CreateDesign` from `better-supabase/preset`.
 */
export interface Design {
  readonly appTables?: Readonly<Record<string, AppTable>>;
  readonly extraColumns?: Readonly<
    Record<string, Readonly<Record<string, string>>>
  >;
  readonly positions?: Readonly<Record<string, readonly [number, number]>>;
}

export const EMPTY_DESIGN: Design = {};

/** The schema app tables go in. */
const APP_SCHEMA = "public";

/** The module name app tables carry in the diagram. */
export const APP_MODULE = "app-tables";

/** Column names every app table creates itself. */
const IMPLICIT_COLUMNS = new Set(["id", "created_at", "updated_at"]);

export function appTableId(name: string): string {
  return `${APP_SCHEMA}.${name}`;
}

export function isAppTable(table: Pick<SchemaTable, "module">): boolean {
  return table.module === APP_MODULE;
}

export function isEmptyDesign(design: Design): boolean {
  return (
    Object.keys(design.appTables ?? {}).length === 0 &&
    Object.keys(design.extraColumns ?? {}).length === 0 &&
    Object.keys(design.positions ?? {}).length === 0
  );
}

/** Why `name` can't name an app table or column, by the library's rules. */
export function identifierError(name: string): string | undefined {
  return appIdentifierError(name);
}

/** The names of an app table's columns, its implicit ones included. */
function columnNamesOf(
  table: AppTable,
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
): readonly string[] {
  const scope = scopeColumnOf(table, preset);

  return [
    "id",
    ...(scope === null ? [] : [scope.name]),
    ...Object.keys(table.columns ?? {}),
    ...(table.timestamps === false ? [] : ["created_at", "updated_at"]),
    ...computedRows(table).map((row) => row.name),
  ];
}

/** Why a column can't be added to an app table, or `undefined` when it can. */
export function columnError(
  table: AppTable,
  name: string,
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
): string | undefined {
  const invalid = identifierError(name);

  if (invalid !== undefined) {
    return invalid;
  }

  if (
    IMPLICIT_COLUMNS.has(name) ||
    columnNamesOf(table, preset).includes(name)
  ) {
    return `The table already has a ${name} column.`;
  }

  if (appReservedColumns(preset.tenantName).includes(name)) {
    return `${name} is a column every app table can get from its scope. Choose another name.`;
  }

  return undefined;
}

/**
 * Why `value` can't be the default of `column` (its type, options and bounds),
 * or `undefined` when it can or is empty.
 */
export function defaultError(
  column: Pick<AppColumn, "type" | "options" | "min" | "max" | "format">,
  value: string,
): string | undefined {
  const trimmed = value.trim();

  return trimmed === "" ? undefined : appDefaultError(column, trimmed);
}

/** A column with its type changed, dropping the keys the new type can't take. */
function retyped(column: AppColumn, type: AppColumnType): AppColumn {
  return fitted({ ...column, type });
}

/** A free app table name: `base`, then `base_2`, `base_3` and so on. */
export function freeTableName(
  design: Design,
  taken: ReadonlySet<string>,
  base = "items",
): string {
  const used = (name: string): boolean =>
    taken.has(appTableId(name)) || design.appTables?.[name] !== undefined;

  if (!used(base)) {
    return base;
  }

  let index = 2;

  while (used(`${base}_${index}`)) {
    index += 1;
  }

  return `${base}_${index}`;
}

function withAppTables(
  design: Design,
  appTables: Readonly<Record<string, AppTable>>,
): Design {
  const { appTables: _drop, ...rest } = design;

  return Object.keys(appTables).length === 0
    ? rest
    : { ...rest, appTables: prunedComputed(appTables) };
}

function withPositions(
  design: Design,
  positions: Readonly<Record<string, readonly [number, number]>>,
): Design {
  const { positions: _drop, ...rest } = design;

  return Object.keys(positions).length === 0 ? rest : { ...rest, positions };
}

function omitKey<T>(
  record: Readonly<Record<string, T>> | undefined,
  key: string,
): Record<string, T> {
  const { [key]: _drop, ...rest } = record ?? {};

  return rest;
}

/** Adds an app table, placed at `position` when given. */
export function addTable(
  design: Design,
  name: string,
  table: AppTable = {},
  position?: readonly [number, number],
): Design {
  const next = withAppTables(design, { ...design.appTables, [name]: table });

  return position === undefined
    ? next
    : withPositions(next, { ...next.positions, [appTableId(name)]: position });
}

/**
 * Removes an app table, every app table column that references it (and those
 * columns from key sets), and the rollups and lookups that read it.
 */
export function deleteTable(design: Design, name: string): Design {
  const rest = omitKey(design.appTables, name);

  const appTables = Object.fromEntries(
    Object.entries(rest).map(([key, table]) => {
      const dropped = new Set(
        Object.entries(table.columns ?? {})
          .filter(
            ([, column]) =>
              column.references?.block === undefined &&
              column.references?.table === name,
          )
          .map(([column]) => column),
      );

      return [
        key,
        dropped.size === 0
          ? table
          : withKeySets(
              {
                ...table,
                columns: Object.fromEntries(
                  Object.entries(table.columns ?? {}).filter(
                    ([column]) => !dropped.has(column),
                  ),
                ),
              },
              (columns) => columns.filter((column) => !dropped.has(column)),
            ),
      ];
    }),
  );

  return withPositions(
    withAppTables(design, appTables),
    omitKey(design.positions, appTableId(name)),
  );
}

/** Renames an app table and the references to it. */
export function renameTable(design: Design, from: string, to: string): Design {
  if (from === to || design.appTables?.[from] === undefined) {
    return design;
  }

  const appTables = Object.fromEntries(
    Object.entries(design.appTables).map(([key, table]) => [
      key === from ? to : key,
      {
        ...table,
        columns: Object.fromEntries(
          Object.entries(table.columns ?? {}).map(([name, column]) => [
            name,
            column.references?.block === undefined &&
            column.references?.table === from
              ? { ...column, references: { ...column.references, table: to } }
              : column,
          ]),
        ),
      },
    ]),
  );

  const position = design.positions?.[appTableId(from)];
  const positions = omitKey(design.positions, appTableId(from));

  return withPositions(
    withAppTables(design, computedTableRenamed(appTables, from, to)),
    position === undefined
      ? positions
      : { ...positions, [appTableId(to)]: position },
  );
}

export type TablePatch = {
  readonly [
    K in
      | "scope"
      | "timestamps"
      | "id"
      | "unique"
      | "indexes"
      | "comment"
      | "subject"
      | "events"
  ]?: AppTable[K] | undefined;
};

const TABLE_PATCH_KEYS = [
  "scope",
  "timestamps",
  "id",
  "unique",
  "indexes",
  "comment",
  "subject",
  "events",
] as const;

/** An app table under construction. */
type DraftTable = { -readonly [K in keyof AppTable]: AppTable[K] };

function patchKey<K extends (typeof TABLE_PATCH_KEYS)[number]>(
  next: DraftTable,
  patch: TablePatch,
  key: K,
): void {
  if (!(key in patch)) {
    return;
  }

  const value = patch[key];

  if (value === undefined) {
    delete next[key];
  } else {
    next[key] = value;
  }
}

/** Updates an app table's options; a key set to `undefined` is removed. */
export function updateTable(
  design: Design,
  name: string,
  patch: TablePatch,
): Design {
  const table = design.appTables?.[name];

  if (table === undefined) {
    return design;
  }

  const next: DraftTable = { ...table };

  for (const key of TABLE_PATCH_KEYS) {
    patchKey(next, patch, key);
  }

  return withAppTables(design, { ...design.appTables, [name]: next });
}

/**
 * Sets an app table's id type and retypes the app table columns that reference
 * it, since a key has the type of the id it points at.
 */
export function setTableId(
  design: Design,
  name: string,
  id: AppTableId,
): Design {
  const next = updateTable(design, name, {
    id: id === "uuid" ? undefined : id,
  });

  return withAppTables(
    next,
    Object.fromEntries(
      Object.entries(next.appTables ?? {}).map(([key, table]) => [
        key,
        {
          ...table,
          columns: Object.fromEntries(
            Object.entries(table.columns ?? {}).map(([column, config]) => [
              column,
              config.references?.block === undefined &&
              config.references?.table === name
                ? retyped(config, id)
                : config,
            ]),
          ),
        },
      ]),
    ),
  );
}

/**
 * A table's composite key sets with `edit` applied to each, dropping empty sets
 * and an empty list.
 */
function withKeySets(
  table: AppTable,
  edit: (columns: readonly string[]) => readonly string[],
): AppTable {
  const { unique, indexes, ...rest } = table;

  const sets = (
    list: readonly (readonly string[])[] | undefined,
  ): readonly (readonly string[])[] | undefined => {
    const next = (list ?? []).map(edit).filter((columns) => columns.length > 0);

    return next.length === 0 ? undefined : next;
  };

  const next: DraftTable = { ...rest };
  const nextUnique = sets(unique);

  if (rest.subject !== undefined) {
    next.subject = subjectColumnsEdited(rest.subject, edit);
  }

  if (rest.events !== undefined) {
    next.events = eventsColumnsEdited(rest.events, edit);
  }

  const nextIndexes = sets(indexes);

  if (nextUnique !== undefined) {
    next.unique = nextUnique;
  }

  if (nextIndexes !== undefined) {
    next.indexes = nextIndexes;
  }

  return next;
}

/** Sets (adds or replaces) an app table column. */
export function setColumn(
  design: Design,
  table: string,
  name: string,
  column: AppColumn,
): Design {
  const current = design.appTables?.[table];

  return current === undefined
    ? design
    : withAppTables(design, {
        ...design.appTables,
        [table]: {
          ...current,
          columns: { ...current.columns, [name]: column },
        },
      });
}

/** Renames an app table column, keeping its place. */
export function renameColumn(
  design: Design,
  table: string,
  from: string,
  to: string,
): Design {
  const current = design.appTables?.[table];

  if (current === undefined || from === to) {
    return design;
  }

  return withAppTables(
    design,
    computedColumnRenamed(
      {
        ...design.appTables,
        [table]: withKeySets(
          {
            ...current,
            columns: Object.fromEntries(
              Object.entries(current.columns ?? {}).map(([name, column]) => [
                name === from ? to : name,
                column,
              ]),
            ),
          },
          (columns) => columns.map((column) => (column === from ? to : column)),
        ),
      },
      table,
      from,
      to,
    ),
  );
}

/** Replaces an app table with `edit` applied to it, such as `tableWithComputed`. */
export function editTable(
  design: Design,
  table: string,
  edit: (current: AppTable) => AppTable,
): Design {
  const current = design.appTables?.[table];

  return current === undefined
    ? design
    : withAppTables(design, { ...design.appTables, [table]: edit(current) });
}

export function deleteColumn(
  design: Design,
  table: string,
  name: string,
): Design {
  const current = design.appTables?.[table];

  return current === undefined
    ? design
    : withAppTables(design, {
        ...design.appTables,
        [table]: withKeySets(
          { ...current, columns: omitKey(current.columns, name) },
          (columns) => columns.filter((column) => column !== name),
        ),
      });
}

/**
 * Sets an extra column on a block table
 * (`blocks.<module>.options.extraColumns`).
 */
export function setExtraColumn(
  design: Design,
  module: string,
  name: string,
  type: string,
): Design {
  return {
    ...design,
    extraColumns: {
      ...design.extraColumns,
      [module]: { ...design.extraColumns?.[module], [name]: type },
    },
  };
}

export function deleteExtraColumn(
  design: Design,
  module: string,
  name: string,
): Design {
  const columns = omitKey(design.extraColumns?.[module], name);
  const { extraColumns: _drop, ...rest } = design;

  const extraColumns =
    Object.keys(columns).length === 0
      ? omitKey(design.extraColumns, module)
      : { ...design.extraColumns, [module]: columns };

  return Object.keys(extraColumns).length === 0
    ? rest
    : { ...rest, extraColumns };
}

/** A design with the name of the table an edit created. */
export interface NamedDesign {
  readonly design: Design;
  readonly name: string;
}

/** Copies an app table under a free name, next to the original. */
export function duplicateTable(
  design: Design,
  name: string,
  taken: ReadonlySet<string>,
): NamedDesign {
  const table = design.appTables?.[name];

  if (table === undefined) {
    return { design, name };
  }

  const copy = freeTableName(design, taken, `${name}_copy`);
  const position = design.positions?.[appTableId(name)];

  return {
    design: addTable(
      design,
      copy,
      table.subject === undefined
        ? table
        : { ...table, subject: { ...table.subject, type: singular(copy) } },
      position === undefined ? undefined : [position[0] + 40, position[1] + 40],
    ),
    name: copy,
  };
}

/** Moves tables (table id to its new top-left corner). */
export function moveTables(
  design: Design,
  moves: Readonly<Record<string, readonly [number, number]>>,
): Design {
  return withPositions(design, { ...design.positions, ...moves });
}

/**
 * The app table column behind a foreign key from `tableId`, when the canvas
 * added it, or `undefined` when a block or the preset owns the key.
 */
export function userConnection(
  design: Design,
  tableId: string,
  column: string | null,
): { readonly table: string; readonly column: string } | undefined {
  const name = Object.keys(design.appTables ?? {}).find(
    (each) => appTableId(each) === tableId,
  );

  if (name === undefined || column === null) {
    return undefined;
  }

  return design.appTables?.[name]?.columns?.[column]?.references === undefined
    ? undefined
    : { table: name, column };
}

/** Drops every saved position, so the automatic layout places every table again. */
export function tidy(design: Design): Design {
  return withPositions(design, {});
}

const SINGULAR_ENDINGS: readonly (readonly [RegExp, string])[] = [
  [/ies$/u, "y"],
  [/(ss|us)$/u, "$1"],
  [/s$/u, ""],
];

/** A naive English singular for a table name: `organizations` to `organization`. */
export function singular(name: string): string {
  for (const [ending, replacement] of SINGULAR_ENDINGS) {
    if (ending.test(name)) {
      return name.replace(ending, replacement);
    }
  }

  return name;
}

/**
 * The column types a foreign key can point at, from the target's primary key
 * type.
 */
function referenceType(type: string): AppColumnType | undefined {
  const normal = type.toLowerCase();

  switch (normal) {
    case "uuid":
    case "text":
    case "bigint":
    case "integer": {
      return normal;
    }

    case "int8":
    case "bigserial": {
      return "bigint";
    }

    case "int":
    case "int4":
    case "serial": {
      return "integer";
    }

    default: {
      return undefined;
    }
  }
}

export interface Connection {
  /** The app table the column goes on. */
  readonly source: string;
  /** The table id it references. */
  readonly target: string;
}

export type ConnectResult =
  | { readonly ok: true; readonly design: Design; readonly column: string }
  | { readonly ok: false; readonly error: string };

/**
 * Adds a foreign key column from an app table to `target`. Only app tables get
 * new columns. A self reference gets `parent_id`, and a second reference to the
 * same table gets a role name (`owner_id`, `<target>_2_id`) the user can
 * rename. A target without a single-column primary key, and the tenant table
 * the scope column already references, are refused with a message.
 */
export function connect(
  design: Design,
  data: SchemaData,
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
  connection: Connection,
): ConnectResult {
  const source = data.tables.find((table) => table.id === connection.source);

  if (source === undefined || !isAppTable(source)) {
    return {
      ok: false,
      error: "Block tables only accept connections. Drag from an app table.",
    };
  }

  if (design.appTables?.[source.name] === undefined) {
    return { ok: false, error: `${source.name} is not in the design.` };
  }

  if (source.tenantColumn !== null && connection.target === data.tenantTable) {
    return {
      ok: false,
      error: `${source.name} already references ${connection.target} through ${source.tenantColumn}.`,
    };
  }

  return referenceFrom(design, data, preset, source.name, connection.target);
}

/** Second references to `auth.users`, in the order they are offered. */
const USER_ROLES = ["owner_id", "assignee_id", "reviewer_id", "approver_id"];

/** The first column name for a reference that the table can still take. */
function referenceColumn(
  table: AppTable,
  base: string,
  roles: readonly string[],
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
): string | undefined {
  const stem = base.replace(/_id$/u, "");

  const candidates = [
    base,
    ...roles,
    ...Array.from({ length: 8 }, (_, index) => `${stem}_${index + 2}_id`),
  ];

  return candidates.find(
    (candidate) => columnError(table, candidate, preset) === undefined,
  );
}

/**
 * Adds a key to `targetId` on the app table `name` in the design, which can be
 * a table the schema doesn't have yet: `<target>_id`, `parent_id` for a self
 * reference, or a free role name when that column is taken.
 */
export function referenceFrom(
  design: Design,
  data: SchemaData,
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
  name: string,
  targetId: string,
): ConnectResult {
  const table = design.appTables?.[name];

  if (table === undefined) {
    return { ok: false, error: `${name} is not in the design.` };
  }

  const target =
    targetId === AUTH_USERS
      ? undefined
      : data.tables.find((each) => each.id === targetId);

  if (targetId !== AUTH_USERS && target === undefined) {
    return { ok: false, error: "That table is not in the schema." };
  }

  const keyType =
    target === undefined
      ? "uuid"
      : target.primaryKey.length === 1
        ? target.columns.find((column) => column.name === target.primaryKey[0])
            ?.type
        : undefined;

  const type = keyType === undefined ? undefined : referenceType(keyType);

  if (type === undefined) {
    return {
      ok: false,
      error: `${targetId} has no single uuid, text or integer key to reference.`,
    };
  }

  const references: AppReference | undefined =
    target === undefined
      ? { table: AUTH_USERS }
      : isAppTable(target)
        ? { table: target.name }
        : data.blockTables[target.id];

  if (references === undefined) {
    return {
      ok: false,
      error: `${targetId} can't be referenced from an app table.`,
    };
  }

  const self = targetId === appTableId(name);
  const user = target === undefined;

  const base = self
    ? "parent_id"
    : `${singular(user ? "user" : target.name)}_id`;

  const column = referenceColumn(table, base, user ? USER_ROLES : [], preset);

  if (column === undefined) {
    return {
      ok: false,
      error: `${name} already has every column name a reference to ${targetId} gets. Rename one first.`,
    };
  }

  return {
    ok: true,
    column,
    design: setColumn(design, name, column, {
      type,
      nullable: true,
      references: {
        ...references,
        onDelete: self || user ? "set null" : "cascade",
      },
    }),
  };
}

function appColumn(name: string, column: AppColumn): SchemaColumn {
  const label = columnLabel(column);

  const schemaColumn: SchemaColumn = {
    name,
    type: column.type,
    nullable: column.identity === true ? false : (column.nullable ?? true),
    default: column.identity === true ? "identity" : (column.default ?? null),
    unique: column.unique ?? false,
  };

  return label === undefined ? schemaColumn : { ...schemaColumn, label };
}

const TIMESTAMP: Omit<SchemaColumn, "name"> = {
  type: "timestamptz",
  nullable: false,
  default: "now()",
  unique: false,
};

/**
 * The id of the table a reference points at, or `undefined` when it is not in
 * the schema.
 */
function referencedId(
  reference: AppReference,
  data: SchemaData,
): string | undefined {
  if (reference.block === undefined) {
    return reference.table === AUTH_USERS
      ? AUTH_USERS
      : appTableId(reference.table);
  }

  return Object.entries(data.blockTables).find(
    ([, each]) =>
      each.block === reference.block && each.table === reference.table,
  )?.[0];
}

function foreignKey(
  column: string,
  to: string,
  onDelete = "no action",
): SchemaTable["foreignKeys"][number] {
  const [schema = "", target = ""] = to.split(".");

  return {
    columns: [column],
    target: { schema, table: target, columns: [] },
    onDelete,
  };
}

/** An app table as the diagram reads it. */
function appSchemaTable(
  name: string,
  table: AppTable,
  data: SchemaData,
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
): SchemaTable {
  const scope = scopeColumnOf(table, preset);

  const scopeTo =
    scope === null
      ? undefined
      : scope.name === "user_id"
        ? AUTH_USERS
        : (data.tenantTable ?? undefined);

  const columns: SchemaColumn[] = [
    table.id === "bigint"
      ? {
          name: "id",
          type: "bigint",
          nullable: false,
          default: "identity",
          unique: false,
        }
      : {
          name: "id",
          type: "uuid",
          nullable: false,
          default: "gen_random_uuid()",
          unique: false,
        },
    ...(scope === null ? [] : [scope]),
    ...Object.entries(table.columns ?? {}).map(([key, column]) =>
      appColumn(key, column),
    ),
    ...subjectColumns(table.subject),
    ...(table.timestamps === false
      ? []
      : [
          { name: "created_at", ...TIMESTAMP },
          { name: "updated_at", ...TIMESTAMP },
        ]),
  ];

  const scopeKeys =
    scope === null || scopeTo === undefined
      ? []
      : [foreignKey(scope.name, scopeTo, "cascade")];

  const columnKeys = Object.entries(table.columns ?? {}).flatMap(
    ([key, column]) => {
      const to =
        column.references === undefined
          ? undefined
          : referencedId(column.references, data);

      return to === undefined
        ? []
        : [foreignKey(key, to, column.references?.onDelete)];
    },
  );

  const schemaTable: SchemaTable = {
    id: appTableId(name),
    schema: APP_SCHEMA,
    name,
    module: APP_MODULE,
    primaryKey: ["id"],
    foreignKeys: [...scopeKeys, ...columnKeys],
    tenantColumn:
      scope !== null && scope.name !== "user_id" ? scope.name : null,
    columns,
  };

  const computed = computedRows(table);

  return computed.length === 0 ? schemaTable : { ...schemaTable, computed };
}

/** The extra column names a block table got from the design. */
function extraColumnsOf(
  design: Design,
  table: SchemaTable,
  data: SchemaData,
): Readonly<Record<string, string>> {
  return data.extraColumns.includes(table.id)
    ? (design.extraColumns?.[table.module] ?? {})
    : {};
}

/**
 * The schema with the design applied: app tables added, extra columns appended
 * to the block tables that accept them.
 */
export function withDesign(
  data: SchemaData,
  design: Design,
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
): SchemaData {
  const tables = data.tables.map((table) => {
    const extra = extraColumnsOf(design, table, data);
    const names = new Set(table.columns.map((column) => column.name));

    const added = Object.entries(extra)
      .filter(([name]) => !names.has(name))
      .map(([name, type]) => ({
        name,
        type,
        nullable: !/\bnot\s+null\b/iu.test(type),
        default: null,
        unique: false,
      }));

    return added.length === 0
      ? table
      : { ...table, columns: [...table.columns, ...added] };
  });

  const appTables = Object.entries(design.appTables ?? {}).map(
    ([name, table]) => appSchemaTable(name, table, data, preset),
  );

  return {
    ...data,
    tables: [...tables, ...appTables],
    manifests: {
      ...data.manifests,
      ...Object.fromEntries(appTables.map((table) => [table.id, APP_MODULE])),
    },
  };
}
