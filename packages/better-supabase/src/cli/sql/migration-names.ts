import { createHash } from "node:crypto";

/** `YYYYMMDDHHMMSS` in UTC, the Supabase CLI's migration prefix. */
export const migrationStamp = (now: Date): string =>
  now.toISOString().replaceAll(/[-:T]/g, "").slice(0, 14);

/**
 * A stamp for `now`, or one second after the newest migration when that one has
 * the same stamp or a later one: the Supabase CLI keys migrations by stamp, and
 * the data has to run after the schema.
 */
export function stampAfter(migrations: readonly string[], now: Date): string {
  // Every name that starts with 14 digits counts, whatever follows them
  // (another tool's `<stamp>-seeds.sql` or `<stamp>.sql`), so the data
  // migration never shares a timestamp with one.
  const newest = migrations
    .map((name) =>
      /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?!\d)/.exec(name),
    )
    .filter((match) => match !== null)
    .map((match) =>
      Date.UTC(
        Number(match[1]),
        Number(match[2]) - 1,
        Number(match[3]),
        Number(match[4]),
        Number(match[5]),
        Number(match[6]),
      ),
    )
    .reduce((max, time) => Math.max(max, time), Number.NEGATIVE_INFINITY);

  const at = Math.floor(now.getTime() / 1000) * 1000;

  return migrationStamp(new Date(Math.max(at, newest + 1000)));
}

/** The first 8 hex digits of a migration's statements, comments left out. */
function contentHash(contents: string): string {
  return createHash("sha256")
    .update(
      contents
        .split("\n")
        .filter((line) => !line.trimStart().startsWith("--"))
        .join("\n")
        .replaceAll(/\s+/g, " ")
        .trim(),
    )
    .digest("hex")
    .slice(0, 8);
}

const HASH = /_[0-9a-f]{8}(?=\.sql$)/;

/**
 * Whether `name` is a migration `suffix` names, with or without the content
 * hash `migrationFile` puts before `.sql`.
 */
export const hasMigrationSuffix = (name: string, suffix: string): boolean =>
  name.replace(HASH, "").endsWith(suffix);

/**
 * The file a migration is written to: a stamp that is later than every name in
 * `existing` (so two tools never share a version, and the Supabase CLI keeps
 * them in order), the `suffix`, and a hash of the statements before `.sql`. A
 * migration an earlier run wrote with the same statements is returned as it
 * is.
 */
export function migrationFile(
  existing: readonly string[],
  now: Date,
  suffix: string,
  contents: string,
  reuse = true,
): { readonly name: string; readonly exists: boolean } {
  const hashed = suffix.replace(/\.sql$/, `_${contentHash(contents)}.sql`);

  const same = reuse
    ? existing.find((name) => name.endsWith(hashed))
    : undefined;

  return same === undefined
    ? { name: `${stampAfter(existing, now)}${hashed}`, exists: false }
    : { name: same, exists: true };
}
