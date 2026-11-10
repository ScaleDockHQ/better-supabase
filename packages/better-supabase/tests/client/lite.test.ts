import { afterEach, describe, expect, it } from "vitest";

import { createLiteBrowserClient } from "../../src/client/lite/index.ts";

const URL = "https://abcdefghijklmnopqrst.supabase.co";

function memory(): {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
  readonly keys: () => string[];
} {
  const store = new Map<string, string>();

  return {
    getItem: (key) => store.get(key) ?? null,
    setItem: (key, value) => void store.set(key, value),
    removeItem: (key) => void store.delete(key),
    keys: () => [...store.keys()],
  };
}

describe("createLiteBrowserClient", () => {
  const clients: ReturnType<typeof createLiteBrowserClient>[] = [];

  afterEach(async () => {
    for (const client of clients.splice(0)) {
      await client.auth.stopAutoRefresh();
      await client.realtime.disconnect();
    }
  });

  it("has auth and realtime and no data clients", () => {
    const client = createLiteBrowserClient(URL, "sb_publishable_test", {
      storage: memory(),
    });

    clients.push(client);
    expect(client.auth).toBeDefined();
    expect(client.realtime).toBeDefined();
    expect(Object.keys(client).toSorted()).toEqual([
      "auth",
      "channel",
      "realtime",
    ]);
  });

  it("opens a realtime channel on the topic", () => {
    const client = createLiteBrowserClient(URL, "sb_publishable_test", {
      storage: memory(),
    });

    clients.push(client);
    expect(client.channel("room:1").topic).toBe("realtime:room:1");
  });

  it("stores the session under the project's key unless one is given", async () => {
    const storage = memory();

    const client = createLiteBrowserClient(URL, "sb_publishable_test", {
      storage,
    });

    clients.push(client);
    await client.auth.getSession();

    const named = memory();

    const other = createLiteBrowserClient(URL, "sb_publishable_test", {
      storage: named,
      storageKey: "my-key",
    });

    clients.push(other);
    await other.auth.setSession({ access_token: "a.b.c", refresh_token: "r" });
    expect(named.keys().every((key) => key.startsWith("my-key"))).toBe(true);
  });

  it("works without a storage option", () => {
    const client = createLiteBrowserClient(URL, "sb_publishable_test");

    clients.push(client);
    expect(client.auth).toBeDefined();
  });
});
