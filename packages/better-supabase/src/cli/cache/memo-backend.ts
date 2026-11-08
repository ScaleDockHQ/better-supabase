import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

import type { DiskModuleStore } from "./module-store.ts";
import type { DiskParseStore } from "./parse-store.ts";

import {
  clearMemo,
  setMemoBackend,
  setModuleRenderStore,
  setParseStore,
} from "../../sql/index.ts";
import { generatorHash } from "../sql/generator-hash.ts";
import { VERSION } from "../version.ts";
import { createDiskModuleStore } from "./module-store.ts";
import { createDiskParseStore } from "./parse-store.ts";
import { cacheEnabled, cacheRoot } from "./store.ts";

/** Results kept per namespace, newest last, so the file stays small. */
const KEPT = 48;

interface Namespace {
  readonly order: string[];
  readonly entries: Record<string, unknown>;
}

function isNamespace(value: unknown): value is Namespace {
  return (
    typeof value === "object" &&
    value !== null &&
    "order" in value &&
    Array.isArray(value.order) &&
    "entries" in value &&
    typeof value.entries === "object" &&
    value.entries !== null
  );
}

/**
 * Keeps `memoized` results in `<cache>/memo/<namespace>.json`, one file per
 * namespace holding its last results. Reads are synchronous because the
 * generator's callers are.
 */
function diskBackend(folder: string, salt: string) {
  const loaded = new Map<string, Namespace>();

  const fileOf = (namespace: string): string =>
    resolve(folder, "memo", `${namespace}.json`);

  const open = (namespace: string): Namespace => {
    const held = loaded.get(namespace);

    if (held !== undefined) {
      return held;
    }

    let parsed: unknown;

    try {
      parsed = JSON.parse(readFileSync(fileOf(namespace), "utf-8"));
    } catch {
      parsed = undefined;
    }

    const opened = isNamespace(parsed) ? parsed : { order: [], entries: {} };
    loaded.set(namespace, opened);

    return opened;
  };

  return {
    salt,
    get: (namespace: string, key: string): unknown =>
      open(namespace).entries[key],
    set: (namespace: string, key: string, value: unknown): void => {
      const record = open(namespace);

      if (!(key in record.entries)) {
        record.order.push(key);
      }

      record.entries[key] = value;

      for (const old of record.order.splice(
        0,
        Math.max(0, record.order.length - KEPT),
      )) {
        delete record.entries[old];
      }

      const file = fileOf(namespace);
      const temporary = `${file}.${String(process.pid)}.tmp`;

      try {
        mkdirSync(dirname(file), { recursive: true });
        writeFileSync(temporary, JSON.stringify(record));
        renameSync(temporary, file);
      } catch {
        // A cache that can't be written costs time, never correctness.
      }
    },
  };
}

let active: { parse: DiskParseStore; modules: DiskModuleStore } | undefined;
let registered = false;

/**
 * Points the generator's `memoized` calls at the project's cache folder, or at
 * nothing when this run has no cache. Call it once the config is known.
 */
export async function installMemo(root: string): Promise<void> {
  clearMemo();
  active?.parse.flush();
  active?.modules.flush();

  if (!cacheEnabled()) {
    setMemoBackend(undefined);
    setParseStore(undefined);
    setModuleRenderStore(undefined);
    active = undefined;

    return;
  }

  const salt = `${VERSION}:${await generatorHash()}`;
  setMemoBackend(diskBackend(cacheRoot(root), salt));
  const parse = createDiskParseStore(cacheRoot(root), salt);
  setParseStore(parse);
  const modules = createDiskModuleStore(cacheRoot(root), salt);
  setModuleRenderStore(modules);
  active = { parse, modules };

  // The stores write once, when the process ends, instead of once per entry.
  if (!registered) {
    registered = true;
    process.once("exit", () => {
      active?.parse.flush();
      active?.modules.flush();
    });
  }
}
