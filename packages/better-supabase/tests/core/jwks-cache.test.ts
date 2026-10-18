import { describe, expect, it, vi } from "vitest";

import { jwksSource } from "../../src/core/jwks-cache.ts";

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
