import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  WORLD_POSTGRES_MIGRATIONS,
  WORLD_POSTGRES_VERSION,
} from "../../sql/modules/workflow-sdk-world-ddl.generated.ts";

export interface MigrationDrift {
  /** Tags the installed package has and the DDL lacks. */
  readonly added: readonly string[];
  /** Tags the DDL has and the installed package lacks. */
  readonly removed: readonly string[];
  /** Tags whose SQL changed. */
  readonly changed: readonly string[];
}

/** The `sha256` of each migration the installed world-postgres journal lists. */
async function installedMigrations(
  dir: string,
): Promise<readonly { tag: string; sha256: string }[]> {
  const journal: unknown = JSON.parse(
    await readFile(join(dir, "meta", "_journal.json"), "utf-8"),
  );

  const entries =
    typeof journal === "object" && journal !== null && "entries" in journal
      ? journal.entries
      : undefined;

  if (!Array.isArray(entries)) {
    throw new TypeError("the migration journal has no entries");
  }

  const list: unknown[] = entries;
  const found: { tag: string; sha256: string }[] = [];

  for (const entry of list) {
    const tag: unknown =
      typeof entry === "object" && entry !== null && "tag" in entry
        ? entry.tag
        : undefined;

    if (typeof tag !== "string") {
      throw new TypeError("a journal entry has no tag");
    }

    const sql = await readFile(join(dir, `${tag}.sql`), "utf-8");
    found.push({ tag, sha256: createHash("sha256").update(sql).digest("hex") });
  }

  return found;
}

/** Compares the migrations the DDL reproduces with an installed list. */
export function compareMigrations(
  installed: readonly { tag: string; sha256: string }[],
): MigrationDrift | undefined {
  const expected = new Map(
    WORLD_POSTGRES_MIGRATIONS.map(({ tag, sha256 }) => [tag, sha256]),
  );

  const have = new Map(installed.map(({ tag, sha256 }) => [tag, sha256]));
  const added = [...have.keys()].filter((tag) => !expected.has(tag));
  const removed = [...expected.keys()].filter((tag) => !have.has(tag));

  const changed = [...have].flatMap(([tag, sha256]) =>
    expected.has(tag) && expected.get(tag) !== sha256 ? [tag] : [],
  );

  return added.length === 0 && removed.length === 0 && changed.length === 0
    ? undefined
    : { added, removed, changed };
}

/**
 * Fails when the installed `@workflow/world-postgres` ships migrations the
 * `workflow-sdk` SQL module's DDL doesn't reproduce, which would leave the
 * tables behind the code that reads them. Resolves without a check when the
 * package's migration files can't be read (a bundled or traced deployment).
 * `migrationsDir` points the check at another migrations folder.
 */
export async function assertWorldMigrations(
  migrationsDir?: string,
): Promise<void> {
  let dir: string;

  try {
    const entry = fileURLToPath(
      import.meta.resolve("@workflow/world-postgres"),
    );

    dir =
      migrationsDir ??
      join(dirname(entry), "..", "src", "drizzle", "migrations");
  } catch {
    return;
  }

  let installed: readonly { tag: string; sha256: string }[];

  try {
    installed = await installedMigrations(dir);
  } catch {
    return;
  }

  const drift = compareMigrations(installed);

  if (drift === undefined) {
    return;
  }

  const parts = [
    ...drift.added.map((tag) => `new ${tag}`),
    ...drift.removed.map((tag) => `missing ${tag}`),
    ...drift.changed.map((tag) => `changed ${tag}`),
  ];

  throw new Error(
    `better-supabase: the installed @workflow/world-postgres migrations differ from the workflow-sdk SQL module's DDL (generated from ${WORLD_POSTGRES_VERSION}): ${parts.join(", ")}. Install the version the module was generated from, or regenerate with scripts/gen-workflow-ddl.ts and upgrade the module.`,
  );
}
