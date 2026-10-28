import { describe, expect, it, vi } from "vitest";

import { createServer } from "../../src/server/server.ts";
import { countResolutions } from "../fixtures/instant-sessions.ts";
import {
  betterSupabase,
  env,
  requestAs,
  signer,
  USER,
} from "../fixtures/test-server.ts";

const fresh = () =>
  createServer(betterSupabase, {
    env,
    auth: { jwks: signer.jwks },
    prefetchJwks: false,
  });

describe("server sessions", () => {
  it("verifies a token once across snapshot calls", async () => {
    const server = fresh();
    const request = await requestAs({ role: "member" });
    const verify = vi.spyOn(crypto.subtle, "verify");

    const [first, second, again] = await Promise.all([
      server.snapshot(request),
      server.snapshot(request.clone()),
      server.snapshot(request),
    ]);

    expect(first).toBe(second);
    expect(again).toBe(first);
    expect(first).toMatchObject({ userId: USER });
    expect(verify).toHaveBeenCalledOnce();
    expect(server.sessions.stats()).toMatchObject({ hits: 1, misses: 1 });
    verify.mockRestore();
  });

  it("builds a context from a snapshot without verifying again", async () => {
    const server = fresh();
    const snapshot = await server.snapshot(await requestAs({ role: "member" }));
    const resolutions = countResolutions(betterSupabase);

    const ctx = await server.contextFromSession(snapshot);

    expect(ctx.auth).toMatchObject({ kind: "user", user: { id: USER } });
    expect(resolutions.count()).toBe(0);
    resolutions.stop();
    expect((await server.contextFromSession(null)).auth).toEqual({
      kind: "none",
      reason: "none",
    });
  });

  it("refuses a forged or deserialized snapshot", async () => {
    const server = fresh();
    const snapshot = await server.snapshot(await requestAs({ role: "member" }));

    for (const forged of [structuredClone(snapshot), { ...snapshot }]) {
      // SAFETY: the copies have the snapshot's shape but not its brand.
      const ctx = await server.contextFromSession(forged as typeof snapshot);
      expect(ctx.auth).toMatchObject({ kind: "invalid", reason: "token" });
    }
  });

  it("treats an expired snapshot as signed out", async () => {
    const server = fresh();
    const token = await signer.sign({ sub: USER, expiresIn: 2 });

    const snapshot = await server.snapshot(
      new Request("https://app.test/", {
        headers: { authorization: `Bearer ${token}` },
      }),
    );

    vi.useFakeTimers({ now: Date.now() + 5000 });

    try {
      expect((await server.contextFromSession(snapshot)).auth).toEqual({
        kind: "none",
        reason: "expired",
      });
    } finally {
      vi.useRealTimers();
    }
  });

  it("evicts a user's sessions, so the next lookup verifies again", async () => {
    const server = fresh();
    const request = await requestAs({ role: "member" });

    await server.snapshot(request);
    server.sessions.evict(USER);
    await server.snapshot(request);

    expect(server.sessions.stats()).toMatchObject({ hits: 0, misses: 2 });

    server.sessions.clear();
    await server.snapshot(request);

    expect(server.sessions.stats()).toMatchObject({ hits: 0, misses: 1 });
  });
});
