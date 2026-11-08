import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { BlockSqlFile, BlockSqlLayout } from "../../sql/index.ts";

import {
  blockFileState,
  moduleRenderStats,
  renderBlocks,
  renderKey,
} from "../../sql/index.ts";
import { CACHE_DIR } from "../introspect/cache.ts";
import { VERSION } from "../version.ts";
import { generatorHash } from "./generator-hash.ts";

interface Entry {
  readonly key: string;
  readonly files: readonly BlockSqlFile[];
}

/**
 * Rendered files by key for this process: every command renders the same input
 * a few times.
 */
const memory = new Map<string, readonly BlockSqlFile[]>();

/**
 * Renders and cache lookups this process made, for tests and the bench:
 * `modules` counts the module files a fresh render produced (not the ones the
 * per-module cache served), so a run served from either cache reports zero.
 */
export const renderStats = { fresh: 0, memory: 0, disk: 0, modules: 0 };

function isFile(value: unknown): value is BlockSqlFile {
  return (
    typeof value === "object" &&
    value !== null &&
    "path" in value &&
    typeof value.path === "string" &&
    "contents" in value &&
    typeof value.contents === "string" &&
    "kind" in value &&
    "module" in value
  );
}

function isEntry(value: unknown): value is Entry {
  return (
    typeof value === "object" &&
    value !== null &&
    "key" in value &&
    typeof value.key === "string" &&
    "files" in value &&
    Array.isArray(value.files) &&
    value.files.every(isFile)
  );
}

/** A fresh render, and how many of its files came from the module cache. */
function renderCounted(
  names: readonly string[],
  layout: BlockSqlLayout,
): BlockSqlFile[] {
  const served = moduleRenderStats.served;
  const files = renderBlocks(names, layout);
  renderStats.modules += files.length - (moduleRenderStats.served - served);

  return files;
}

/** A cached file is used only when its `@bsb-hash` line still matches its body. */
const intact = (files: readonly BlockSqlFile[]): boolean =>
  files.every((file) => blockFileState(file.contents) === "clean");

const cachePath = (config: ResolvedConfig): string =>
  resolve(config.root, CACHE_DIR, "render-blocks.json");

/** Options of the cached render. */
export interface RenderCacheOptions {
  /** `--no-cache`: render fresh and leave the cache alone. */
  readonly cache?: boolean;
}

/**
 * `renderBlocks` behind a content-addressed cache. The key covers the block
 * names, the layout, the CLI version and a hash of the generator's files, so
 * any change to the input renders fresh. The disk entry is one file,
 * overwritten in place, and is dropped when a file's hash line no longer
 * matches its body. A layout with a function in it can't be keyed and always
 * renders fresh.
 */
export async function renderBlocksCached(
  config: ResolvedConfig,
  names: readonly string[],
  layout: BlockSqlLayout,
  options: RenderCacheOptions = {},
): Promise<BlockSqlFile[]> {
  const key =
    options.cache === false
      ? undefined
      : renderKey(names, layout, `${VERSION}:${await generatorHash()}`);

  if (key === undefined) {
    renderStats.fresh += 1;

    return renderCounted(names, layout);
  }

  const held = memory.get(key);

  if (held !== undefined) {
    renderStats.memory += 1;

    return [...held];
  }

  const file = cachePath(config);

  const stored: unknown = await readFile(file, "utf-8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);

  if (isEntry(stored) && stored.key === key && intact(stored.files)) {
    memory.set(key, stored.files);
    renderStats.disk += 1;

    return [...stored.files];
  }

  renderStats.fresh += 1;
  const files = renderCounted(names, layout);
  memory.set(key, files);
  const entry: Entry = { key, files };
  const temporary = `${file}.${String(process.pid)}.tmp`;

  await mkdir(dirname(file), { recursive: true })
    .then(() => writeFile(temporary, JSON.stringify(entry)))
    .then(() => rename(temporary, file))
    .catch(() => rm(temporary, { force: true }));

  return [...files];
}

/** The cache option of a command's flags. */
export const cacheOf = (flags: {
  readonly "no-cache"?: boolean | undefined;
}): RenderCacheOptions => ({ cache: flags["no-cache"] !== true });

/** Forgets the in-process entries, so a test reads the disk. */
export function clearRenderMemory(): void {
  memory.clear();
}
