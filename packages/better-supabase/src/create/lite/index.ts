import type { LiteRuntime } from "../../lite/runtime.ts";
import type { Issue } from "../issue.ts";
import type { PresetMigrationFile } from "../types.ts";
import type { SkippedBlock } from "./apply.ts";

import { LITE_INSTALL, loadLite } from "../../lite/runtime.ts";
import { applyFiles } from "./apply.ts";
import { SUPABASE_PRELUDE } from "./prelude.ts";

export { SUPABASE_PRELUDE } from "./prelude.ts";

export type { SkippedBlock } from "./apply.ts";

export type { RawCatalog, RawColumn, RawTable } from "./catalog.ts";

export * from "./import.ts";

export * from "./data-api.ts";

export * from "./verify.ts";

export type {
  Persona,
  Sandbox,
  SandboxError,
  SandboxOptions,
  SandboxResult,
  SandboxSession,
} from "./sandbox.ts";

export { openSandbox } from "./sandbox.ts";

export interface DesignValidation {
  /** `true` when every file that could run applied cleanly. */
  readonly ok: boolean;
  /** One issue per file Postgres rejected: `source: "sql"`, `table` the module. */
  readonly issues: readonly Issue[];
  readonly skipped: readonly SkippedBlock[];
  /** Tables in `public` after the files applied. */
  readonly tables: number;
}

export interface ValidateDesignOptions {
  /** A loaded `@supabase/lite`; loaded on demand when left out. */
  readonly runtime?: LiteRuntime;
}

/**
 * Applies the files `previewFiles` returns to an in-memory PGlite database and
 * reports what Postgres rejects. A module that needs an extension PGlite
 * doesn't ship (`pgmq`, `btree_gist`) is skipped, not failed, along with its
 * other files. pgTAP test files are left out, as in `deployQuery`. Throws when
 * `@supabase/lite` isn't installed.
 */
export async function validateDesign(
  files: readonly PresetMigrationFile[],
  options: ValidateDesignOptions = {},
): Promise<DesignValidation> {
  const runtime = options.runtime ?? (await loadLite());

  if (runtime === undefined) {
    throw new Error(LITE_INSTALL);
  }

  const connection = await runtime.createPgliteConnection();

  try {
    const { driver } = connection;

    await driver.exec(SUPABASE_PRELUDE);

    const { issues, skipped } = await applyFiles(driver, files);

    const { rows } = await driver.query(
      "select count(*)::int as count from pg_tables where schemaname = 'public'",
    );

    const [row] = rows;

    const tables =
      typeof row === "object" && row !== null && "count" in row
        ? Number(row.count)
        : 0;

    return { ok: issues.length === 0, issues, skipped, tables };
  } finally {
    await connection.close();
  }
}

/**
 * The issues `validateDesign` finds, for `checkProject`'s `sql` option:
 * `checkProject(project, { sql: sqlIssues })`.
 */
export async function sqlIssues(
  files: readonly PresetMigrationFile[],
): Promise<readonly Issue[]> {
  return (await validateDesign(files)).issues;
}
