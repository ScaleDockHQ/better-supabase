import { describe, expect, it, vi } from "vitest";

import {
  clearJwksCache,
  jwksSource,
  purgeJwks,
  sharedJwks,
} from "../../src/core/jwks-cache.ts";

const KEY = {
  kty: "OKP",
  crv: "Ed25519",
  x: "11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo",
  kid: "k1",
};

const JWKS_URL = new URL("https://issuer.example.com/jwks.json");

describe("jwksSource", () => {
  it("loads a key set from a function once per cache window", async () => {
    let clock = 0;
    const loader = vi.fn(async () => ({ keys: [KEY] }));
    const source = jwksSource(loader, { now: () => clock });

    expect(await source(false)).toMatchObject({
      ok: true,
      data: { keys: [KEY] },
    });
    await source(false);
    expect(loader).toHaveBeenCalledOnce();

    clock = 301_000;
    await source(false);
    expect(loader).toHaveBeenCalledTimes(2);
  });

  it("fails with JWKS_FETCH_FAILED on an error status or an oversized body", async () => {
    const failing = jwksSource(JWKS_URL, {
      fetch: async () => new Response("", { status: 503 }),
    });

    const huge = jwksSource(JWKS_URL, {
      fetch: async () => new Response("x".repeat(256 * 1024 + 1)),
    });

    expect(await failing(false)).toMatchObject({
      ok: false,
      error: { code: "JWKS_FETCH_FAILED" },
    });
    expect(await huge(false)).toMatchObject({
      ok: false,
      error: {
        code: "JWKS_FETCH_FAILED",
        message: "The JWKS response is too large",
      },
    });
  });

  it("keeps the known keys when a refetch fails", async () => {
    let clock = 0;

    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValueOnce(Response.json({ keys: [KEY] }))
      .mockRejectedValueOnce(new Error("offline"));

    const source = jwksSource(JWKS_URL, { fetch, now: () => clock });

    await source(false);
    clock = 31_000;

    expect(await source(true)).toMatchObject({
      ok: true,
      data: { keys: [KEY] },
    });
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("reports a loader that throws", async () => {
    const source = jwksSource(async () => {
      throw new Error("boom");
    });

    expect(await source(false)).toMatchObject({
      ok: false,
      error: { message: "The JWKS could not be loaded: boom" },
    });
  });
});

describe("sharedJwks", () => {
  const keys = { keys: [KEY] };

  const counting = () =>
    vi.fn<typeof globalThis.fetch>(async () => Response.json(keys));

  it("fetches a Supabase key set again after 600 seconds at most, whatever cacheSeconds says", async () => {
    clearJwksCache();

    let clock = 0;
    const fetch = counting();

    const url = new URL(
      "https://abc.supabase.co/auth/v1/.well-known/jwks.json",
    );

    const options = { fetch, now: () => clock, cacheSeconds: 86_400 };

    await sharedJwks(url, false, options);
    clock = 599_000;
    await sharedJwks(url, false, options);
    expect(fetch).toHaveBeenCalledOnce();

    clock = 601_000;
    await sharedJwks(url, false, options);
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("keeps another issuer's cacheSeconds", async () => {
    clearJwksCache();

    let clock = 0;
    const fetch = counting();
    const options = { fetch, now: () => clock, cacheSeconds: 3600 };

    await sharedJwks(JWKS_URL, false, options);
    clock = 3_000_000;
    await sharedJwks(JWKS_URL, false, options);
    expect(fetch).toHaveBeenCalledOnce();
  });

  it("refetches once for an unknown kid and then waits out the cooldown", async () => {
    clearJwksCache();

    let clock = 0;
    const fetch = counting();
    const options = { fetch, now: () => clock };

    await sharedJwks(JWKS_URL, false, options);
    clock = 10_000;
    await sharedJwks(JWKS_URL, true, options);
    expect(fetch).toHaveBeenCalledOnce();

    clock = 31_000;
    await sharedJwks(JWKS_URL, true, options);
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("purges one key set so the next call fetches it again", async () => {
    clearJwksCache();

    const fetch = counting();
    const other = new URL("https://other.example.com/jwks.json");

    await sharedJwks(JWKS_URL, false, { fetch });
    await sharedJwks(other, false, { fetch });
    purgeJwks(JWKS_URL);
    await sharedJwks(JWKS_URL, false, { fetch });
    await sharedJwks(other, false, { fetch });
    expect(fetch).toHaveBeenCalledTimes(4);
  });

  it("serves a stale key set without waiting for the refresh", async () => {
    clearJwksCache();

    let clock = 0;
    let release: (() => void) | undefined;

    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });

    const fetch = vi.fn<typeof globalThis.fetch>(async () => {
      if (fetch.mock.calls.length > 1) {
        await gate;
      }

      return Response.json(keys);
    });

    const options = { fetch, now: () => clock, cacheSeconds: 10 };

    await sharedJwks(JWKS_URL, false, options);
    clock = 11_000;

    const started = Date.now();
    const result = await sharedJwks(JWKS_URL, false, options);

    expect(Date.now() - started).toBeLessThan(500);
    expect(result.ok && result.data).toEqual(keys);
    release?.();
  });

  it("waits once the stale window has ended, and fails when the fetch fails", async () => {
    clearJwksCache();

    let clock = 0;

    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValueOnce(Response.json({ keys: [KEY] }))
      .mockResolvedValueOnce(new Response("", { status: 503 }));

    const options = {
      fetch,
      now: () => clock,
      cacheSeconds: 10,
      maxStaleSeconds: 10,
    };

    await sharedJwks(JWKS_URL, false, options);
    clock = 21_000;

    expect(await sharedJwks(JWKS_URL, false, options)).toMatchObject({
      ok: false,
      error: { code: "JWKS_FETCH_FAILED" },
    });
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("stops serving a Supabase key set once cache and stale age reach 600 seconds", async () => {
    clearJwksCache();

    let clock = 0;

    const url = new URL(
      "https://abcdefghijklmnopqrst.supabase.co/auth/v1/.well-known/jwks.json",
    );

    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValueOnce(Response.json({ keys: [KEY] }))
      .mockResolvedValue(new Response("", { status: 503 }));

    const options = {
      fetch,
      now: () => clock,
      cacheSeconds: 300,
      maxStaleSeconds: 1000,
    };

    await sharedJwks(url, false, options);
    clock = 599_000;

    expect(await sharedJwks(url, false, options)).toMatchObject({
      ok: true,
      data: { keys: [KEY] },
    });

    clock = 601_000;

    expect(await sharedJwks(url, false, options)).toMatchObject({
      ok: false,
      error: { code: "JWKS_FETCH_FAILED" },
    });
  });

  it("purges every key set without an argument", async () => {
    clearJwksCache();

    const fetch = counting();

    await sharedJwks(JWKS_URL, false, { fetch });
    purgeJwks();
    await sharedJwks(JWKS_URL, false, { fetch });
    expect(fetch).toHaveBeenCalledTimes(2);
  });
});

describe("jwksSource with a loader function", () => {
  const keys = { keys: [KEY] };

  it("reports a rejection that is not an Error", async () => {
    const source = jwksSource(() => Promise.reject("plain text"));

    expect(await source(false)).toMatchObject({
      ok: false,
      error: { message: "The JWKS could not be loaded: plain text" },
    });
  });

  it("answers a refresh from the cache until the refetch window has passed", async () => {
    let clock = 0;
    const load = vi.fn(() => Promise.resolve(keys));
    const source = jwksSource(load, { now: () => clock });

    await source(false);
    clock = 10_000;
    await source(true);
    expect(load).toHaveBeenCalledOnce();

    clock = 31_000;
    await source(true);
    expect(load).toHaveBeenCalledTimes(2);
  });

  it("shares one load between concurrent callers", async () => {
    const load = vi.fn(() => Promise.resolve(keys));
    const source = jwksSource(load);

    await Promise.all([source(false), source(false)]);

    expect(load).toHaveBeenCalledOnce();
  });

  it("serves the known keys while the cache is stale and fails once the stale window ends", async () => {
    let clock = 0;

    const load = vi
      .fn<() => Promise<typeof keys>>()
      .mockResolvedValueOnce(keys)
      .mockRejectedValue(new Error("down"));

    const source = jwksSource(load, {
      now: () => clock,
      cacheSeconds: 10,
      maxStaleSeconds: 20,
    });

    await source(false);
    clock = 15_000;
    expect(await source(false)).toMatchObject({ ok: true });

    clock = 35_000;
    expect(await source(false)).toMatchObject({
      ok: false,
      error: { code: "JWKS_FETCH_FAILED" },
    });
  });
});

describe("sharedJwks failures", () => {
  it("reports a fetch that rejects with something other than an Error", async () => {
    clearJwksCache();

    const fetch = vi.fn<typeof globalThis.fetch>(() => Promise.reject("nope"));

    expect(await sharedJwks(JWKS_URL, false, { fetch })).toMatchObject({
      ok: false,
      error: { message: "The JWKS could not be loaded: nope" },
    });
  });

  it("purges a key set named by its address as a string", async () => {
    clearJwksCache();

    const fetch = vi.fn<typeof globalThis.fetch>(() =>
      Promise.resolve(Response.json({ keys: [KEY] })),
    );

    await sharedJwks(JWKS_URL, false, { fetch });
    purgeJwks(JWKS_URL.href);
    await sharedJwks(JWKS_URL, false, { fetch });

    expect(fetch).toHaveBeenCalledTimes(2);
  });
});
