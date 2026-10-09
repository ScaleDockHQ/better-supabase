import { describe, expect, it } from "vitest";

import type { SecureStoreLike } from "../../../src/client/native/storage.ts";

import { largeSecureStorage } from "../../../src/client/native/large-storage.ts";

function fakeSecureStore() {
  const map = new Map<string, string>();
  const options: unknown[] = [];
  const store: SecureStoreLike = {
    getItemAsync: (key, extra) => {
      options.push(extra);
      return Promise.resolve(map.get(key) ?? null);
    },
    setItemAsync: (key, value, extra) => {
      options.push(extra);
      map.set(key, value);
      return Promise.resolve();
    },
    deleteItemAsync: (key, extra) => {
      options.push(extra);
      map.delete(key);
      return Promise.resolve();
    },
  };
  return { store, map, options };
}

function fakeStorage() {
  const map = new Map<string, string>();
  return {
    map,
    storage: {
      getString: (key: string) => map.get(key),
      set: (key: string, value: string) => {
        map.set(key, value);
      },
      remove: (key: string) => map.delete(key),
    },
  };
}

describe("largeSecureStorage", () => {
  const session = JSON.stringify({
    access_token: "a".repeat(4000),
    user: { id: "user-marker-0f3c" },
  });

  it("keeps only the key in the keychain and the sealed session elsewhere", async () => {
    const secure = fakeSecureStore();
    const plain = fakeStorage();
    const auth = largeSecureStorage({
      secureStore: secure.store,
      storage: plain.storage,
    });
    await auth.setItem("sb-auth-token", session);
    expect(await auth.getItem("sb-auth-token")).toBe(session);
    const secret = secure.map.get("sb-auth-token.aes");
    expect(secret).toBeDefined();
    expect(secret?.length).toBeLessThan(64);
    const sealed = plain.map.get("sb-auth-token") ?? "";
    expect(sealed.startsWith("v1.")).toBe(true);
    expect(sealed).not.toContain("user-marker-0f3c");
    await auth.removeItem("sb-auth-token");
    expect(secure.map.size).toBe(0);
    expect(plain.map.size).toBe(0);
    expect(await auth.getItem("sb-auth-token")).toBeNull();
  });

  it("reads as signed out when the key and the data don't match", async () => {
    const secure = fakeSecureStore();
    const plain = fakeStorage();
    const auth = largeSecureStorage({
      secureStore: secure.store,
      storage: plain.storage,
    });
    await auth.setItem("k", session);
    const stale = plain.map.get("k") ?? "";
    await auth.setItem("k", session);
    plain.map.set("k", stale);
    expect(await auth.getItem("k")).toBeNull();
    plain.map.set("k", "v0.x.y");
    expect(await auth.getItem("k")).toBeNull();
  });

  it("passes store options and hashes unsafe keys", async () => {
    const secure = fakeSecureStore();
    const plain = fakeStorage();
    const auth = largeSecureStorage({
      secureStore: secure.store,
      storage: plain.storage,
      storeOptions: { keychainService: "app" },
    });
    await auth.setItem("a:b", "value");
    expect(await auth.getItem("a:b")).toBe("value");
    expect([...secure.map.keys()][0]).toMatch(/^a_b-[\w]+\.aes$/u);
    expect(secure.options.every((extra) => extra !== undefined)).toBe(true);
  });

  it("explains how to add WebCrypto when it is missing", async () => {
    const secure = fakeSecureStore();
    const plain = fakeStorage();
    const auth = largeSecureStorage({
      secureStore: secure.store,
      storage: plain.storage,
    });
    const original = globalThis.crypto;
    Object.defineProperty(globalThis, "crypto", {
      value: undefined,
      configurable: true,
    });
    try {
      await expect(auth.setItem("k", "v")).rejects.toThrow(
        /react-native-quick-crypto/u,
      );
    } finally {
      Object.defineProperty(globalThis, "crypto", {
        value: original,
        configurable: true,
      });
    }
  });
});
