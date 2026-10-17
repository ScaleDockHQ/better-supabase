import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { SpecDiagnostic } from "../../spec/index.ts";

import { CACHE_DIR, writeAtomic } from "../introspect/cache.ts";

/** Rendered specs live next to the introspection cache. */
export const SPEC_CACHE_DIR: string = `${CACHE_DIR}/specs`;

export const sha256 = (text: string): string =>
  createHash("sha256").update(text).digest("hex");

/** What a render produced, keyed by everything it read. */
export interface CachedRender {
  readonly key: string;
  readonly text: string;
  readonly diagnostics: readonly SpecDiagnostic[];
  /** Schema findings, present once `validate` ran for this key. */
  readonly schema?: readonly SpecDiagnostic[];
}

function isDiagnostics(value: unknown): value is SpecDiagnostic[] {
  return (
    Array.isArray(value) &&
    value.every(
      (item: unknown) =>
        typeof item === "object" &&
        item !== null &&
        "code" in item &&
        typeof item.code === "string",
    )
  );
}

function isCached(value: unknown): value is CachedRender {
  return (
    typeof value === "object" &&
    value !== null &&
    "key" in value &&
    typeof value.key === "string" &&
    "text" in value &&
    typeof value.text === "string" &&
    "diagnostics" in value &&
    isDiagnostics(value.diagnostics) &&
    (!("schema" in value) || isDiagnostics(value.schema))
  );
}

/** One file per output path keeps the cache from growing. */
function cacheFile(root: string, output: string): string {
  return resolve(root, SPEC_CACHE_DIR, `${sha256(output).slice(0, 16)}.json`);
}

export async function readCachedRender(
  root: string,
  output: string,
  key: string,
): Promise<CachedRender | undefined> {
  const cached: unknown = await readFile(cacheFile(root, output), "utf-8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);
  return isCached(cached) && cached.key === key ? cached : undefined;
}

/** Best effort: a read-only `node_modules` only costs the next run a render. */
export async function writeCachedRender(
  root: string,
  output: string,
  entry: CachedRender,
): Promise<void> {
  await writeAtomic(cacheFile(root, output), JSON.stringify(entry)).catch(
    () => undefined,
  );
}
