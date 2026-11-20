// Fails when a branch adds a migration that sorts before the newest one on
// main in the same folder: `supabase db push` and `db reset` apply migrations
// by file name, so a migration older than main's newest runs out of order on a
// database that already has main's. Rename the file with a newer timestamp.
// It checks the root stack and each validation project, and it counts
// migrations not committed yet. In CI a missing base is fetched, and the check
// fails when it still can't be read.
import { execFileSync } from "node:child_process";

const ROOT = "supabase/migrations/";

const VALIDATION = /^(tests\/validation-[^/]+\/supabase\/migrations\/)[^/]+$/u;

const git = (...args: readonly string[]): string =>
  execFileSync("git", args, { encoding: "utf-8" });

/** The migrations folder of a path, or undefined for any other file. */
export function folderOf(path: string): string | undefined {
  if (!path.endsWith(".sql")) {
    return undefined;
  }

  if (path.startsWith(ROOT) && !path.slice(ROOT.length).includes("/")) {
    return ROOT;
  }

  return VALIDATION.exec(path)?.[1];
}

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

/** File names per migrations folder. */
export function byFolder(paths: readonly string[]): Map<string, string[]> {
  const folders = new Map<string, string[]>();

  for (const path of paths) {
    const folder = folderOf(path);

    if (folder !== undefined) {
      folders.set(folder, [
        ...(folders.get(folder) ?? []),
        path.slice(folder.length),
      ]);
    }
  }

  return folders;
}

const lines = (output: string): string[] =>
  output.split("\n").filter((line) => line !== "");

function readable(ref: string): boolean {
  try {
    git("rev-parse", "--verify", "--quiet", ref);

    return true;
  } catch {
    return false;
  }
}

function baseRef(ref: string): boolean {
  if (readable(ref)) {
    return true;
  }

  if (process.env["CI"] === undefined || !ref.startsWith("origin/")) {
    return false;
  }

  try {
    git("fetch", "--no-tags", "origin", ref.slice("origin/".length));
  } catch {
    return false;
  }

  return readable(ref);
}

function main(): number {
  const ref = process.env["MIGRATION_BASE"] ?? "origin/main";

  if (!baseRef(ref)) {
    if (process.env["CI"] !== undefined) {
      process.stderr.write(
        `check-migration-order: ${ref} can't be read, so the order can't be checked\n`,
      );

      return 1;
    }

    process.stdout.write(`check-migration-order: ${ref} not found, skipped\n`);

    return 0;
  }

  const fork = git("merge-base", ref, "HEAD").trim();
  const base = byFolder(lines(git("ls-tree", "-r", "--name-only", ref)));

  const added = byFolder([
    ...lines(git("diff", "--name-only", "--diff-filter=A", fork)),
    ...lines(git("ls-files", "--others", "--exclude-standard")),
  ]);

  const late = [...added].flatMap(([folder, names]) =>
    outOfOrder(base.get(folder) ?? [], names).map((name) => folder + name),
  );

  if (late.length === 0) {
    process.stdout.write("check-migration-order: migrations are in order\n");

    return 0;
  }

  process.stderr.write(
    `check-migration-order: ${late.join(", ")} sort before the newest migration of their folder on ${ref}. Rename each with a newer timestamp.\n`,
  );

  return 1;
}

if (import.meta.main) {
  process.exitCode = main();
}
