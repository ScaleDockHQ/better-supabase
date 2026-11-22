/** A column a `create table` or `alter table ... add column` declares. */
export interface ColumnFact {
  readonly name: string;
  /** The type as written, lower-cased with its spacing collapsed. */
  readonly type: string;
  /** `not null` or `primary key` on the column itself. */
  readonly notNull: boolean;
  readonly hasDefault: boolean;
}

export interface ForeignKeyFact {
  readonly name: string | undefined;
  readonly columns: readonly string[];
  /** `schema.table` the key points at. */
  readonly references: string;
  readonly referencedColumns: readonly string[];
  readonly deferrable: boolean;
  readonly initiallyDeferred: boolean;
  readonly match: "simple" | "full" | "partial";
  readonly onDelete: string;
  readonly onUpdate: string;
}

export interface CheckFact {
  readonly name: string | undefined;
  /** Columns the expression names, in source order, without repeats. */
  readonly columns: readonly string[];
  /** The expression as written. */
  readonly expression: string;
}

export interface TableFact {
  /** `schema.table`, unquoted. */
  readonly name: string;
  readonly line: number;
  /** Position among the file's statements, for create-then-drop order. */
  readonly index: number;
  readonly ifNotExists: boolean;
  readonly temporary: boolean;
  readonly unlogged: boolean;
  /** A `partition of` or `inherits` table has columns from elsewhere. */
  readonly partitionOf: string | undefined;
  /** The columns come from `(like ...)` or `create table as`. */
  readonly columnsElsewhere: boolean;
  readonly columns: readonly ColumnFact[];
  readonly primaryKey: readonly string[];
  readonly foreignKeys: readonly ForeignKeyFact[];
  readonly checks: readonly CheckFact[];
}

export interface AlterFact {
  readonly table: string;
  readonly line: number;
  readonly index: number;
  readonly addedColumns: readonly ColumnFact[];
  readonly setNotNull: readonly string[];
  readonly dropNotNull: readonly string[];
  readonly droppedColumns: readonly string[];
  readonly addedForeignKeys: readonly ForeignKeyFact[];
  readonly addedChecks: readonly CheckFact[];
  readonly enablesRls: boolean;
}

export type DropKind =
  | "table"
  | "view"
  | "index"
  | "type"
  | "function"
  | "policy"
  | "trigger"
  | "other";

export interface DropFact {
  readonly kind: DropKind;
  /** `schema.name`; a policy or trigger is `schema.table.name`. */
  readonly name: string;
  readonly index: number;
}

export interface EnumFact {
  readonly name: string;
  readonly labels: readonly string[];
  readonly line: number;
}

export interface ViewFact {
  readonly name: string;
  readonly line: number;
  readonly index: number;
  readonly materialized: boolean;
  readonly replace: boolean;
  /** Declared column aliases, or `undefined` when the select decides. */
  readonly columnAliases: readonly string[] | undefined;
  /** The `security_invoker` option, when set. */
  readonly securityInvoker: boolean | undefined;
}

export interface IndexFact {
  readonly name: string | undefined;
  readonly table: string;
  readonly line: number;
  readonly index: number;
  readonly unique: boolean;
  readonly method: string;
  /** Each key part as written; an expression keeps its source text. */
  readonly keys: readonly string[];
  /** The `where` text as written, or `undefined`. */
  readonly predicate: string | undefined;
  readonly ifNotExists: boolean;
  /** The statement's source text, trimmed. */
  readonly text: string;
}

export interface PolicyFact {
  readonly name: string;
  readonly table: string;
  readonly line: number;
  readonly index: number;
  /** `all`, `select`, `insert`, `update` or `delete`. */
  readonly command: string;
  readonly permissive: boolean;
  /** Role names; empty means `public`. */
  readonly roles: readonly string[];
  readonly using: string | undefined;
  readonly withCheck: string | undefined;
  /** The statement after the table name, lower-cased, whitespace collapsed. */
  readonly terms: string;
}

export interface TriggerFact {
  readonly name: string;
  readonly table: string;
  readonly line: number;
  readonly index: number;
  /** `schema.function` the trigger runs. */
  readonly function: string;
  readonly text: string;
}

export interface FunctionFact {
  /** `schema.name`. */
  readonly name: string;
  /** Argument types as written, so overloads stay apart. */
  readonly signature: string;
  readonly line: number;
  readonly index: number;
  readonly ifNotExists: boolean;
  readonly procedure: boolean;
}

export type CommentTarget =
  | "table"
  | "column"
  | "view"
  | "function"
  | "type"
  | "schema"
  | "other";

export interface CommentFact {
  readonly target: CommentTarget;
  /** `schema.object`, plus `.column` for a column comment. */
  readonly name: string;
  /** For a function, its argument types as written. */
  readonly signature: string | undefined;
  /** The decoded comment text, whichever quoting the file used. */
  readonly text: string;
  readonly line: number;
}

export interface GrantFact {
  readonly grant: boolean;
  readonly privileges: readonly string[];
  readonly objectType: string;
  readonly objects: readonly string[];
  readonly roles: readonly string[];
  readonly index: number;
}

/** A named object a statement creates that has no richer fact. */
export interface ObjectFact {
  readonly kind: "sequence" | "schema" | "extension" | "type";
  readonly name: string;
  readonly line: number;
  readonly ifNotExists: boolean;
}

export interface MarkerFact {
  readonly kind: "bsb" | "pg-delta" | "rename";
  readonly text: string;
  readonly line: number;
}

/** What one SQL file declares. */
export interface FileFacts {
  readonly tables: readonly TableFact[];
  readonly alters: readonly AlterFact[];
  readonly drops: readonly DropFact[];
  readonly enums: readonly EnumFact[];
  readonly views: readonly ViewFact[];
  readonly indexes: readonly IndexFact[];
  readonly policies: readonly PolicyFact[];
  readonly triggers: readonly TriggerFact[];
  readonly functions: readonly FunctionFact[];
  readonly comments: readonly CommentFact[];
  readonly grants: readonly GrantFact[];
  readonly objects: readonly ObjectFact[];
  readonly markers: readonly MarkerFact[];
  /** Lines of `do` blocks. */
  readonly doBlocks: readonly number[];
  /** Lines of top-level `insert` statements. */
  readonly inserts: readonly number[];
  /** Lines of every statement, in order. */
  readonly statements: readonly {
    readonly line: number;
    readonly kind: string;
  }[];
  /** The file asks pg-delta for `transaction=false`. */
  readonly outsideTransaction: boolean;
}

/** A file that does not parse; `gen` and doctor stop with this. */
export interface SchemaReadError {
  readonly path: string;
  readonly message: string;
  readonly line: number;
  readonly column: number;
}
