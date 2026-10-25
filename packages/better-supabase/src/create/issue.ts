import type { DesignErrorCode } from "../preset/design.ts";

/** Where in the project pipeline an issue came from. */
export type IssueSource =
  /** The preset or the design failed to parse or conflicts with the preset. */
  | "design"
  /** A rule that needs the preset: names, references, keys, defaults. */
  | "rules"
  /** Postgres rejected a file when it applied in PGlite. */
  | "sql"
  /** A catalog check (`verifyCatalog`). */
  | "verifier"
  /** The migration plan (renames, data loss). */
  | "plan";

export type IssueSeverity = "error" | "warning" | "info";

/**
 * A stable code for an issue: a `DesignErrorCode` from parsing, a rule that
 * needs the preset, `sql_error` for a file Postgres rejected, or a code the
 * verifier or the plan adds (`verify_*`, `plan_*`). The codes are stable; the
 * messages may change.
 */
export type IssueCode =
  | DesignErrorCode
  /** A block already creates a table with this name. */
  | "table_name_taken"
  /** A table name too long for the names Postgres derives from it. */
  | "name_too_long"
  /** Another app table already has this subject type. */
  | "subject_type_taken"
  /** A column default its type doesn't accept. */
  | "invalid_default"
  /** A required column signed-in users can't write, with no default. */
  | "default_required"
  /** A column that clashes with one its record features add. */
  | "column_clash"
  /** A unique key or index naming a column the table doesn't have. */
  | "unknown_column"
  /** A reference to a table the preset doesn't install. */
  | "missing_reference"
  /** A set-null delete on a required column. */
  | "set_null_required"
  /** A conflict in the preset itself, such as a block that needs tenants. */
  | "preset_conflict"
  /** A file Postgres rejected when it applied. */
  | "sql_error"
  | `verify_${string}`
  | `plan_${string}`;

/**
 * The one problem type every surface reports: the canvas, the chat tools, the
 * API, the CLI's doctor and the deploy planner (ADR 0100).
 */
export interface Issue {
  readonly code: IssueCode;
  readonly severity: IssueSeverity;
  readonly source: IssueSource;
  /**
   * A JSON Pointer (RFC 6901) into the design, such as
   * `/appTables/tasks/columns/title`. `""` is the design itself, and the path
   * of an issue with the preset or with SQL.
   */
  readonly path: string;
  /** The app table or block module the issue is on, or `design` or `preset`. */
  readonly table: string;
  readonly message: string;
  /** The file, for an issue found in SQL. */
  readonly file?: string;
}
