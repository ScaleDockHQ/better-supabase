import { describe, expect, it, vi } from "vitest";

import {
  authzVersionOf,
  isSessionSnapshot,
  issuedAtOf,
  sessionCacheKey,
  sessionMemo,
} from "../../src/auth/snapshot.ts";
import { requestAs, server } from "../fixtures/test-server.ts";

interface Value {
  readonly user: string;
  readonly exp: number | null;
}

const memoAt = (now: { ms: number }, max?: number) =>
  sessionMemo<Value>((value) => value.exp, {
    now: () => now.ms,
    ttlMs: 60_000,
    ...(max === undefined ? {} : { max }),
  });

describe("sessionMemo", () => {
  it("shares one in-flight verification between concurrent lookups", async () => {
    const memo = memoAt({ ms: 0 });
    const load = vi.fn(async () => ({ user: "a", exp: null }));

    const [first, second] = await Promise.all([
      memo.get("token", load),
      memo.get("token", load),
    ]);

    expect(first).toBe(second);
    expect(load).toHaveBeenCalledOnce();
    expect(memo.stats()).toEqual({ hits: 1, misses: 1, size: 1 });
  });

  it("keeps at most max entries and drops the least recently used", async () => {
    const memo = memoAt({ ms: 0 }, 2);
    const load = (user: string) => async () => ({ user, exp: null });

    await memo.get("a", load("a"));
    await memo.get("b", load("b"));
    await memo.get("a", load("a"));
    await memo.get("c", load("c"));

    expect(memo.stats().size).toBe(2);

    const reloaded = vi.fn(load("b"));
    await memo.get("b", reloaded);
    expect(reloaded).toHaveBeenCalledOnce();

    const kept = vi.fn(load("c"));
    await memo.get("c", kept);
    expect(kept).not.toHaveBeenCalled();
  });

  it("never keeps an entry past its token's exp or the ttl", async () => {
    const now = { ms: 1_000_000 };
    const memo = memoAt(now);
    const load = vi.fn(async () => ({ user: "a", exp: 1010 }));

    await memo.get("token", load);
    now.ms = 1_009_000;
    await memo.get("token", load);
    expect(load).toHaveBeenCalledOnce();

    now.ms = 1_010_000;
    await memo.get("token", load);
    expect(load).toHaveBeenCalledTimes(2);

    const lasting = vi.fn(async () => ({ user: "b", exp: null }));
    await memo.get("other", lasting);
    now.ms += 60_000;
    await memo.get("other", lasting);
    expect(lasting).toHaveBeenCalledTimes(2);
  });

  it("caches neither a null result nor a failure", async () => {
    const memo = memoAt({ ms: 0 });
    const empty = vi.fn(async () => null);

    expect(await memo.get("none", empty)).toBeNull();
    await memo.get("none", empty);
    expect(empty).toHaveBeenCalledTimes(2);

    const failing = vi.fn(async (): Promise<Value> => {
      throw new Error("jwks down");
    });

    await expect(memo.get("broken", failing)).rejects.toThrow("jwks down");
    await expect(memo.get("broken", failing)).rejects.toThrow("jwks down");
    expect(failing).toHaveBeenCalledTimes(2);
    expect(memo.stats().size).toBe(0);
  });

  it("answers from a seeded value and evicts a user's entries", async () => {
    const memo = memoAt({ ms: 0 });
    await memo.seed("seeded", { user: "a", exp: null });
    await memo.get("loaded", async () => ({ user: "b", exp: null }));

    const load = vi.fn(async () => ({ user: "a", exp: null }));
    await memo.get("seeded", load);
    expect(load).not.toHaveBeenCalled();

    memo.evict((value) => value.user === "a");
    await memo.get("seeded", load);
    expect(load).toHaveBeenCalledOnce();
    expect(memo.stats().size).toBe(2);
  });
});

describe("sessionCacheKey", () => {
  it("depends on the user, the session and the version, never the token", () => {
    const base = { userId: "u", sessionId: "s", authzVersion: 3 };

    expect(sessionCacheKey(base)).toBe(sessionCacheKey({ ...base }));
    expect(sessionCacheKey(base)).toBe("u:s:3");
    expect(sessionCacheKey({ ...base, authzVersion: 4 })).not.toBe(
      sessionCacheKey(base),
    );
    expect(
      sessionCacheKey({ userId: "u", sessionId: null, authzVersion: null }),
    ).toBe("u:-:0");
  });
});

describe("claims", () => {
  it("reads iat and authz_ver as numbers, else null", () => {
    expect(issuedAtOf({ iat: 10 })).toBe(10);
    expect(issuedAtOf({ iat: "10" })).toBeNull();
    expect(authzVersionOf({ authz_ver: 2 })).toBe(2);
    expect(authzVersionOf({})).toBeNull();
  });
});

describe("snapshots", () => {
  it("brands the snapshots it builds, and a copy is not one", async () => {
    const snapshot = await server.snapshot(await requestAs({ role: "m" }));

    expect(isSessionSnapshot(snapshot)).toBe(true);
    expect(isSessionSnapshot(structuredClone(snapshot))).toBe(false);
    expect(isSessionSnapshot({ ...snapshot })).toBe(false);
  });
});
