import { createHash } from "node:crypto";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import type { IntrospectionSource } from "./source.ts";
import type { Snapshot } from "./types.ts";

import { VERSION } from "../version.ts";
import { catalogFingerprint } from "./fingerprint.ts";
import { TYPEGEN_VERSION } from "./typegen-version.ts";

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
 * fingerprint, the `inputs` (schemas and hooks), the CLI version and the
 * typegen version all match. One file per source keeps the cache from growing. A source that
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
    JSON.stringify([
      VERSION,
      TYPEGEN_VERSION,
      source.describe,
      inputs,
      fingerprint,
    ]),
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
  await writeAtomic(file, JSON.stringify(entry)).catch(() => undefined);
  return snapshot;
}

/**
 * Calls `produce`, or returns the `database.types.ts` cached under `root`
 * for the same `inputs`, CLI version and typegen version. Typegen and oxfmt
 * are most of a `gen` run on a large schema, and their output only depends
 * on the inputs.
 */
export async function cachedDatabaseTypes(
  root: string,
  inputs: unknown,
  produce: () => Promise<string>,
): Promise<string> {
  const key = sha256(JSON.stringify([VERSION, TYPEGEN_VERSION, inputs]));
  const file = resolve(root, CACHE_DIR, "database-types.json");
  const cached: unknown = await readFile(file, "utf8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);
  if (
    typeof cached === "object" &&
    cached !== null &&
    "key" in cached &&
    cached.key === key &&
    "contents" in cached &&
    typeof cached.contents === "string"
  )
    return cached.contents;
  const contents = await produce();
  await writeAtomic(file, JSON.stringify({ key, contents })).catch(
    () => undefined,
  );
  return contents;
}

/** Writes through a temporary file, so a concurrent reader never sees half a file. */
export async function writeAtomic(
  file: string,
  contents: string,
): Promise<void> {
  await mkdir(dirname(file), { recursive: true });
  const temporary = `${file}.${process.pid}-${crypto.randomUUID()}.tmp`;
  try {
    await writeFile(temporary, contents);
    await rename(temporary, file);
  } catch (cause) {
    await rm(temporary, { force: true });
    throw cause;
  }
}
