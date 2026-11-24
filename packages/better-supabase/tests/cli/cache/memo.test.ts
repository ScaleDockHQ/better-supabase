import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  adoptedTables,
  primeAdoption,
} from "../../../src/cli/adopted-columns.ts";
import { installMemo } from "../../../src/cli/cache/memo-backend.ts";
import { cacheRoot, setCacheEnabled } from "../../../src/cli/cache/store.ts";
import {
  clearMemo,
  isMemoized,
  memoStats,
  memoized,
  setMemoBackend,
} from "../../../src/sql/index.ts";

let root = "";

const reset = (): void => {
  memoStats.memory = 0;
  memoStats.stored = 0;
  memoStats.computed = 0;
};

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bsb-memo-"));
  setCacheEnabled(true);
  reset();
});

afterEach(async () => {
  setMemoBackend(undefined);
  clearMemo();
  await rm(root, { recursive: true, force: true });
});

const isNumber = (value: unknown): value is number => typeof value === "number";

describe("memoized", () => {
  it("computes once per input, from memory, then from the file, never for a function", async () => {
    await installMemo(root);
    let calls = 0;

    const compute = (): number => {
      calls += 1;

      return 7;
    };

    expect(memoized("demo", ["a"], isNumber, compute)).toBe(7);
    expect(memoized("demo", ["a"], isNumber, compute)).toBe(7);
    expect(calls).toBe(1);
    expect(memoStats).toMatchObject({ computed: 1, memory: 1, stored: 0 });

    // A new process: the memory is empty and the file answers.
    await installMemo(root);
    expect(memoized("demo", ["a"], isNumber, compute)).toBe(7);
    expect(calls).toBe(1);
    expect(memoStats.stored).toBe(1);

    expect(memoized("demo", ["b"], isNumber, compute)).toBe(7);
    expect(calls).toBe(2);

    memoized("demo", [() => 1], isNumber, compute);
    memoized("demo", [() => 1], isNumber, compute);
    expect(calls).toBe(4);
  });

  it("computes again when a stored value fails its check, and under --no-cache", async () => {
    await installMemo(root);
    memoized("demo", ["a"], isNumber, () => 1);

    const file = join(cacheRoot(root), "memo", "demo.json");

    const stored = JSON.parse(await readFile(file, "utf-8")) as {
      entries: Record<string, unknown>;
    };

    for (const key of Object.keys(stored.entries)) {
      stored.entries[key] = "not a number";
    }

    await writeFile(file, JSON.stringify(stored));
    await installMemo(root);
    expect(memoized("demo", ["a"], isNumber, () => 2)).toBe(2);

    setCacheEnabled(false);
    await installMemo(root);
    expect(memoized("demo", ["a"], isNumber, () => 3)).toBe(3);
  });

  it("tells whether a result is held, in memory or in the file, without computing it", async () => {
    await installMemo(root);
    expect(isMemoized("peek", ["a"], isNumber)).toBe(false);
    memoized("peek", ["a"], isNumber, () => 1);
    expect(isMemoized("peek", ["a"], isNumber)).toBe(true);

    await installMemo(root);
    expect(isMemoized("peek", ["a"], isNumber)).toBe(true);
    expect(
      isMemoized(
        "peek",
        ["a"],
        (value): value is string => typeof value === "string",
      ),
    ).toBe(false);
    expect(isMemoized("peek", [() => 1], isNumber)).toBe(false);
    expect(memoStats.computed).toBe(1);
  });

  it("answers a result it called memoized after the file drops it", async () => {
    await installMemo(root);
    memoized("pinned", ["kept"], isNumber, () => 1);
    await installMemo(root);

    expect(isMemoized("pinned", ["kept"], isNumber)).toBe(true);

    for (let index = 0; index < 60; index += 1) {
      memoized("pinned", [index], isNumber, () => index);
    }

    expect(
      memoized("pinned", ["kept"], isNumber, () => {
        throw new Error("computed a result isMemoized promised");
      }),
    ).toBe(1);
  });

  it("keeps the file small: only the newest results of a name stay", async () => {
    await installMemo(root);

    for (let index = 0; index < 60; index += 1) {
      memoized("many", [index], isNumber, () => index);
    }

    const stored = JSON.parse(
      await readFile(join(cacheRoot(root), "memo", "many.json"), "utf-8"),
    ) as { entries: Record<string, unknown> };

    expect(Object.keys(stored.entries)).toHaveLength(48);
  });
});

describe("the adoption scan", () => {
  it("gives the same tables with the cache, from the file, and without it", async () => {
    const modules = {
      webhooks: {
        tables: { secrets: "public.hook_secrets" },
        options: { secretStorage: "column" },
      },
    };

    const tables = { "public.hook_secrets": "supabase/schemas/hooks.sql" };

    await primeAdoption(modules, tables);
    await installMemo(root);
    const first = adoptedTables(modules, tables);
    expect(memoStats.computed).toBeGreaterThan(0);

    await installMemo(root);
    reset();
    const second = adoptedTables(modules, tables);
    expect(memoStats.stored).toBeGreaterThan(0);
    expect(memoStats.computed).toBe(0);

    setCacheEnabled(false);
    await installMemo(root);
    const fresh = adoptedTables(modules, tables);

    expect(second).toStrictEqual(first);
    expect(fresh).toStrictEqual(first);
  });
});
