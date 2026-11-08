import type { BlockSqlFile, BlockSqlLayout } from "../module-types.ts";
import type { Read } from "./read-tracking.ts";

import { createReadTracker, readsHold } from "./read-tracking.ts";

/**
 * What the cache keeps for one rendered module: the files, and the reads that
 * produced them. The entry is valid for any layout in which every read still
 * sees what it saw.
 */
export interface ModuleRenderEntry {
  readonly reads: readonly Read[];
  readonly files: readonly BlockSqlFile[];
}

/**
 * Where module renders live between runs. The CLI installs one that reads and
 * writes a file, so `src/sql` stays free of Node built-ins. `salt` is what the
 * generator is (its version and a hash of its files): an entry rendered by
 * other code is never served.
 */
export interface ModuleRenderStore {
  readonly salt: string;
  readonly get: (id: string) => unknown;
  readonly set: (id: string, entry: ModuleRenderEntry) => void;
}

interface State {
  store: ModuleRenderStore | undefined;
  readonly stats: {
    hits: number;
    misses: number;
    uncacheable: number;
    /** Files in the entries served from the store. */
    served: number;
  };
}

const STATE_KEY: unique symbol = Symbol.for("better-supabase.module-render");

// The bundle can hold this module twice (the `./sql` entry and the CLI chunks),
// so the state lives on `globalThis`, where both copies find the same one.
// SAFETY: only this module writes STATE_KEY on globalThis, and it writes a State.
const shared = globalThis as { [STATE_KEY]?: State };

shared[STATE_KEY] ??= {
  store: undefined,
  stats: { hits: 0, misses: 0, uncacheable: 0, served: 0 },
};

const state: State = shared[STATE_KEY];

/**
 * Module renders served from the store (`hits`), rendered with tracking
 * (`misses`), and rendered but too dependent on a function to store
 * (`uncacheable`); `served` counts the files the hits returned. For tests and
 * the bench.
 */
export const moduleRenderStats: State["stats"] = state.stats;

/** Installs the store `renderBlocks` reads and writes, or removes it. */
export function setModuleRenderStore(
  store: ModuleRenderStore | undefined,
): void {
  state.store = store;
}

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

function isRead(value: unknown): value is Read {
  return (
    typeof value === "object" &&
    value !== null &&
    "root" in value &&
    (value.root === "layout" || value.root === "installed") &&
    "path" in value &&
    Array.isArray(value.path) &&
    "kind" in value &&
    typeof value.kind === "string" &&
    "seen" in value &&
    typeof value.seen === "string"
  );
}

function isEntry(value: unknown): value is ModuleRenderEntry {
  return (
    typeof value === "object" &&
    value !== null &&
    "reads" in value &&
    Array.isArray(value.reads) &&
    value.reads.every(isRead) &&
    "files" in value &&
    Array.isArray(value.files) &&
    value.files.every(isFile)
  );
}

/**
 * `render(layout, installed)` for the module instance `id`, from the store when
 * every input the earlier render read is unchanged. A miss renders through a
 * read-tracking view of the layout and the installed names, so the entry holds
 * exactly what this render depended on: a change to anything else leaves it
 * valid. Without a store the render runs as it is.
 *
 * An error thrown while tracking renders the real input once more, so the
 * caller sees the render's own error and nothing is stored.
 */
export function renderModuleCached(
  id: string,
  layout: BlockSqlLayout,
  installed: readonly string[],
  render: (
    layout: BlockSqlLayout,
    installed: readonly string[],
  ) => BlockSqlFile[],
): BlockSqlFile[] {
  const { store } = state;

  if (store === undefined) {
    return render(layout, installed);
  }

  const key = `${store.salt}:${id}`;
  const held = store.get(key);

  if (isEntry(held) && readsHold(held.reads, { layout, installed })) {
    state.stats.hits += 1;
    state.stats.served += held.files.length;

    return [...held.files];
  }

  const tracker = createReadTracker();
  let files: BlockSqlFile[];

  try {
    files = render(
      tracker.wrap("layout", layout),
      tracker.wrap("installed", installed),
    );
  } catch {
    // A render may do something a proxy can't take (`structuredClone` throws on
    // one). Render the real input again: a genuine error is thrown from there,
    // and nothing is stored.
    state.stats.uncacheable += 1;

    return render(layout, installed);
  }

  if (tracker.uncacheable()) {
    state.stats.uncacheable += 1;

    return files;
  }

  state.stats.misses += 1;
  store.set(key, { reads: tracker.reads(), files });

  return files;
}
