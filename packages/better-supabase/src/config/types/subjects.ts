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
  readonly search?: {
    readonly title?: string;
    readonly body?: readonly string[];
  };
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
}

/**
 * The app's subject types, keyed by type name (lowercase, digits and
 * underscores).
 */
export type SubjectsConfig = Readonly<Record<string, SubjectConfig>>;
