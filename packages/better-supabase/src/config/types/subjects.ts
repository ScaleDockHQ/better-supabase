/**
 * One entity the app's blocks attach to (`subjects.<type>`): a task, a
 * customer, a document. Every subject-bound SQL module reads these entries
 * unless its own `on` says otherwise. ADR 0020.
 */
export interface SubjectConfig {
  /** `schema.table`, or a table in `public`. */
  readonly table: string;
  /** The id column. Defaults to `id`. */
  readonly id?: string;
  /**
   * The id column's type, such as `uuid` or `bigint`, so lookups compare on the
   * primary key's own type. Without it the column is compared as text.
   */
  readonly idType?: string;
  /**
   * The tenant column. Defaults to `organization_id`, or
   * `<blocks.memberships.names.organization>_id` when the tenant is renamed.
   * `false` for a subject without a tenant, which modules that keep a tenant on
   * every row skip.
   */
  readonly tenant?: string | false;
  /** The column `subject_title` returns. */
  readonly title?: string;
  /**
   * The path `subject_url` returns, with `{column}` placeholders:
   * `/tasks/{id}`.
   */
  readonly url?: string;
  /**
   * A permission key per action (`read`, `write`, `share`, `comment`,
   * `moderate`, or an app action) that `can_subject` checks in the subject's
   * tenant, on top of the row being visible to the caller. `read` is also the
   * permission modules check before they attach rows to the subject. An object
   * adds per-row grants: `rows` asks the authorization provider for the rows of
   * that resource the caller holds `key` on, and `owner` names a uuid column
   * whose value is the caller; any form that holds grants the action.
   */
  readonly permissions?: Readonly<Record<string, string | SubjectPermission>>;
  /**
   * A scope the authorization provider declares whose ids are this subject's
   * ids, so a grant on the record counts as well as one on the tenant.
   */
  readonly scope?: string;
  /** Delete module rows for a subject when its row is deleted. */
  readonly cascade?: boolean;
  /**
   * The column holding the soft-delete time. Blocks hide rows where it is set,
   * metrics skip them, and `gen` makes it the table's `trashExtension()`
   * column.
   */
  readonly deletedAt?: string;
  /** The columns a search index reads. */
  readonly search?: SubjectSearch;
  /**
   * The text column holding the subject's rank key, and the column it is
   * grouped by (a board stage), for `move()`. ADR 0021.
   */
  readonly rank?: { readonly column: string; readonly group?: string };
  /**
   * The columns the versions block snapshots and restores, and whether it
   * snapshots on each change. An app table's `subject.versions` sets it.
   */
  readonly versions?: {
    readonly columns: readonly string[];
    readonly auto: boolean;
  };
}

/**
 * An action on a subject granted in more ways than a tenant key: the tenant
 * (and `scope`) key, the provider's per-row grants and the row's owner. Any one
 * that holds grants the action.
 */
export interface SubjectPermission {
  /** The permission key, checked in the tenant and on `scope`. */
  readonly key?: string;
  /**
   * A resource of the authorization provider (its SQL name, such as
   * `file_node`) whose row grants for `key` count, through the provider's
   * `rowsWith` template. Needs `key`.
   */
  readonly rows?: string;
  /** A uuid column of the subject row that grants the action to its user. */
  readonly owner?: string;
  /**
   * A permission key the caller must hold as well, in the row's tenant (or on
   * `scope`), whichever of `key`, `rows` and `owner` grants the action.
   */
  readonly also?: string;
}

/**
 * What the search index reads for a record type: `title` and `body` columns of
 * the row (or of `from`), a `description` returned with each hit, and an
 * `exclude` column that keeps a row out of search while it is set.
 */
export interface SubjectSearch {
  readonly title?: string;
  readonly body?: readonly string[];
  /** A column whose value each hit returns as `description`. */
  readonly description?: string;
  /**
   * A column that keeps the row out of the index while it is set (not null, and
   * not `false`), such as `archived_at`; other blocks still see the row.
   */
  readonly exclude?: string;
  /**
   * A view or table with one row per record, keyed by `key` (the record's id),
   * that `title`, `body`, `description` and `exclude` read instead of the
   * record's own row.
   */
  readonly from?: { readonly view: string; readonly key: string };
  /**
   * Tables whose changes re-index the record: `key` is the column holding the
   * record's id, or, with `via`, the column the record's `via` column points
   * at.
   */
  readonly watch?: readonly {
    readonly table: string;
    readonly key: string;
    readonly via?: string;
  }[];
}

/**
 * The app's subject types, keyed by type name (lowercase, digits and
 * underscores).
 */
export type SubjectsConfig = Readonly<Record<string, SubjectConfig>>;
