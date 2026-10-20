import type { CreateDesign, DesignChange } from "../preset/index.ts";

import { diffDesigns } from "../preset/index.ts";
import { previewFiles } from "./preview-provider.ts";

/** The module whose file holds the app's own tables. */
const APP_TABLES_MODULE = "app-tables";

/**
 * Why no migration was written: `breaking` changes need the expand and
 * contract steps in each change, and `unsupported` ones are outside what a
 * generated migration covers.
 */
export type MigrationRefusal = "breaking" | "unsupported";

export type MigrationPlan =
  | {
      readonly ok: true;
      /** The SQL to apply; empty when nothing changed. */
      readonly sql: string;
      readonly changes: readonly DesignChange[];
    }
  | {
      readonly ok: false;
      readonly reason: MigrationRefusal;
      /** The changes that caused the refusal, or every change when a file outside the app tables differs. */
      readonly changes: readonly DesignChange[];
    };

/**
 * The migration that takes a project deployed from `base` to `next`, for
 * added tables and added columns only. The rendered app-table SQL is
 * idempotent (`create table if not exists`, `add column if not exists`,
 * `drop policy if exists`), so the migration is the re-rendered file.
 * Anything else, such as a rename, a retype, a changed default or a change
 * outside `appTables`, is refused so a deploy never guesses.
 */
export function migrationBetween(
  code: string,
  base: CreateDesign,
  next: CreateDesign,
): MigrationPlan {
  const changes = diffDesigns(base, next);
  const breaking = changes.filter((change) => change.breaking);

  if (breaking.length > 0) {
    return { ok: false, reason: "breaking", changes: breaking };
  }

  const unsupported = changes.filter(
    (change) => change.kind !== "table.added" && change.kind !== "column.added",
  );

  if (unsupported.length > 0) {
    return { ok: false, reason: "unsupported", changes: unsupported };
  }

  const before = new Map(
    previewFiles(code, base).map((file) => [file.path, file.contents]),
  );

  const differing = previewFiles(code, next).filter(
    (file) => before.get(file.path) !== file.contents,
  );

  if (differing.some((file) => file.module !== APP_TABLES_MODULE)) {
    return { ok: false, reason: "unsupported", changes };
  }

  return {
    ok: true,
    sql: differing
      .map((file) => `-- ${file.path}\n${file.contents.trim()}\n`)
      .join("\n"),
    changes,
  };
}
