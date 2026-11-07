import { existsSync } from "node:fs";
import { readdir, rm, stat } from "node:fs/promises";
import { resolve } from "node:path";

/**
 * Where the CLI keeps its cache, relative to the project root. Shared with the
 * splinter download cache.
 */
export const CACHE_DIR = "node_modules/.cache/better-supabase";

let enabled = true;

/**
 * Whether this run reads and writes the cache. `run()` sets it from
 * `--no-cache` before each command, so one run never changes the next.
 */
export function setCacheEnabled(on: boolean): void {
  enabled = on;
}

export const cacheEnabled = (): boolean => enabled;

/** The folder the cache lives in for the project at `root`. */
export const cacheRoot = (root: string): string => resolve(root, CACHE_DIR);

/** What `cache purge` removed. */
export interface PurgeReport {
  readonly folder: string;
  /** The entries removed: the cache's files and folders, by name. */
  readonly removed: readonly string[];
  readonly bytes: number;
}

async function sizeOf(path: string): Promise<number> {
  const info = await stat(path).catch(() => undefined);

  if (info === undefined) {
    return 0;
  }

  if (!info.isDirectory()) {
    return info.size;
  }

  const names = await readdir(path).catch(() => []);

  const sizes = await Promise.all(
    names.map((name) => sizeOf(resolve(path, name))),
  );

  return sizes.reduce((total, size) => total + size, 0);
}

/** The names of the cache's files and folders under `root`, sorted. */
export async function listCache(root: string): Promise<string[]> {
  const names = await readdir(cacheRoot(root)).catch((): string[] => []);

  return names.toSorted();
}

/** The bytes the cache takes under `root`. */
export const cacheSize = (root: string): Promise<number> =>
  sizeOf(cacheRoot(root));

/**
 * Deletes everything the CLI caches under `root`: the rendered modules, the
 * parsed schema files, the catalog snapshot and the downloaded lints. The next
 * run rebuilds what it needs.
 */
export async function purgeCache(root: string): Promise<PurgeReport> {
  const folder = cacheRoot(root);

  if (!existsSync(folder)) {
    return { folder, removed: [], bytes: 0 };
  }

  const removed = await listCache(root);
  const bytes = await cacheSize(root);
  await rm(folder, { recursive: true, force: true });

  return { folder, removed, bytes };
}
