import { createHash } from "node:crypto";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
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
 * typegen version all match. One file per source keeps the cache from growing.
 * A source that cannot report a fingerprint is read every time.
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

  if (fingerprint === undefined) {
    return read();
  }

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

  const cached: unknown = await readFile(file, "utf-8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);

  if (isEntry(cached) && cached.key === key) {
    return cached.snapshot;
  }

  const snapshot = await read();
  const entry: CacheEntry = { key, snapshot };
  await writeAtomic(file, JSON.stringify(entry)).catch(() => undefined);

  return snapshot;
}

/**
 * Calls `produce`, or returns the `database.types.ts` cached under `root` for
 * the same `inputs`, CLI version and typegen version. Typegen and oxfmt are
 * most of a `gen` run on a large schema, and their output only depends on the
 * inputs.
 */
export async function cachedDatabaseTypes(
  root: string,
  inputs: unknown,
  produce: () => Promise<string>,
): Promise<string> {
  const key = sha256(JSON.stringify([VERSION, TYPEGEN_VERSION, inputs]));
  const file = resolve(root, CACHE_DIR, "database-types.json");

  const cached: unknown = await readFile(file, "utf-8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);

  if (
    typeof cached === "object" &&
    cached !== null &&
    "key" in cached &&
    cached.key === key &&
    "contents" in cached &&
    typeof cached.contents === "string"
  ) {
    return cached.contents;
  }

  const contents = await produce();
  await writeAtomic(file, JSON.stringify({ key, contents })).catch(
    () => undefined,
  );

  return contents;
}

/**
 * JSON for the resolved config with each function as its source text, so
 * generators and plugins count toward the key. Options a factory closes over
 * are invisible here, which is why the key also takes the config file's text.
 */
function configJson(config: ResolvedConfig): string {
  return JSON.stringify(config, (_key, value: unknown) =>
    typeof value === "function"
      ? String(value)
      : typeof value === "bigint"
        ? `${value}n`
        : value,
  );
}

/**
 * The key of the module the content mapper serves: the CLI and typegen
 * versions, the config (resolved, and the text of its file) and the snapshot.
 * `gen` and the mapper compute the same key, so a `gen` run warms the mapper.
 */
export function typesModuleKey(
  config: ResolvedConfig,
  configText: string | undefined,
  snapshot: Snapshot,
): string {
  return sha256(
    JSON.stringify([
      VERSION,
      TYPEGEN_VERSION,
      configText ?? null,
      sha256(configJson(config)),
      sha256(JSON.stringify(snapshot)),
    ]),
  );
}

const typesModuleFile = (root: string, output: string): string =>
  resolve(root, CACHE_DIR, `types-${sha256(output).slice(0, 16)}.json`);

async function readTypesModule(
  root: string,
  output: string,
): Promise<{ readonly key: string; readonly contents: string } | undefined> {
  const cached: unknown = await readFile(typesModuleFile(root, output), "utf-8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);

  return typeof cached === "object" &&
    cached !== null &&
    "key" in cached &&
    typeof cached.key === "string" &&
    "contents" in cached &&
    typeof cached.contents === "string"
    ? { key: cached.key, contents: cached.contents }
    : undefined;
}

/**
 * Stores the module the content mapper serves for `output`. One file per
 * generated module keeps the cache from growing.
 */
export async function storeTypesModule(
  root: string,
  output: string,
  key: string,
  contents: string,
): Promise<void> {
  await writeAtomic(
    typesModuleFile(root, output),
    JSON.stringify({ key, contents }),
  ).catch(() => undefined);
}

/**
 * Calls `produce`, or returns the module cached for `output` under the same
 * `key` (see `typesModuleKey`).
 */
export async function cachedTypesModule(
  root: string,
  output: string,
  key: string,
  produce: () => Promise<string>,
): Promise<string> {
  const cached = await readTypesModule(root, output);

  if (cached?.key === key) {
    return cached.contents;
  }

  const contents = await produce();
  await storeTypesModule(root, output, key, contents);

  return contents;
}

/**
 * The module last cached for `output`, whatever its key: what the content
 * mapper serves while the schema source can't be read.
 */
export async function lastTypesModule(
  root: string,
  output: string,
): Promise<string | undefined> {
  return (await readTypesModule(root, output))?.contents;
}

/**
 * Writes through a temporary file, so a concurrent reader never sees half a
 * file.
 */
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
