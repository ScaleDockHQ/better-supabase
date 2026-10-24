import { createHash } from "node:crypto";
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { IntrospectionSource } from "../../../src/cli/introspect/source.ts";
import type { Snapshot } from "../../../src/cli/introspect/types.ts";

import {
  CACHE_DIR,
  cachedDatabaseTypes,
  cachedIntrospect,
  cachedTypesModule,
  lastTypesModule,
  storeTypesModule,
  typesModuleKey,
  writeAtomic,
} from "../../../src/cli/introspect/cache.ts";
import { TYPEGEN_VERSION } from "../../../src/cli/introspect/typegen-version.ts";
import { VERSION } from "../../../src/cli/version.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const snapshot = (name: string) =>
  ({ version: 2, schemas: [name] }) as unknown as Snapshot;

function source(fingerprint: () => string | undefined): IntrospectionSource {
  return {
    describe: "postgresql://db/x",
    close: () => Promise.resolve(),
    queryable: {
      query: async (sql: string) => {
        if (!sql.includes("as fingerprint")) {
          throw new Error(`unexpected ${sql}`);
        }

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
  root = await mkdtemp(join(tmpdir(), "bsb-cache-"));
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

  it("keys the entry on the typegen version and leaves no temporary files", async () => {
    const db = source(() => "a");
    const { read } = reader("typed");
    await cachedIntrospect(root, db, [], read);
    const files = await readdir(join(root, CACHE_DIR));
    expect(files).toEqual([expect.stringMatching(/^snapshot-\w+\.json$/)]);

    const entry = JSON.parse(
      await readFile(join(root, CACHE_DIR, files[0]!), "utf-8"),
    ) as { key: string };

    const key = (typegen: string) =>
      createHash("sha256")
        .update(JSON.stringify([VERSION, typegen, db.describe, [], "a"]))
        .digest("hex");

    expect(entry.key).toBe(key(TYPEGEN_VERSION));
    expect(entry.key).not.toBe(key("0.0.0"));
  });
});

describe("cachedDatabaseTypes", () => {
  it("reuses the output for the same inputs and renders again for others", async () => {
    let calls = 0;

    const produce = () => {
      calls += 1;

      return Promise.resolve(`types ${calls}`);
    };

    expect(await cachedDatabaseTypes(root, ["a"], produce)).toBe("types 1");
    expect(await cachedDatabaseTypes(root, ["a"], produce)).toBe("types 1");
    expect(await cachedDatabaseTypes(root, ["b"], produce)).toBe("types 2");
    await writeFile(join(root, CACHE_DIR, "database-types.json"), "{");
    expect(await cachedDatabaseTypes(root, ["b"], produce)).toBe("types 3");
    expect(calls).toBe(3);
  });
});

describe("cachedTypesModule", () => {
  const config = (generate: () => string) =>
    resolveConfig(
      { gen: { generators: [{ name: "g", apiVersion: 1, generate }] } },
      "/app",
    );

  it("keys on the config, its file and the snapshot", () => {
    const base = typesModuleKey(
      config(() => "a"),
      "x",
      snapshot("public"),
    );

    expect(
      typesModuleKey(
        config(() => "a"),
        "x",
        snapshot("public"),
      ),
    ).toBe(base);
    expect(
      typesModuleKey(
        config(() => "b"),
        "x",
        snapshot("public"),
      ),
    ).not.toBe(base);
    expect(
      typesModuleKey(
        config(() => "a"),
        "y",
        snapshot("public"),
      ),
    ).not.toBe(base);
    expect(
      typesModuleKey(
        config(() => "a"),
        "x",
        snapshot("app"),
      ),
    ).not.toBe(base);
  });

  it("reuses the module for a key and keeps the last one per output", async () => {
    let calls = 0;

    const produce = () => {
      calls += 1;

      return Promise.resolve(`module ${calls}`);
    };

    const output = "src/generated.ts";

    expect(await cachedTypesModule(root, output, "k1", produce)).toBe(
      "module 1",
    );
    expect(await cachedTypesModule(root, output, "k1", produce)).toBe(
      "module 1",
    );
    expect(await cachedTypesModule(root, output, "k2", produce)).toBe(
      "module 2",
    );
    expect(await lastTypesModule(root, output)).toBe("module 2");
    expect(await lastTypesModule(root, "other.ts")).toBeUndefined();

    await storeTypesModule(root, output, "k3", "stored");
    expect(await cachedTypesModule(root, output, "k3", produce)).toBe("stored");
    expect(calls).toBe(2);
    expect(
      (await readdir(join(root, CACHE_DIR))).filter((name) =>
        name.startsWith("types-"),
      ),
    ).toHaveLength(1);
  });
});

describe("writeAtomic", () => {
  it("replaces the file and removes the temporary one when the rename fails", async () => {
    const file = join(root, "nested/out.json");
    await writeAtomic(file, "one");
    await writeAtomic(file, "two");
    expect(await readFile(file, "utf-8")).toBe("two");

    const folder = join(root, "folder");
    await mkdir(join(folder, "child"), { recursive: true });
    await expect(writeAtomic(folder, "x")).rejects.toMatchObject({
      code: expect.any(String),
    });
    expect(await readdir(root)).toEqual(
      expect.not.arrayContaining([expect.stringMatching(/\.tmp$/)]),
    );
  });
});
