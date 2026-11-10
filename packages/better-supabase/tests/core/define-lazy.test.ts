import { describe, expect, it, vi } from "vitest";

import type { SchemaMeta } from "../../src/schema/types.ts";

import { ensureFunctions, lazyRepository } from "../../src/core/define-lazy.ts";
import { createSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";

function freshMeta(): SchemaMeta {
  return { ...createSupabase(schema).meta };
}

function loadedTable(
  meta: SchemaMeta,
): SchemaMeta["tables"][string] & { readonly key: string } {
  const [first] = Object.values(meta.tables);

  if (!first) {
    throw new Error("the fixture has no table");
  }

  return { ...first, key: "lazyItems" };
}

type Method = (...args: unknown[]) => Promise<unknown>;

// SAFETY: lazyRepository answers every string key with a method.
const call = (
  repo: Record<string, unknown>,
  name: string,
  ...args: unknown[]
) => (repo[name] as Method)(...args);

describe("lazyRepository", () => {
  it("loads the table once and runs the method on the built repository", async () => {
    const meta = freshMeta();
    const table = loadedTable(meta);
    const load = vi.fn(() => Promise.resolve(table));
    const register = vi.fn();
    const list = vi.fn((...args: unknown[]) => Promise.resolve(ok(args)));
    const build = vi.fn(() => ({ list }));
    const repo = lazyRepository(meta, {}, "lazyItems", load, build, register);

    const first = await call(repo, "list", 1);
    const second = await call(repo, "list", 2);

    expect(first).toEqual(ok([1]));
    expect(second).toEqual(ok([2]));
    expect(load).toHaveBeenCalledOnce();
    expect(register).toHaveBeenCalledExactlyOnceWith(table);
  });

  it("is not thenable and ignores symbol keys", () => {
    const meta = freshMeta();

    const repo = lazyRepository(
      meta,
      {},
      "lazyItems",
      () => Promise.resolve(loadedTable(meta)),
      () => ({}),
      vi.fn(),
    );

    expect(repo["then"]).toBeUndefined();
    expect(repo[Symbol.iterator as never]).toBeUndefined();
  });

  it("reports a name that is not a repository method", async () => {
    const meta = freshMeta();

    const repo = lazyRepository(
      meta,
      {},
      "lazyItems",
      () => Promise.resolve(loadedTable(meta)),
      () => ({ size: 3 }),
      vi.fn(),
    );

    const result = await call(repo, "size");

    expect(result).toMatchObject({
      ok: false,
      error: { message: "better-supabase: lazyItems.size is not a method" },
    });
  });

  it("retries a load that failed", async () => {
    const meta = freshMeta();
    const table = loadedTable(meta);

    const load = vi
      .fn<() => Promise<typeof table>>()
      .mockRejectedValueOnce(new Error("offline"))
      .mockResolvedValue(table);

    const repo = lazyRepository(
      meta,
      {},
      "lazyItems",
      load,
      () => ({ list: () => Promise.resolve(ok("rows")) }),
      vi.fn(),
    );

    expect(await call(repo, "list")).toMatchObject({
      ok: false,
      error: { message: "offline" },
    });
    expect(await call(repo, "list")).toEqual(ok("rows"));
    expect(load).toHaveBeenCalledTimes(2);
  });
});

describe("ensureFunctions", () => {
  const fn = {
    name: "lazy_fn",
    schema: "public",
    args: [],
    returns: "int4",
    returnsSet: false,
    volatility: "stable",
  } as const;

  it("loads the functions once and installs them", async () => {
    const loadFunctions = vi.fn(() => Promise.resolve({ lazyFn: fn }));
    const meta: SchemaMeta = { ...freshMeta(), functions: {}, loadFunctions };

    await Promise.all([ensureFunctions(meta), ensureFunctions(meta)]);
    await ensureFunctions(meta);

    expect(loadFunctions).toHaveBeenCalledOnce();
    expect(meta.functions["lazyFn"]).toEqual(fn);
  });

  it("does nothing without a loader", async () => {
    const meta: SchemaMeta = { ...freshMeta(), functions: {} };

    await ensureFunctions(meta);

    expect(meta.functions).toEqual({});
  });
});
