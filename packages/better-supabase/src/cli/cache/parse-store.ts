import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

import type { ParseStore } from "../../sql/index.ts";

/** Entries kept on disk, so the file stays bounded as the schema files change. */
const KEPT = 4096;

interface Stored {
  readonly salt: string;
  readonly entries: Record<string, unknown>;
}

function isStored(value: unknown): value is Stored {
  return (
    typeof value === "object" &&
    value !== null &&
    "salt" in value &&
    typeof value.salt === "string" &&
    "entries" in value &&
    typeof value.entries === "object" &&
    value.entries !== null
  );
}

/** A parse store with the entries it holds and a way to write them. */
export interface DiskParseStore extends ParseStore {
  /** Writes the file when this run added an entry; returns whether it did. */
  readonly flush: () => boolean;
}

/**
 * Keeps parse results in `<cache>/parse/files.json`, keyed by the content hash
 * and parser version `createParseCache` builds. The file holds the entries this
 * run used last, so the oldest drop first, and it is discarded when `salt` (the
 * CLI version and a hash of the generator's files) differs. Reads are
 * synchronous because the model's callers are.
 */
export function createDiskParseStore(
  folder: string,
  salt: string,
): DiskParseStore {
  const file = resolve(folder, "parse", "files.json");
  const entries = new Map<string, unknown>();
  const used = new Set<string>();
  let added = false;

  try {
    const parsed: unknown = JSON.parse(readFileSync(file, "utf-8"));

    if (isStored(parsed) && parsed.salt === salt) {
      for (const [key, value] of Object.entries(parsed.entries)) {
        entries.set(key, value);
      }
    }
  } catch {
    // No file, or one that can't be read: parse everything again.
  }

  return {
    get(key) {
      const value = entries.get(key);

      if (value !== undefined) {
        used.add(key);
      }

      return value;
    },
    set(key, value) {
      entries.set(key, value);
      used.add(key);
      added = true;
    },
    flush() {
      if (!added) {
        return false;
      }

      added = false;

      const ordered = [
        ...[...entries].filter(([key]) => !used.has(key)),
        ...[...entries].filter(([key]) => used.has(key)),
      ].slice(-KEPT);

      const temporary = `${file}.${String(process.pid)}.tmp`;

      try {
        mkdirSync(dirname(file), { recursive: true });
        writeFileSync(
          temporary,
          JSON.stringify({ salt, entries: Object.fromEntries(ordered) }),
        );
        renameSync(temporary, file);
      } catch {
        // A cache that can't be written costs time, never correctness.
      }

      return true;
    },
  };
}
