// A block that installs SQL needs a pgTAP file in supabase/tests/database
// whose name starts with the block's name (`-` and `_` count the same):
// `assets` is covered by `assets.test.sql` or `assets_leases.test.sql`.
// Blocks that have none yet sit in pgtap-allowlist.json, and the check fails
// when a listed block gains a file, so the list only shrinks (EX-1351).
import { existsSync, readdirSync, readFileSync } from "node:fs";

const SQL_LIST = /^\s*sql:\s*\[([^\]]*)\]/m;

const normalized = (name: string): string => name.replaceAll("-", "_");

/** The names of the blocks whose manifest lists at least one SQL module. */
export function blocksWithSql(blocksRoot: string): string[] {
  const names: string[] = [];

  for (const entry of readdirSync(blocksRoot, { withFileTypes: true })) {
    const manifest = `${blocksRoot}/${entry.name}/manifest.ts`;

    if (!entry.isDirectory() || !existsSync(manifest)) {
      continue;
    }

    const modules = SQL_LIST.exec(readFileSync(manifest, "utf-8"))?.[1];

    if (modules?.trim()) {
      names.push(entry.name);
    }
  }

  return names.toSorted();
}

/** The names of the pgTAP files, without the `.test.sql` suffix. */
export function pgtapNames(testsDir: string): string[] {
  return readdirSync(testsDir)
    .filter((file) => file.endsWith(".test.sql"))
    .map((file) => normalized(file.slice(0, -".test.sql".length)));
}

/**
 * Problems for blocks with SQL and no pgTAP file, and for stale allowlist
 * entries.
 */
export function pgtapProblems(
  blocks: readonly string[],
  tests: readonly string[],
  allowlist: readonly string[],
): string[] {
  const covered = (block: string): boolean =>
    tests.some(
      (name) =>
        name === normalized(block) || name.startsWith(`${normalized(block)}_`),
    );

  const allowed = new Set(allowlist);
  const problems: string[] = [];

  for (const block of blocks) {
    if (!covered(block) && !allowed.has(block)) {
      problems.push(
        `pgtap: block ${block} installs SQL but supabase/tests/database has no ${normalized(block)}*.test.sql`,
      );
    }
  }

  for (const name of allowlist) {
    if (!blocks.includes(name)) {
      problems.push(
        `pgtap: ${name} is not a block with SQL; remove it from scripts/pgtap-allowlist.json`,
      );
    } else if (covered(name)) {
      problems.push(
        `pgtap: ${name} has a pgTAP file now; remove it from scripts/pgtap-allowlist.json`,
      );
    }
  }

  return problems;
}

/** Reads the repository and returns the problems; the caller prints them. */
export function checkPgtapCoverage(): string[] {
  // SAFETY: pgtap-allowlist.json is this repo's own file, a list of block names.
  const allowlist = JSON.parse(
    readFileSync("scripts/pgtap-allowlist.json", "utf-8"),
  ) as string[];

  return pgtapProblems(
    blocksWithSql("packages/better-supabase/src/blocks"),
    pgtapNames("supabase/tests/database"),
    allowlist,
  );
}
