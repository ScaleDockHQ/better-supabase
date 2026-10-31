// Fails when a branch adds a migration that sorts before the newest one on
// main: `supabase db push` and `db reset` apply migrations by file name, so a
// migration older than main's newest runs out of order on a database that
// already has main's. Rename the file with a newer timestamp.
import { execFileSync } from "node:child_process";

const DIR = "supabase/migrations/";

const git = (...args: readonly string[]): string =>
  execFileSync("git", args, { encoding: "utf-8" });

const names = (output: string): string[] =>
  output
    .split("\n")
    .filter((line) => line.startsWith(DIR) && line.endsWith(".sql"))
    .map((line) => line.slice(DIR.length));

/** The migrations in `added` that sort before the newest one in `base`. */
export function outOfOrder(
  base: readonly string[],
  added: readonly string[],
): string[] {
  const newest = base.toSorted().at(-1);

  return newest === undefined
    ? []
    : added.filter((name) => name < newest).toSorted();
}

function main(): number {
  const ref = process.env["MIGRATION_BASE"] ?? "origin/main";

  try {
    git("rev-parse", "--verify", "--quiet", ref);
  } catch {
    process.stdout.write(`check-migration-order: ${ref} not found, skipped\n`);

    return 0;
  }

  const base = names(git("ls-tree", "-r", "--name-only", ref, DIR));

  const added = names(
    git("diff", "--name-only", "--diff-filter=A", `${ref}...HEAD`, "--", DIR),
  );

  const late = outOfOrder(base, added);

  if (late.length === 0) {
    process.stdout.write("check-migration-order: migrations are in order\n");

    return 0;
  }

  process.stderr.write(
    `check-migration-order: ${late.join(", ")} sort before the newest migration on ${ref}. Rename each with a newer timestamp.\n`,
  );

  return 1;
}

if (import.meta.main) {
  process.exitCode = main();
}
