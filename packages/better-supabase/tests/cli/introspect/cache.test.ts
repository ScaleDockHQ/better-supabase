import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { IntrospectionSource } from "../../../src/cli/introspect/source.ts";
import type { Snapshot } from "../../../src/cli/introspect/types.ts";

import {
  CACHE_DIR,
  cachedIntrospect,
} from "../../../src/cli/introspect/cache.ts";

const snapshot = (name: string) =>
  ({ version: 2, schemas: [name] }) as unknown as Snapshot;

function source(fingerprint: () => string | undefined): IntrospectionSource {
  return {
    describe: "postgresql://db/x",
    close: () => Promise.resolve(),
    queryable: {
      query: async (sql: string) => {
        if (!sql.includes("as fingerprint"))
          throw new Error(`unexpected ${sql}`);
        const value = fingerprint();
        return { rows: value === undefined ? [] : [{ fingerprint: value }] };
      },
    },
  };
}

/** A `read` that returns the next name each call and counts the calls. */
function reader(...names: string[]) {
  let calls = 0;
  return {
    read: () => {
      const name = names[Math.min(calls, names.length - 1)]!;
      calls += 1;
      return Promise.resolve(snapshot(name));
    },
    calls: () => calls,
  };
}

let root: string;
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bs-cache-"));
});
afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

describe("cachedIntrospect", () => {
  it("reuses the snapshot while the fingerprint is unchanged", async () => {
    let fingerprint = "a";
    const db = source(() => fingerprint);
    const { read, calls } = reader("first", "second");

    expect(await cachedIntrospect(root, db, ["public"], read)).toEqual(
      snapshot("first"),
    );
    expect(await cachedIntrospect(root, db, ["public"], read)).toEqual(
      snapshot("first"),
    );
    expect(calls()).toBe(1);

    fingerprint = "b";
    expect(await cachedIntrospect(root, db, ["public"], read)).toEqual(
      snapshot("second"),
    );
    expect(calls()).toBe(2);
    expect(await readdir(join(root, CACHE_DIR))).toHaveLength(1);
  });

  it("reads again for other inputs", async () => {
    const db = source(() => "a");
    const { read, calls } = reader("any");
    await cachedIntrospect(root, db, [["public"], []], read);
    await cachedIntrospect(root, db, [["public", "api"], []], read);
    await cachedIntrospect(root, db, [["public", "api"], ["hook"]], read);
    expect(calls()).toBe(3);
  });

  it("reads every time when the source has no fingerprint", async () => {
    const db = source(() => undefined);
    const { read, calls } = reader("any");
    await cachedIntrospect(root, db, [], read);
    await cachedIntrospect(root, db, [], read);
    expect(calls()).toBe(2);
  });

  it("returns the snapshot when the cache cannot be written", async () => {
    const db = source(() => "a");
    const { read } = reader("unsaved");
    await writeFile(join(root, "node_modules"), "a file, not a folder");
    expect(await cachedIntrospect(root, db, [], read)).toEqual(
      snapshot("unsaved"),
    );
  });

  it("ignores a cache file it cannot read", async () => {
    const db = source(() => "a");
    const { read, calls } = reader("fresh");
    await cachedIntrospect(root, db, [], read);
    const [file] = await readdir(join(root, CACHE_DIR));
    await writeFile(join(root, CACHE_DIR, file!), "{not json");
    expect(await cachedIntrospect(root, db, [], read)).toEqual(
      snapshot("fresh"),
    );
    expect(calls()).toBe(2);
  });
});
