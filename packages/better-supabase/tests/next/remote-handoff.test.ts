import { describe, expect, it } from "vitest";

import type { RemoteCacheKey } from "../../src/next/index.ts";

import {
  handOff,
  handoffKey,
  takeHandoff,
} from "../../src/next/remote-handoff.ts";
import { sessionSnapshot } from "../../src/testing/authorization.ts";

const USER = "11111111-1111-4111-8111-111111111111";

const key = (parts: Partial<RemoteCacheKey> = {}): RemoteCacheKey => ({
  userId: USER,
  sessionId: "s1",
  tenant: null,
  authzVersion: 3,
  shared: null,
  support: null,
  ...parts,
});

describe("remote handoffs", () => {
  it("keys by owner, a shared key or a support session", () => {
    expect(handoffKey(key())).toBe(`${USER}:s1:3`);
    expect(handoffKey(key({ sessionId: null, authzVersion: null }))).toBe(
      `${USER}:*:0`,
    );
    expect(handoffKey(key({ shared: "pricing" }))).toBe("key:pricing");
    expect(handoffKey(key({ support: "sup1" }))).toBe(
      `${USER}:s1:3:support:sup1`,
    );
    // The tenant is part of the cache key, not the owner: one token serves both.
    expect(handoffKey(key({ tenant: "acme" }))).toBe(handoffKey(key()));
  });

  it("keeps the snapshot until the last concurrent call releases it", () => {
    const snapshot = sessionSnapshot({ claims: { sub: USER } });
    const first = handOff(key(), snapshot);
    const second = handOff(key(), snapshot);

    expect(takeHandoff(key())).toBe(snapshot);
    first();
    first();
    expect(takeHandoff(key())).toBe(snapshot);
    second();
    expect(takeHandoff(key())).toBeUndefined();
  });

  it("never returns a snapshot under another key", () => {
    const release = handOff(key(), sessionSnapshot({ claims: { sub: USER } }));

    try {
      expect(takeHandoff(key({ sessionId: "s2" }))).toBeUndefined();
      expect(takeHandoff(key({ authzVersion: 4 }))).toBeUndefined();
    } finally {
      release();
    }
  });
});
