import { describe, expect, it } from "vitest";

import type { VaultCredentials } from "../../../src/credentials/vault.ts";

import {
  dedupeMcpEvents,
  postgresMcpEventStore,
} from "../../../src/ai-sdk/mcp/events.ts";
import { AsyncResult } from "../../../src/core/result.ts";

function fakeVault() {
  const secrets = new Map<string, string>();

  const vault = {
    apiVersion: 1,
    name: "vault",
    capabilities: () => ({}),
    getToken: (ref: { secret: string }) => {
      const value = secrets.get(ref.secret);

      return value === undefined
        ? AsyncResult.err({ kind: "not_found", message: "none", status: 404 })
        : AsyncResult.ok({ token: value, headers: {} });
    },
    set: (ref: { secret: string }, value: string) => {
      secrets.set(ref.secret, value);

      return AsyncResult.ok(undefined);
    },
    revoke: (ref: { secret: string }) =>
      AsyncResult.ok(secrets.delete(ref.secret)),
  };

  // SAFETY: the store calls getToken, set and revoke only.
  return { vault: vault as unknown as VaultCredentials, secrets };
}

const subscription = {
  key: "k1",
  id: "sub_1",
  name: "issues",
  arguments: {},
  definition: { name: "issues" },
  delivery: {
    mode: "webhook" as const,
    url: "https://x.test/hook",
    secret: "s3",
  },
  cursor: null,
  truncated: false,
  status: "pending" as const,
};

describe("postgresMcpEventStore", () => {
  it("stores, finds by key and id, merges updates and deletes", async () => {
    const { vault, secrets } = fakeVault();
    const store = postgresMcpEventStore({ vault, scope: "srv:u1" });

    // SAFETY: a minimal definition is enough for the store.
    await store.set(subscription as never);
    expect((await store.get("k1"))?.delivery.secret).toBe("s3");
    expect((await store.getById("sub_1"))?.key).toBe("k1");
    expect(await store.get("nope")).toBeUndefined();

    await store.update("k1", { status: "active", cursor: "c2" });
    expect(await store.get("k1")).toMatchObject({
      status: "active",
      cursor: "c2",
      name: "issues",
    });

    await store.delete("k1");
    expect(secrets.size).toBe(0);
    expect(await store.getById("sub_1")).toBeUndefined();
  });
});

describe("dedupeMcpEvents", () => {
  it("runs a delivery once", async () => {
    const claimed = new Set<string>();
    const seen: string[] = [];

    const handlers = dedupeMcpEvents(
      {
        onEvent: async ({ event }) => {
          seen.push(event.eventId);
        },
        onGap: async ({ messageId }) => {
          seen.push(`gap:${messageId}`);
        },
      },
      {
        claim: async (key) => {
          if (claimed.has(key)) {
            return false;
          }

          claimed.add(key);

          return true;
        },
      },
    );

    const info = {
      id: "sub_1",
      name: "issues",
      arguments: {},
      delivery: { mode: "webhook" as const, url: "u" },
      refreshBefore: null,
    };

    const event = { eventId: "e1", name: "issues", timestamp: "t", data: {} };

    await handlers.onEvent({ subscription: info, event });
    await handlers.onEvent({ subscription: info, event });
    // SAFETY: only messageId is read.
    await handlers.onGap?.({
      subscription: info,
      messageId: "m1",
      gap: {},
    } as never);
    await handlers.onGap?.({
      subscription: info,
      messageId: "m1",
      gap: {},
    } as never);

    expect(seen).toEqual(["e1", "gap:m1"]);
    expect(handlers.onTerminated).toBeUndefined();
  });

  it("dedupes terminations", async () => {
    const claimed = new Set<string>();
    let ended = 0;

    const handlers = dedupeMcpEvents(
      {
        onEvent: async () => undefined,
        onTerminated: async () => {
          ended += 1;
        },
      },
      {
        claim: async (key) => {
          const fresh = !claimed.has(key);
          claimed.add(key);

          return fresh;
        },
      },
    );

    // SAFETY: only subscription.id and messageId are read.
    const args = { subscription: { id: "s" }, messageId: "m" } as never;
    await handlers.onTerminated?.(args);
    await handlers.onTerminated?.(args);

    expect(ended).toBe(1);
  });
});

describe("postgresMcpEventStore, remaining paths", () => {
  it("ignores unparsable values, missing updates and an id change", async () => {
    const { vault, secrets } = fakeVault();
    const store = postgresMcpEventStore({ vault, scope: "srv:u2" });

    await store.update("none", { status: "active" });
    expect(secrets.size).toBe(0);

    // SAFETY: a minimal subscription is enough for the store.
    await store.set({ ...subscription, id: undefined } as never);
    await store.update("k1", { id: "sub_2" });
    expect((await store.getById("sub_2"))?.key).toBe("k1");

    for (const [name] of secrets) {
      secrets.set(name, name.includes("key:") ? "not json" : "k1");
    }

    expect(await store.get("k1")).toBeUndefined();

    await store.delete("k1");
  });
});
