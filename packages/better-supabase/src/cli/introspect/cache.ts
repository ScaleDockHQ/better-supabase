import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import type { IntrospectionSource } from "./source.ts";
import type { Snapshot } from "./types.ts";

import { VERSION } from "../version.ts";
import { catalogFingerprint } from "./fingerprint.ts";

/** Shared with the splinter download cache. */
export const CACHE_DIR = "node_modules/.cache/better-supabase";

const sha256 = (text: string): string =>
  createHash("sha256").update(text).digest("hex");

interface CacheEntry {
  readonly key: string;
  readonly snapshot: Snapshot;
}

function isEntry(value: unknown): value is CacheEntry {
  return (
    typeof value === "object" &&
    value !== null &&
    "key" in value &&
    typeof value.key === "string" &&
    "snapshot" in value &&
    typeof value.snapshot === "object"
  );
}

/**
 * Calls `read`, or returns the snapshot cached under `root` when the catalog
 * fingerprint, the `inputs` (schemas and hooks) and the CLI version all
 * match. One file per source keeps the cache from growing. A source that
 * cannot report a fingerprint is read every time.
 */
export async function cachedIntrospect(
  root: string,
  source: IntrospectionSource,
  inputs: unknown,
  read: () => Promise<Snapshot>,
): Promise<Snapshot> {
  const fingerprint = await catalogFingerprint(source.queryable).catch(
    () => undefined,
  );
  if (fingerprint === undefined) return read();
  const key = sha256(
    JSON.stringify([VERSION, source.describe, inputs, fingerprint]),
  );
  const file = resolve(
    root,
    CACHE_DIR,
    `snapshot-${sha256(source.describe).slice(0, 16)}.json`,
  );
  const cached: unknown = await readFile(file, "utf8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);
  if (isEntry(cached) && cached.key === key) return cached.snapshot;
  const snapshot = await read();
  const entry: CacheEntry = { key, snapshot };
  await mkdir(dirname(file), { recursive: true })
    .then(() => writeFile(file, JSON.stringify(entry)))
    .catch(() => undefined);
  return snapshot;
}
