/** A column a `create table` or `alter table ... add column` declares. */
export interface ColumnFact {
  readonly name: string;
  /** The type as written, lower-cased with its spacing collapsed. */
  readonly type: string;
  /** `not null` or `primary key` on the column itself. */
  readonly notNull: boolean;
  readonly hasDefault: boolean;
  /**
   * Everything after the name up to the comma that ends the column, as written
   * (quoting and case kept) with comments dropped and whitespace collapsed.
   */
  readonly definition: string;
}

/** A primary key or unique constraint, in the order the table lists them. */
export interface KeyFact {
  readonly columns: readonly string[];
  readonly primary: boolean;
  /** `unique nulls not distinct (...)`. */
  readonly nullsNotDistinct: boolean;
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
  /** Every primary key and unique constraint, column-level ones included. */
  readonly keys: readonly KeyFact[];
  readonly foreignKeys: readonly ForeignKeyFact[];
  readonly checks: readonly CheckFact[];
}

export interface AlterFact {
  readonly table: string;
  readonly line: number;
  readonly index: number;
  readonly addedColumns: readonly ColumnFact[];
  /** The added columns written `add column if not exists`, in order. */
  readonly addedIfNotExists: readonly string[];
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
  /**
   * The view's columns: its aliases, else the select list's names. `undefined`
   * when an item is `*` or has no name to read.
   */
  readonly columns: readonly string[] | undefined;
  /**
   * Whether `insert`, `update` and `delete` reach the table under it: not a
   * materialized view, and no distinct, group by, having, limit, offset, set
   * operation, window, join, aggregate or window function.
   */
  readonly updatable: boolean;
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
  /** The plain column names the index leads with, up to the first expression. */
  readonly columns: readonly string[];
  /** Every key is a column with no operator class or collation. */
  readonly plain: boolean;
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
  readonly timing: "before" | "after" | "instead of";
  /** `insert`, `update`, `delete` and `truncate`, as listed. */
  readonly events: readonly string[];
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
  /** How many arguments it takes, `out` and defaulted ones included. */
  readonly arity: number;
  /** The text between the quotes of `as`, whichever quoting the file used. */
  readonly body: string | undefined;
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
  /** The schema an extension is created `with schema`. */
  readonly schema?: string;
}

/** An object a statement creates, in file order, for the declaration model. */
export interface DeclaredFact {
  readonly kind:
    | "table"
    | "view"
    | "function"
    | "index"
    | "policy"
    | "trigger"
    | "type"
    | "sequence"
    | "schema"
    | "extension";
  /** `schema.name`; a policy or trigger is `schema.table.name`. */
  readonly name: string;
  /** A function's argument count. */
  readonly arity?: number;
  readonly line: number;
  readonly ifNotExists: boolean;
}

/** A function a top-level `select` calls, with its string arguments. */
export interface CallFact {
  /** `schema.function` as written, or the bare name. */
  readonly name: string;
  readonly strings: readonly string[];
  readonly index: number;
}

/**
 * What a statement does to the audited tables, in file order: a
 * `better_supabase.audit(...)` call or `bsb_audit` trigger registers a table,
 * `unaudit(...)` or `drop table` removes it and `rename to` moves it.
 */
export type AuditFact =
  | {
      readonly kind: "register";
      /** `schema.table`, unquoted. */
      readonly target: string;
      readonly ignore: readonly string[];
      readonly redact: readonly string[];
      readonly index: number;
    }
  | {
      readonly kind: "unregister" | "drop";
      readonly target: string;
      readonly index: number;
    }
  | {
      readonly kind: "rename";
      readonly target: string;
      readonly to: string;
      readonly index: number;
    };

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
  /** Every created object in statement order. */
  readonly declared: readonly DeclaredFact[];
  readonly calls: readonly CallFact[];
  readonly audits: readonly AuditFact[];
  /** The file starts a generated module (`-- @bsb-block` or `-- @bs-module`). */
  readonly module: boolean;
  /** The module a marker comment names (`-- @bsb-block name@3`), if any. */
  readonly moduleName?: string;
  /** Lines of `do` blocks. */
  readonly doBlocks: readonly number[];
  /** Lines of `do` blocks that create objects or `execute` at run time. */
  readonly doCreates: readonly number[];
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
