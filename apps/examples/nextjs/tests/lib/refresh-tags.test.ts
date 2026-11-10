import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const features = fileURLToPath(new URL("../../src/features", import.meta.url));

/**
 * Domains whose writes change what every other domain reads (restore and purge)
 * or what the session is (roles, sessions): they expire the whole session on
 * purpose (ADR 0615 and 0633).
 */
const SESSION_WIDE = new Set(["roles", "sessions", "trash"]);

/**
 * Reads that belong to the session, not to a domain: the user's own profile,
 * the bench harness and the islands demo. `evictSession` expires them.
 */
const SESSION_READS = new Set(["bench", "islands", "user"]);

const read = (path: string): string => readFileSync(path, "utf-8");

const dirs = readdirSync(features, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name);

describe("refreshCaller tags", () => {
  it("passes tags from every action file, except the session-wide domains", () => {
    const untagged: string[] = [];

    for (const dir of dirs) {
      const file = join(features, dir, `${dir}-actions.ts`);
      let source: string;

      try {
        source = read(file);
      } catch {
        continue;
      }

      const bare = /refreshCaller\(\s*auth\s*\)/.test(source);

      if (bare && !SESSION_WIDE.has(dir)) {
        untagged.push(dir);
      }
    }

    expect(untagged).toEqual([]);
  });

  it("tags every private cached read of a domain that has a cache file", () => {
    const untagged: string[] = [];

    for (const dir of dirs.filter((each) => !SESSION_READS.has(each))) {
      const cacheFile = join(features, dir, `${dir}-cache.ts`);
      const queries = join(features, dir, `${dir}-queries.ts`);
      let source: string;

      try {
        read(cacheFile);
        source = read(queries);
      } catch {
        continue;
      }

      const reads = source.split('"use cache: private"').slice(1);

      for (const [index, body] of reads.entries()) {
        const end = body.search(/\n(?:export )?(?:async )?function /);
        const fn = end === -1 ? body : body.slice(0, end);

        if (!fn.includes("cacheTag(")) {
          untagged.push(`${dir} #${String(index + 1)}`);
        }
      }
    }

    expect(untagged).toEqual([]);
  });
});
