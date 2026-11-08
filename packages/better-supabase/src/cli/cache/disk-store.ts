import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

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

/** A file of entries that is read once and written once. */
export interface DiskStore {
  readonly get: (key: string) => unknown;
  readonly set: (key: string, value: unknown) => void;
  /** Writes the file when this run added an entry; returns whether it did. */
  readonly flush: () => boolean;
}

/**
 * Keeps entries in `<folder>/<name>` as `{ salt, entries }`. The file is read
 * the first time an entry is asked for, and written by `flush` with the entries
 * this run used last, so the oldest drop first once there are more than `kept`.
 * It is discarded when `salt` (the CLI version and a hash of the generator's
 * files) differs. Reads are synchronous because the generator's callers are.
 */
export function createDiskStore(options: {
  readonly folder: string;
  readonly name: string;
  readonly salt: string;
  readonly kept: number;
}): DiskStore {
  const file = resolve(options.folder, options.name);
  const entries = new Map<string, unknown>();
  const used = new Set<string>();
  let opened = false;
  let added = false;

  const open = (): void => {
    if (opened) {
      return;
    }

    opened = true;

    try {
      const parsed: unknown = JSON.parse(readFileSync(file, "utf-8"));

      if (isStored(parsed) && parsed.salt === options.salt) {
        for (const [key, value] of Object.entries(parsed.entries)) {
          entries.set(key, value);
        }
      }
    } catch {
      // No file, or one that can't be read: render or parse everything again.
    }
  };

  return {
    get(key) {
      open();
      const value = entries.get(key);

      if (value !== undefined) {
        used.add(key);
      }

      return value;
    },
    set(key, value) {
      open();
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
      ].slice(-options.kept);

      const temporary = `${file}.${String(process.pid)}.tmp`;

      try {
        mkdirSync(dirname(file), { recursive: true });
        writeFileSync(
          temporary,
          JSON.stringify({
            salt: options.salt,
            entries: Object.fromEntries(ordered),
          }),
        );
        renameSync(temporary, file);
      } catch {
        // A cache that can't be written costs time, never correctness.
      }

      return true;
    },
  };
}
