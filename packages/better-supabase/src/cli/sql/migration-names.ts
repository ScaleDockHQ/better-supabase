import { createHash } from "node:crypto";

import { canonicalSql } from "../schema-reader/index.ts";

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

/**
 * The version of the content hash `migrationFile` writes (ADR 1301). Version 1
 * hashed the statements as whitespace-collapsed text with `--` lines dropped
 * and has no tag in the name; version 2 hashes the parser's canonical text and
 * is tagged `v2-` before the digits.
 */
const CONTENT_HASH_VERSION = 2;

const digest = (text: string): string =>
  createHash("sha256").update(text).digest("hex").slice(0, 8);

/** The version 1 hash: the text without `--` lines, whitespace collapsed. */
const legacyContentHash = (contents: string): string =>
  digest(
    contents
      .split("\n")
      .filter((line) => !line.trimStart().startsWith("--"))
      .join("\n")
      .replaceAll(/\s+/g, " ")
      .trim(),
  );

/**
 * The version 2 hash of a migration's statements, or `undefined` when the text
 * does not parse, so the name falls back to version 1.
 */
async function canonicalContentHash(
  contents: string,
): Promise<string | undefined> {
  const canonical = await canonicalSql(contents);

  return canonical === undefined ? undefined : digest(canonical);
}

const HASH = /_(?:v2-)?[0-9a-f]{8}(?=\.sql$)/;

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
 * migration an earlier run wrote with the same statements is returned as it is,
 * whether it carries the version 2 hash or the version 1 hash of an older
 * release: a pushed migration is never renamed.
 */
export async function migrationFile(
  existing: readonly string[],
  now: Date,
  suffix: string,
  contents: string,
  reuse = true,
): Promise<{ readonly name: string; readonly exists: boolean }> {
  const canonical = await canonicalContentHash(contents);

  const hashes = [
    ...(canonical === undefined
      ? []
      : [`v${CONTENT_HASH_VERSION}-${canonical}`]),
    legacyContentHash(contents),
  ].map((hash) => suffix.replace(/\.sql$/, `_${hash}.sql`));

  const same = reuse
    ? existing.find((name) => hashes.some((hashed) => name.endsWith(hashed)))
    : undefined;

  return same === undefined
    ? { name: `${stampAfter(existing, now)}${hashes[0]!}`, exists: false }
    : { name: same, exists: true };
}
