import type { BlockSqlLayout } from "./module-types.ts";

// Plain data the CLI reads from the schema files with its SQL reader and hands
// to the render functions (ADR 1300). No parser or scanner is imported here.

/** Privileges one role gets on a table, from the policies that name it. */
export interface PolicyGrant {
  /** `schema.table`, unquoted; an unqualified name is in `public`. */
  readonly table: string;
  readonly role: "anon" | "authenticated";
  readonly privileges: readonly ("select" | "insert" | "update" | "delete")[];
}

/** A view the app's files create. */
export interface DeclaredView {
  /** Its columns, or `undefined` when they can't be read (`select *`). */
  readonly columns: readonly string[] | undefined;
  /** Whether `insert`, `update` and `delete` reach the table under it. */
  readonly updatable: boolean;
}

/**
 * An index of the app's, by its name when it has one, and its leading columns.
 * Without `method` and `where` it is a full btree index.
 */
export interface OwnIndex {
  readonly name?: string;
  readonly columns: readonly string[];
  /** Whether it enforces uniqueness: a unique index, a unique or primary key. */
  readonly unique?: boolean;
  /**
   * Whether every key is a plain column. An expression key is false. Omitted
   * means the caller already knows the keys are columns.
   */
  readonly plain?: boolean;
  /** The access method when it is not `btree`. */
  readonly method?: string;
  /**
   * The `where` of a partial index. Omitted for a full index, and for a unique
   * key whose `where` is `<key column> is not null`.
   */
  readonly where?: string;
}

/** A foreign key the schema files declare. */
export interface DeclaredForeignKey {
  /** `schema.table`, unquoted. */
  readonly table: string;
  readonly columns: readonly string[];
  /** The referenced `schema.table`, unquoted. */
  readonly references: string;
  /**
   * The referenced columns. Without a column list, the referenced table's
   * declared primary key, or `id` when the files don't declare one.
   */
  readonly referencedColumns: readonly string[];
  /** The key is `deferrable`, so it is checked at commit, not per statement. */
  readonly deferrable?: boolean;
}

/**
 * The layout fields `blocks.memberships.options.sameTenant.auto` derives its
 * entries from, plus the app triggers' bodies.
 */
export type SameTenantLayout = Required<
  Pick<
    BlockSqlLayout,
    "foreignKeys" | "declaredColumns" | "notNullColumns" | "appTriggerColumns"
  >
> & {
  /**
   * The function body of each app trigger, `schema.table` to bodies (doctor
   * BS398).
   */
  readonly appTriggerBodies: Readonly<Record<string, readonly string[]>>;
};
