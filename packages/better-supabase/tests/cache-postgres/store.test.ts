import { describe, expect, it, vi } from "vitest";

import {
  decodeBase64,
  encodeBase64,
  postgresCacheStore,
} from "../../src/cache-postgres/store.ts";

describe("base64", () => {
  it("round-trips bytes past the chunk size", () => {
    const bytes = new Uint8Array(100_000).map((_, index) => index % 256);

    expect(decodeBase64(encodeBase64(bytes))).toEqual(bytes);
  });
});

describe("postgresCacheStore", () => {
  it("returns an error result when the client throws", async () => {
    const client = {
      schema: () => {
        throw new Error("boom");
      },
    };

    // SAFETY: the stub has only the method the store calls first.
    const store = postgresCacheStore({ client: client as never });

    const result = await store.get("k");

    expect(result.ok).toBe(false);
    expect(result.error?.kind).toBe("unexpected");
  });

  it("reads tags in chunks of 128", async () => {
    const calls: string[][] = [];

    const client = {
      schema: () => ({
        from: () => ({
          select: () => ({
            in: (_column: string, tags: string[]) => {
              calls.push(tags);

              return {
                overrideTypes: () =>
                  Promise.resolve({
                    data: [{ tag: tags[0], stale_at: 1, expired_at: 2 }],
                    error: null,
                  }),
              };
            },
          }),
        }),
      }),
    };

    const store = postgresCacheStore({ client: client as never });
    const tags = Array.from({ length: 300 }, (_, index) => `t${String(index)}`);

    const result = await store.tagStates(tags);

    expect(calls.map((call) => call.length)).toEqual([128, 128, 44]);
    expect(result.ok && result.data.size).toBe(3);
  });
});

interface Call {
  readonly target: string;
  readonly ops: [string, ...unknown[]][];
}

type Reply = {
  data?: unknown;
  error?: { message: string; code?: string } | null;
};

/** The reply PostgREST gives for a function it does not know. */
const UNKNOWN_FUNCTION: Reply = {
  error: { code: "PGRST202", message: "Could not find the function" },
};

function scripted(reply: (call: Call) => Reply) {
  const calls: Call[] = [];

  const query = (target: string): unknown => {
    const call: Call = { target, ops: [] };
    calls.push(call);

    const builder: object = new Proxy(
      {},
      {
        get: (_, name) =>
          name === "then"
            ? (
                resolve: (value: unknown) => void,
                reject: (e: unknown) => void,
              ) => {
                try {
                  resolve({ data: null, error: null, ...reply(call) });
                } catch (error) {
                  reject(error);
                }
              }
            : (...args: unknown[]) => {
                call.ops.push([String(name), ...args]);

                return builder;
              },
      },
    );

    return builder;
  };

  const client = {
    schema: (schema: string) => ({
      from: (table: string) => query(`${schema}.${table}`),
      rpc: (name: string, args: unknown) => {
        const builder = query(`${schema}.${name}()`);
        calls.at(-1)?.ops.push(["rpc", args]);

        return builder;
      },
    }),
  };

  return { calls, client: client as never };
}

const op = (call: Call | undefined, name: string) =>
  call?.ops.find(([each]) => each === name)?.slice(1);

