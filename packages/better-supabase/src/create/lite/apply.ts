import type { Issue } from "../issue.ts";
import type { PresetMigrationFile } from "../types.ts";

/** The part of a PGlite instance that applying files needs. */
export interface FileDriver {
  exec(sql: string): Promise<unknown>;
}

/**
 * A module PGlite can't run, such as one that needs an extension it doesn't
 * ship.
 */
export interface SkippedBlock {
  readonly module: string;
  readonly reason: string;
}

const MISSING_EXTENSION = /extension "([^"]+)" is not available/u;

export function messageOf(error: unknown): string {
  return (error instanceof Error ? error.message : String(error))
    .replaceAll(/\s+/gu, " ")
    .slice(0, 300);
}

/**
 * Runs each file in order. A module that needs an extension PGlite doesn't ship
 * is skipped, with its other files. pgTAP test files are left out.
 */
export async function applyFiles(
  driver: FileDriver,
  files: readonly PresetMigrationFile[],
): Promise<{
  readonly issues: readonly Issue[];
  readonly skipped: readonly SkippedBlock[];
}> {
  const issues: Issue[] = [];
  const skipped = new Map<string, string>();

  for (const file of files) {
    if (file.path.includes("/tests/") || skipped.has(file.module)) {
      continue;
    }

    try {
      await driver.exec(file.contents);
    } catch (error) {
      const message = messageOf(error);
      const extension = MISSING_EXTENSION.exec(message)?.[1];

      if (extension === undefined) {
        issues.push({
          code: "sql_error",
          severity: "error",
          source: "sql",
          path: "",
          table: file.module,
          file: file.path,
          message,
        });
      } else {
        skipped.set(
          file.module,
          `Needs the ${extension} extension, which PGlite doesn't ship.`,
        );
      }
    }
  }

  return {
    issues,
    skipped: [...skipped].map(([module, reason]) => ({ module, reason })),
  };
}
