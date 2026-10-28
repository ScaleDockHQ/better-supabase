// A Next.js `cacheHandlers` handler over one directory: entries and the tags
// manifest are files, so every instance that points at the directory reads
// what another one wrote, and a tag one instance expires is expired on all.
// It shows the handler contract; a deployment uses Vercel's handler or one
// over Redis. Node loads it with type stripping, so it stays erasable syntax
// with explicit `.ts` and `node:` imports.
import type {
  CacheEntry,
  CacheHandler,
} from "next/dist/server/lib/cache-handlers/types";

import { Buffer } from "node:buffer";
import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const TAGS_FILE = "tags.json";

interface TagState {
  stale?: number;
  expired?: number;
}

type StoredEntry = Omit<CacheEntry, "value"> & { readonly value: string };

export function createFileCacheHandler(dir: string): CacheHandler {
  const pendingSets = new Map<string, Promise<void>>();
  let manifest: Record<string, TagState> = {};
  const dev = process.env.NODE_ENV === "development";

  const fileFor = (key: string) =>
    path.join(dir, `${createHash("sha256").update(key).digest("hex")}.json`);

  // Writes through a temporary file, so a reader in the other instance never
  // sees half a file.
  const writeAtomic = async (file: string, contents: string) => {
    await mkdir(dir, { recursive: true });
    const temporary = `${file}.${process.pid}.${randomUUID()}`;
    await writeFile(temporary, contents);
    await rename(temporary, file);
  };

  const readManifest = async () => {
    try {
      // SAFETY: only `updateTags` below writes the manifest.
      manifest = JSON.parse(
        await readFile(path.join(dir, TAGS_FILE), "utf-8"),
      ) as Record<string, TagState>;
    } catch {
      manifest = {};
    }
  };

  const expired = (tags: readonly string[], timestamp: number) =>
    tags.some((tag) => {
      const at = manifest[tag]?.expired;

      return at !== undefined && at <= Date.now() && at > timestamp;
    });

  const stale = (tags: readonly string[], timestamp: number) =>
    tags.some((tag) => (manifest[tag]?.stale ?? 0) > timestamp);

  return {
    async get(cacheKey) {
      await pendingSets.get(cacheKey);

      let stored: StoredEntry;

      try {
        // SAFETY: only `set` below writes these files.
        stored = JSON.parse(
          await readFile(fileFor(cacheKey), "utf-8"),
        ) as StoredEntry;
      } catch {
        return;
      }

      const { value, ...entry } = stored;
      const maxAge = dev ? entry.expire : entry.revalidate;

      if (entry.expire < 0 || Date.now() > entry.timestamp + maxAge * 1000) {
        return;
      }

      if (expired(entry.tags, entry.timestamp)) {
        return;
      }

      const bytes = new Uint8Array(Buffer.from(value, "base64"));

      return {
        ...entry,
        revalidate: stale(entry.tags, entry.timestamp) ? -1 : entry.revalidate,
        value: new ReadableStream<Uint8Array>({
          start(controller) {
            controller.enqueue(bytes);
            controller.close();
          },
        }),
      };
    },

    async set(cacheKey, pendingEntry) {
      let done = () => {};

      pendingSets.set(
        cacheKey,
        new Promise<void>((resolve) => {
          done = resolve;
        }),
      );

      try {
        const entry = await pendingEntry;

        // A production `expire: 0` entry is regenerated on every read.
        if (!dev && entry.expire === 0) {
          return;
        }

        const body = Buffer.from(
          await new Response(entry.value).arrayBuffer(),
        ).toString("base64");

        const { value: _, ...metadata } = entry;
        const stored: StoredEntry = { ...metadata, value: body };

        await writeAtomic(fileFor(cacheKey), JSON.stringify(stored));
      } catch {
        // A failed write is a miss on the next read.
      } finally {
        done();
        pendingSets.delete(cacheKey);
      }
    },

    // Next calls this once per request: the other instance's expirations
    // arrive here.
    refreshTags() {
      return readManifest();
    },

    getExpiration(tags) {
      return Promise.resolve(
        Math.max(0, ...tags.map((tag) => manifest[tag]?.expired ?? 0)),
      );
    },

    async updateTags(tags, durations) {
      await readManifest();
      const now = Date.now();

      for (const tag of tags) {
        const current = manifest[tag] ?? {};

        if (!durations) {
          manifest[tag] = { ...current, expired: now };
          continue;
        }

        const next: TagState = { ...current, stale: now };

        if (durations.expire !== undefined) {
          next.expired = now + durations.expire * 1000;
        }

        manifest[tag] = next;
      }

      await writeAtomic(path.join(dir, TAGS_FILE), JSON.stringify(manifest));
    },
  };
}
