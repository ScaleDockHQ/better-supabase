import { readdir, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";

import type {
  BaselineManifest,
  BaselineMatch,
  BaselineVersions,
  HashedFile,
} from "./key.ts";

import { matchBaseline } from "./key.ts";

/**
 * Where artifacts live unless `--out` or `--from` names a folder: gitignored
 * with `node_modules`.
 */
export function baselineRoot(root: string, folder?: string): string {
  return folder === undefined
    ? join(root, "node_modules", ".cache", "better-supabase", "baseline")
    : resolve(root, folder);
}

export interface ArtifactFiles {
  readonly dir: string;
  readonly manifest: string;
  readonly schema: string;
  readonly data: string;
  readonly snapshot: string;
  readonly seedSchema: string;
  readonly seedSnapshot: string;
  readonly seedData: string;
  readonly seedStorage: string;
}

export function artifactFiles(base: string, key: string): ArtifactFiles {
  const dir = join(base, key);

  return {
    dir,
    manifest: join(dir, "manifest.json"),
    schema: join(dir, "schema.sql"),
    data: join(dir, "data.sql"),
    snapshot: join(dir, "catalog.snapshot"),
    seedSchema: join(dir, "seed", "schema.sql"),
    seedSnapshot: join(dir, "seed", "catalog.snapshot"),
    seedData: join(dir, "seed", "data.sql"),
    seedStorage: join(dir, "seed", "storage.tar.gz"),
  };
}

export async function getManifest(
  file: string,
): Promise<BaselineManifest | undefined> {
  try {
    // SAFETY: the file is written by `baseline build`; matchBaseline checks the format version before anything else is read.
    return JSON.parse(await readFile(file, "utf-8")) as BaselineManifest;
  } catch {
    return undefined;
  }
}

export interface FoundArtifact {
  readonly files: ArtifactFiles;
  readonly manifest: BaselineManifest;
  readonly match: Extract<BaselineMatch, { ok: true }>;
}

export interface ArtifactSearch {
  readonly found: FoundArtifact | undefined;
  /** Why the closest artifact does not fit, when none does. */
  readonly reason: string;
}

/**
 * The artifact in `base` that fits the migrations on disk with the fewest newer
 * migrations left to run. A restored cache can hold several, from older
 * `restore-keys` prefixes.
 */
export async function findArtifact(
  base: string,
  current: readonly HashedFile[],
  versions: BaselineVersions,
): Promise<ArtifactSearch> {
  const names = await readdir(base).catch(() => []);
  let best: FoundArtifact | undefined;
  let reason = `no baseline in ${base}`;

  for (const name of names.toSorted((a, b) => a.localeCompare(b))) {
    const files = artifactFiles(base, name);
    const manifest = await getManifest(files.manifest);

    if (manifest === undefined) {
      continue;
    }

    const match = matchBaseline(manifest, current, versions);

    if (!match.ok) {
      reason = match.reason;
      continue;
    }

    if (
      best === undefined ||
      match.pending.length < best.match.pending.length
    ) {
      best = { files, manifest, match };
    }
  }

  return { found: best, reason };
}
