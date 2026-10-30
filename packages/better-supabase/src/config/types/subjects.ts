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
   * whose value is the caller; any form that holds grants the action. `check`
   * names a SQL function that decides the action for one row.
   */
  readonly permissions?: Readonly<Record<string, string | SubjectPermission>>;
  /**
   * Who reads the rows blocks keep per record, such as custom field values:
   * `tenant` (the default) asks for the block's own read key, `record` asks
   * whether the caller may read the record through `permissions.read`.
   */
  readonly readAccess?: "tenant" | "record";
  /**
   * The record team (`subject_members`): `can_subject` grants each of `actions`
   * to the users and teams on the record's team while their dates include
   * today, next to the key, the owner column and the check. An action in
   * `actions` without a `permissions` entry is granted only to the team. Needs
   * a tenant column.
   */
  readonly team?: SubjectTeam;
  /**
   * Log every read of a record through the blocks' read functions in the audit
   * log (`record_subject_read`, category `read`), with the NEN 7513 fields:
   * who, which record, when, which function and whether it was an emergency.
   * `subject_access_log` lists the entries. Needs the `subjects` and `audit`
   * blocks. Plain `select`s through the Data API are not logged.
   */
  readonly auditReads?: boolean;
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
  /**
   * The column holding a legal hold's end time. The trash block keeps a batch
   * with a held subject in the trash instead of purging it.
   */
  readonly held?: string;
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
  /**
   * The schema-qualified name of a SQL function `(subject_id <idType>) returns
   * boolean`, such as `better_supabase.drive_node_writable`, that answers for
   * the caller (`auth.uid()`). Alone it decides the action; next to `key`,
   * `rows` or `owner` it must return true as well. `can_subject_for` can't run
   * it for another user, so the action is false there.
   */
  readonly check?: string;
}

/** `subjects.<type>.team`: the actions a record's team holds on it. */
export interface SubjectTeam {
  /** Such as `["read", "write"]`. */
  readonly actions: readonly string[];
}

/** One table `search.watch[].through` crosses: from the `from` column to `to`. */
export interface SearchWatchHop {
  readonly table: string;
  readonly from: string;
  readonly to: string;
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
   * at. `through` follows `key` across further tables first, such as a junction
   * table: each hop reads `to` from the rows of `table` whose `from` holds the
   * previous value.
   */
  readonly watch?: readonly {
    readonly table: string;
    readonly key: string;
    readonly via?: string;
    readonly through?: readonly SearchWatchHop[];
  }[];
}

/**
 * The app's subject types, keyed by type name (lowercase, digits and
 * underscores).
 */
export type SubjectsConfig = Readonly<Record<string, SubjectConfig>>;