describe("postgresCacheStore against the tables", () => {
  it("decodes a stored row and maps a null path to undefined", async () => {
    const { calls, client } = scripted(() => ({
      data: {
        key: "k",
        value: encodeBase64(new Uint8Array([1, 2, 3])),
        tags: ["a"],
        stored_at: 10,
        expires_at: 20,
        path: null,
        meta: { status: 200 },
      },
    }));

    const store = postgresCacheStore({
      client,
      schema: "cache",
      entriesTable: "entries",
    });

    const result = await store.get("k");

    expect(result.ok && result.data).toEqual({
      key: "k",
      value: new Uint8Array([1, 2, 3]),
      tags: ["a"],
      storedAt: 10,
      expiresAt: 20,
      path: undefined,
      meta: { status: 200 },
    });
    expect(calls[0]?.target).toBe("cache.entries");
    expect(op(calls[0], "eq")).toEqual(["key", "k"]);
  });

  it("answers a missing row with undefined and a read error with its message", async () => {
    const missing = postgresCacheStore(scripted(() => ({ data: null })));

    const failing = postgresCacheStore(
      scripted(() => ({ error: { message: "denied" } })),
    );

    const none = await missing.get("k");
    const failed = await failing.get("k");

    expect(none.ok && none.data).toBeUndefined();
    expect(failed.error?.message).toBe("Postgres cache: read failed: denied");
  });

  it("writes an entry as a base64 row with a null path", async () => {
    const { calls, client } = scripted(() => ({}));
    const store = postgresCacheStore({ client });

    const result = await store.set({
      key: "k",
      value: new Uint8Array([104, 105]),
      tags: ["t"],
      storedAt: 1,
      expiresAt: 2,
      meta: {},
    });

    expect(result.ok).toBe(true);
    expect(calls[0]?.target).toBe("public.bsb_cache_entries");
    expect(op(calls[0], "upsert")).toEqual([
      {
        key: "k",
        value: "aGk=",
        tags: ["t"],
        stored_at: 1,
        expires_at: 2,
        path: null,
        meta: {},
      },
    ]);
  });

  it("rounds the fractional timestamps Next.js passes down to whole milliseconds", async () => {
    const { calls, client } = scripted(() => ({}));
    const store = postgresCacheStore({ client });

    await store.set({
      key: "k",
      value: new Uint8Array(),
      tags: [],
      storedAt: 1_795_443_609_045.412,
      expiresAt: 1_795_443_610_045.9,
      meta: {},
    });

    expect(op(calls[0], "upsert")).toMatchObject([
      { stored_at: 1_795_443_609_045, expires_at: 1_795_443_610_045 },
    ]);
  });

  it("turns each failed write, delete and prune into a typed error", async () => {
    const store = postgresCacheStore(
      scripted(() => ({ error: { message: "nope" } })),
    );

    const entry = {
      key: "k",
      value: new Uint8Array(),
      tags: [],
      storedAt: 0,
      expiresAt: 0,
      path: "/p",
      meta: {},
    };

    expect((await store.set(entry)).error?.message).toBe(
      "Postgres cache: write failed: nope",
    );
    expect((await store.deletePath("/p")).error?.message).toBe(
      "Postgres cache: delete failed: nope",
    );
    expect((await store.prune(5)).error?.message).toBe(
      "Postgres cache: prune failed: nope",
    );
    expect((await store.tagStates(["a"])).error?.message).toBe(
      "Postgres cache: tag read failed: nope",
    );
    expect((await store.markTags(["a"])).error?.message).toBe(
      "Postgres cache: tag write failed: nope",
    );
    expect((await store.lookup("k")).error?.message).toBe(
      "Postgres cache: read failed: nope",
    );
    expect((await store.delete("k")).error?.message).toBe(
      "Postgres cache: delete failed: nope",
    );
  });

  it("catches a thrown error in every method", async () => {
    const store = postgresCacheStore(
      scripted(() => {
        throw new Error("down");
      }),
    );

    const messages = await Promise.all([
      store.set({
        key: "k",
        value: new Uint8Array(),
        tags: [],
        storedAt: 0,
        expiresAt: 0,
        meta: {},
      }),
      store.deletePath("/p"),
      store.prune(),
      store.tagStates(["a"]),
      store.markTags(["a"]),
      store.lookup("k"),
    ]).then((results) => results.map((result) => result.error?.message));

    expect(messages).toEqual([
      "Postgres cache: write failed: down",
      "Postgres cache: delete failed: down",
      "Postgres cache: prune failed: down",
      "Postgres cache: tag read failed: down",
      "Postgres cache: tag write failed: down",
      "Postgres cache: read failed: down",
    ]);
  });

  it("deletes by path and prunes entries before now", async () => {
    const { calls, client } = scripted(() => ({}));
    const store = postgresCacheStore({ client });

    expect((await store.deletePath("/orders")).ok).toBe(true);
    expect((await store.prune(123)).ok).toBe(true);
    expect(op(calls[0], "eq")).toEqual(["path", "/orders"]);
    expect(op(calls[1], "lt")).toEqual(["expires_at", 123]);
  });

  it("marks tags in one function call per chunk of 128", async () => {
    const { calls, client } = scripted(() => ({}));
    const store = postgresCacheStore({ client, functionPrefix: "app_cache" });
    const many = Array.from({ length: 130 }, (_, index) => `t${String(index)}`);

    await store.markTags(["a", "a"], { now: 1000 });
    await store.markTags(["a"], { now: 1000, expireSeconds: 10 });
    await store.markTags(["a"], { now: 1000, staleOnly: true });
    await store.markTags(many, { now: 1000 });

    expect(calls.map((call) => call.target)).toEqual(
      Array.from({ length: 5 }, () => "public.app_cache_mark_tags()"),
    );
    expect(calls.slice(0, 3).map((call) => op(call, "rpc")?.[0])).toEqual([
      { p_tags: ["a"], p_mode: "expire", p_expire_seconds: 0, p_now: 1000 },
      { p_tags: ["a"], p_mode: "delay", p_expire_seconds: 10, p_now: 1000 },
      { p_tags: ["a"], p_mode: "stale", p_expire_seconds: 0, p_now: 1000 },
    ]);
  });

  it("reads an entry and its tag states in one function call", async () => {
    const { calls, client } = scripted(() => ({
      data: {
        key: "k",
        value: encodeBase64(new Uint8Array([7])),
        tags: ["a"],
        stored_at: "10",
        expires_at: "20",
        path: "/p",
        meta: {},
        stale: true,
      },
    }));

    const store = postgresCacheStore({ client });
    const found = await store.lookup("k", ["soft"], 15);

    expect(found.ok && found.data).toEqual({
      entry: {
        key: "k",
        value: new Uint8Array([7]),
        tags: ["a"],
        storedAt: 10,
        expiresAt: 20,
        path: "/p",
        meta: {},
      },
      stale: true,
    });
    expect(calls).toHaveLength(1);
    expect(op(calls[0], "rpc")).toEqual([
      { p_key: "k", p_soft_tags: ["soft"], p_now: 15 },
    ]);
  });

  it("falls back to the tables once when the functions are missing", async () => {
    const errors: string[] = [];

    const { calls, client } = scripted((call) => {
      if (call.target.endsWith("()")) {
        return UNKNOWN_FUNCTION;
      }

      return op(call, "in")
        ? { data: [{ tag: "a", stale_at: 5, expired_at: 0 }] }
        : {
            data: {
              key: "k",
              value: "",
              tags: ["a"],
              stored_at: 1,
              expires_at: 99,
              path: null,
              meta: {},
            },
          };
    });

    const store = postgresCacheStore({
      client,
      onError: (error) => errors.push(error.message),
    });

    const first = await store.lookup("k", [], 10);
    const second = await store.lookup("k", [], 10);

    expect(first.ok && first.data?.stale).toBe(true);
    expect(second.ok && second.data?.stale).toBe(true);
    expect(calls.filter((call) => call.target.endsWith("()"))).toHaveLength(1);
    expect(errors).toEqual([
      expect.stringContaining(
        "bsb_cache_get or bsb_cache_mark_tags is missing",
      ),
    ]);
  });

  it("tries the functions again a minute after they were missing", async () => {
    vi.useFakeTimers({ now: 0 });

    try {
      let installed = false;

      const { calls, client } = scripted((call) =>
        call.target.endsWith("()") && !installed ? UNKNOWN_FUNCTION : {},
      );

      const store = postgresCacheStore({ client });

      await store.markTags(["a"]);
      installed = true;
      await store.markTags(["a"]);
      vi.setSystemTime(61_000);
      await store.markTags(["a"]);

      expect(
        calls.map((call) => (call.target.endsWith("()") ? "rpc" : "table")),
      ).toEqual(["rpc", "table", "table", "table", "table", "rpc"]);
    } finally {
      vi.useRealTimers();
    }
  });

  it("takes a lease in one function call and releases only its own", async () => {
    const { calls, client } = scripted((call) =>
      call.target.endsWith("()") ? { data: false } : {},
    );

    const store = postgresCacheStore({ client });
    const leased = await store.lease("k", "me", 1500.7, 10);

    expect(leased.ok && leased.data).toBe(false);
    expect(op(calls[0], "rpc")).toEqual([
      { p_key: "k", p_holder: "me", p_ttl_ms: 1500, p_now: 10 },
    ]);

    expect((await store.release("k", "me")).ok).toBe(true);
    expect(calls[1]?.target).toBe("public.bsb_cache_leases");
    expect(calls[1]?.ops.filter(([name]) => name === "eq")).toEqual([
      ["eq", "key", "k"],
      ["eq", "holder", "me"],
    ]);
  });

  it("lets every caller fill while the lease function is missing", async () => {
    const { calls, client } = scripted(() => UNKNOWN_FUNCTION);
    const store = postgresCacheStore({ client });

    expect((await store.lease("k", "a", 1000)).ok).toBe(true);
    expect(await store.lease("k", "b", 1000)).toMatchObject({ data: true });
    expect((await store.release("k", "a")).ok).toBe(true);
    expect(calls).toHaveLength(1);
  });

  it("reports a failed lease as an error result", async () => {
    const store = postgresCacheStore(
      scripted(() => ({ error: { message: "down" } })),
    );

    const leased = await store.lease("k", "a", 1000);

    expect(!leased.ok && leased.error.message).toContain("lease failed: down");
  });

  it("deletes one entry by key", async () => {
    const { calls, client } = scripted(() => ({}));
    const store = postgresCacheStore({ client });

    expect((await store.delete("k")).ok).toBe(true);
    expect(op(calls[0], "delete")).toEqual([]);
    expect(op(calls[0], "eq")).toEqual(["key", "k"]);
  });

  it("marks tags expired now, stale with a later expiry, or stale only without the function", async () => {
    const { calls, client } = scripted((call) =>
      call.target.endsWith("()")
        ? UNKNOWN_FUNCTION
        : op(call, "select")
          ? { data: [{ tag: "old", stale_at: 1, expired_at: 50_000 }] }
          : {},
    );

    const store = postgresCacheStore({ client, tagsTable: "tags" });

    await store.markTags(["old", "new"], { now: 1000 });
    await store.markTags(["old", "new"], { now: 1000, expireSeconds: 10 });
    await store.markTags(["old", "new"], { now: 1000, staleOnly: true });

    const written = calls
      .filter((call) => op(call, "upsert"))
      .map((call) => op(call, "upsert")?.[0]);

    expect(written).toEqual([
      [
        { tag: "old", stale_at: 1000, expired_at: 1000 },
        { tag: "new", stale_at: 1000, expired_at: 1000 },
      ],
      [
        { tag: "old", stale_at: 1000, expired_at: 50_000 },
        { tag: "new", stale_at: 1000, expired_at: 11_000 },
      ],
      [
        { tag: "old", stale_at: 1000, expired_at: 50_000 },
        { tag: "new", stale_at: 1000, expired_at: 0 },
      ],
    ]);
    expect(calls[1]?.target).toBe("public.tags");
  });

  it("reports a failed tag write", async () => {
    const store = postgresCacheStore(
      scripted((call) =>
        call.target.endsWith("()")
          ? UNKNOWN_FUNCTION
          : op(call, "upsert")
            ? { error: { message: "full" } }
            : { data: [] },
      ),
    );

    expect((await store.markTags(["a"])).error?.message).toBe(
      "Postgres cache: tag write failed: full",
    );
  });
});
