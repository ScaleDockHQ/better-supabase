import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { basename, join } from "node:path";

/** Bumped when the artifact layout changes, so an older artifact never loads. */
export const BASELINE_FORMAT = 1;

export interface HashedFile {
  /** Relative to the project root, with forward slashes. */
  readonly file: string;
  readonly sha256: string;
}

/** The tool versions that decide whether an artifact fits a stack. */
export interface BaselineVersions {
  readonly bsb: string;
  readonly supabaseCli: string;
  readonly postgres: string;
  readonly engine: string;
}

interface SeedManifest {
  readonly key: string;
  readonly files: readonly HashedFile[];
  /** Row counts of the tables the seed snapshot restores. */
  readonly counts: Readonly<Record<string, number>>;
  /** Storage objects in the tarball. */
  readonly objects: number;
  /**
   * The catalog digest after the seeds: they may create objects, such as pgmq
   * queues.
   */
  readonly fingerprint: Readonly<Record<string, string>>;
}

export interface BaselineManifest {
  readonly format: number;
  readonly key: string;
  readonly createdAt: string;
  readonly versions: BaselineVersions;
  readonly migrations: readonly HashedFile[];
  /** Row counts of the tables `data.sql` restores. */
  readonly counts: Readonly<Record<string, number>>;
  /**
   * Digest of policies, triggers, grants and functions, recomputed after a
   * restore.
   */
  readonly fingerprint: Readonly<Record<string, string>>;
  readonly seed?: SeedManifest;
}

function sha256(data: string | Uint8Array): string {
  return createHash("sha256").update(data).digest("hex");
}

/** Hashes each file's bytes; the order of `files` does not matter. */
export async function hashFiles(
  root: string,
  files: readonly string[],
): Promise<readonly HashedFile[]> {
  const hashed = await Promise.all(
    files.map(async (file) => ({
      file: file.replaceAll("\\", "/"),
      sha256: sha256(await readFile(join(root, file))),
    })),
  );

  return hashed.toSorted((a, b) => a.file.localeCompare(b.file));
}

/**
 * One digest over the named parts, each length-prefixed so none can run into
 * the next.
 */
export function digest(parts: readonly string[]): string {
  const hash = createHash("sha256");

  for (const part of parts) {
    hash.update(`${String(part.length)}:${part}\n`);
  }

  return hash.digest("hex");
}

const hashLines = (files: readonly HashedFile[]): string[] =>
  files.map((file) => `${basename(file.file)} ${file.sha256}`);

/** The folder name of an artifact: migrations plus every tool version. */
export function schemaKey(
  migrations: readonly HashedFile[],
  versions: BaselineVersions,
): string {
  return digest([
    String(BASELINE_FORMAT),
    versions.bsb,
    versions.supabaseCli,
    versions.postgres,
    versions.engine,
    ...hashLines(migrations),
  ]);
}

/** The schema key plus the seed files and bucket objects. */
export function seedKey(schema: string, seeds: readonly HashedFile[]): string {
  return digest([
    schema,
    ...seeds.map((file) => `${file.file} ${file.sha256}`),
  ]);
}

/** The leading digits of `<version>_name.sql`. */
function migrationVersion(file: string): string | undefined {
  return /^(\d+)_/.exec(basename(file))?.[1];
}

export type BaselineMatch =
  | { readonly ok: true; readonly pending: readonly string[] }
  | { readonly ok: false; readonly reason: string };

/**
 * Decides whether the migrations on disk may start from this baseline: every
 * migration it holds must exist unchanged, and every other file must sort after
 * the last one it holds (an older-dated file would run in a different order
 * than a full replay). `pending` lists the files `migration up` still runs.
 */
export function matchBaseline(
  manifest: BaselineManifest,
  current: readonly HashedFile[],
  versions: BaselineVersions,
): BaselineMatch {
  if (manifest.format !== BASELINE_FORMAT) {
    return { ok: false, reason: "the baseline has an older file format" };
  }

  // The diff engine is not compared: it only decided what schema.sql holds.
  for (const name of ["bsb", "supabaseCli", "postgres"] as const) {
    if (manifest.versions[name] !== versions[name]) {
      return {
        ok: false,
        reason: `${name} is ${versions[name]} here and ${manifest.versions[name]} in the baseline`,
      };
    }
  }

  const byName = new Map(current.map((file) => [basename(file.file), file]));

  for (const held of manifest.migrations) {
    const name = basename(held.file);
    const now = byName.get(name);

    if (now === undefined) {
      return { ok: false, reason: `migration ${name} was removed or renamed` };
    }

    if (now.sha256 !== held.sha256) {
      return { ok: false, reason: `migration ${name} was edited` };
    }
  }

  const heldNames = new Set(manifest.migrations.map((m) => basename(m.file)));

  const last = manifest.migrations
    .map((m) => migrationVersion(m.file) ?? "")
    .toSorted()
    .at(-1);

  const pending = current
    .map((file) => basename(file.file))
    .filter((name) => !heldNames.has(name))
    .toSorted();

  for (const name of pending) {
    const version = migrationVersion(name);

    if (version === undefined) {
      return { ok: false, reason: `migration ${name} has no version` };
    }

    if (last !== undefined && version <= last) {
      return {
        ok: false,
        reason: `migration ${name} is dated before the baseline's last migration`,
      };
    }
  }

  return { ok: true, pending };
}

/**
 * Whether the seed snapshot may replace the seed files, given the files now on
 * disk.
 */
export function matchSeed(
  manifest: BaselineManifest,
  seeds: readonly HashedFile[],
  match: BaselineMatch,
): string | undefined {
  if (manifest.seed === undefined) {
    return "the baseline was built without --with-seed";
  }

  if (!match.ok || match.pending.length > 0) {
    return "migrations newer than the baseline would run before the seeds";
  }

  return manifest.seed.key === seedKey(manifest.key, seeds)
    ? undefined
    : "the seed files or bucket objects changed";
}
