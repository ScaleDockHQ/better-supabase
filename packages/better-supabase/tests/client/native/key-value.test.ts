import { describe, expect, it } from "vitest";

import { keyValue } from "../../../src/client/native/key-value.ts";

describe("keyValue", () => {
  it("wraps AsyncStorage", async () => {
    const map = new Map<string, string>();
    const store = keyValue({
      getItem: (key) => Promise.resolve(map.get(key) ?? null),
      setItem: (key, value) => Promise.resolve(void map.set(key, value)),
      removeItem: (key) => Promise.resolve(void map.delete(key)),
    });
    await store.set("a", "1");
    expect(await store.get("a")).toBe("1");
    await store.remove("a");
    expect(await store.get("a")).toBeNull();
  });

  it("wraps MMKV v3 (delete) and v4 (remove)", async () => {
    for (const method of ["delete", "remove"] as const) {
      const map = new Map<string, string>();
      const removeKey = (key: string) => {
        map.delete(key);
      };
      const store = keyValue({
        getString: (key) => map.get(key),
        set: (key, value) => {
          map.set(key, value);
        },
        [method]: removeKey,
      });
      await store.set("a", "1");
      expect(await store.get("a")).toBe("1");
      await store.remove("a");
      expect(await store.get("a")).toBeNull();
    }
  });
});
