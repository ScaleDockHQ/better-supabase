import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import {
  createNativeClient,
  secureStorage,
} from "../../src/client/native/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

function memoryStore() {
  const values = new Map<string, string>();
  return {
    values,
    getItemAsync: (key: string) => Promise.resolve(values.get(key) ?? null),
    setItemAsync: (key: string, value: string) => {
      if (!/^[\w.-]+$/.test(key)) throw new Error(`invalid key ${key}`);
      values.set(key, value);
      return Promise.resolve();
    },
    deleteItemAsync: (key: string) => {
      values.delete(key);
      return Promise.resolve();
    },
  };
}

describe("better-supabase/client/native", () => {
  it("binds repositories to a client the app created", async () => {
    const { client } = capturingClient(() => ({ body: [] }));
    const bs = createNativeClient(defineSupabase(schema), client);
    expect(bs.supabase).toBe(client);
    expect(bs.auth.current().status).toBe("loading");
    expect(await bs.db.tags.findMany({ select: ["id"] })).toMatchObject({
      ok: true,
    });
  });

  it("never loads @supabase/ssr", async () => {
    for (const file of ["native/index.ts", "native/storage.ts", "bind.ts"]) {
      const source = await readFile(
        new URL(`../../src/client/${file}`, import.meta.url),
        "utf8",
      );
      expect(source).not.toContain("@supabase/ssr");
    }
  });
});

describe("secureStorage", () => {
  it("splits values into chunks and reads them back", async () => {
    const store = memoryStore();
    const storage = secureStorage(store, { chunkSize: 4 });
    await storage.setItem("sb-ref-auth-token", "abcdefghij");
    expect(store.values.get("sb-ref-auth-token.chunks")).toBe("3");
    expect(await storage.getItem("sb-ref-auth-token")).toBe("abcdefghij");

    await storage.setItem("sb-ref-auth-token", "xy");
    expect(store.values.get("sb-ref-auth-token.chunks")).toBe("1b");
    expect(store.values.has("sb-ref-auth-token.0")).toBe(false);
    expect(store.values.has("sb-ref-auth-token.2")).toBe(false);
    expect(await storage.getItem("sb-ref-auth-token")).toBe("xy");

    await storage.setItem("a b:c", "");
    expect(await storage.getItem("a b:c")).toBe("");

    await storage.removeItem("sb-ref-auth-token");
    expect(await storage.getItem("sb-ref-auth-token")).toBeNull();
    expect(
      [...store.values.keys()].every((key) => key.startsWith("a_b_c")),
    ).toBe(true);
  });

  it("keeps keys apart that map to the same safe name", async () => {
    const store = memoryStore();
    const storage = secureStorage(store);
    await storage.setItem("a:b", "colon");
    await storage.setItem("a/b", "slash");
    await storage.setItem("a_b", "plain");
    expect(await storage.getItem("a:b")).toBe("colon");
    expect(await storage.getItem("a/b")).toBe("slash");
    expect(await storage.getItem("a_b")).toBe("plain");
    expect(store.values.get("a_b.chunks")).toBe("1");
  });

  it("passes the store options to every call", async () => {
    const store = memoryStore();
    const calls: unknown[] = [];
    const spy = {
      getItemAsync: (key: string, options?: unknown) => {
        calls.push(options);
        return store.getItemAsync(key);
      },
      setItemAsync: (key: string, value: string, options?: unknown) => {
        calls.push(options);
        return store.setItemAsync(key, value);
      },
      deleteItemAsync: (key: string, options?: unknown) => {
        calls.push(options);
        return store.deleteItemAsync(key);
      },
    };
    const storeOptions = { keychainAccessible: 0 };
    const storage = secureStorage(spy, { storeOptions });
    await storage.setItem("k", "v");
    await storage.getItem("k");
    await storage.removeItem("k");
    expect(calls.length).toBeGreaterThan(4);
    expect(calls.every((options) => options === storeOptions)).toBe(true);
  });

  it("reads a missing chunk as no session", async () => {
    const store = memoryStore();
    const storage = secureStorage(store);
    await storage.setItem("k", "x".repeat(4000));
    store.values.delete("k.1");
    expect(await storage.getItem("k")).toBeNull();
    expect(() => secureStorage(store, { chunkSize: 0 })).toThrow(/chunkSize/);
  });

  it("never reads a value half written by a concurrent setItem", async () => {
    const store = memoryStore();
    const storage = secureStorage(store, { chunkSize: 4 });
    await storage.setItem("k", "abcdefghij");
    const [, read] = await Promise.all([
      storage.setItem("k", "12345678"),
      storage.getItem("k"),
    ]);
    expect(["abcdefghij", "12345678"]).toContain(read);
    expect(await storage.getItem("k")).toBe("12345678");
  });

  it("keeps the previous value when a write fails part way", async () => {
    const store = memoryStore();
    const storage = secureStorage(store, { chunkSize: 4 });
    await storage.setItem("k", "abcdefghij");
    const set = store.setItemAsync;
    let writes = 0;
    store.setItemAsync = (key, value) => {
      writes += 1;
      if (writes === 2) return Promise.reject(new Error("keychain locked"));
      return set(key, value);
    };
    await expect(storage.setItem("k", "12345678")).rejects.toThrow(/keychain/);
    expect(await storage.getItem("k")).toBe("abcdefghij");

    store.setItemAsync = set;
    await storage.setItem("k", "12345678");
    expect(await storage.getItem("k")).toBe("12345678");
    await storage.removeItem("k");
    expect(await storage.getItem("k")).toBeNull();
    expect(store.values.size).toBe(0);
  });

  it("reads values stored before the second chunk slot existed", async () => {
    const store = memoryStore();
    store.values.set("k.chunks", "2");
    store.values.set("k.0", "ab");
    store.values.set("k.1", "cd");
    const storage = secureStorage(store);
    expect(await storage.getItem("k")).toBe("abcd");
    await storage.setItem("k", "ef");
    expect(await storage.getItem("k")).toBe("ef");
    expect(store.values.has("k.1")).toBe(false);
  });
});
