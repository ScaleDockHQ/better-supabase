import { describe, expect, it, vi } from "vitest";

import { loadJsonPath } from "../../src/overlay/index.ts";

describe("loadJsonPath", () => {
  it("loads jsonpath-rfc9535 once and returns normalized paths", async () => {
    const engine = await loadJsonPath();
    expect(await loadJsonPath()).toBe(engine);
    expect(engine.paths({ a: [1, { "b/c": 2 }] }, "$..*")).toEqual([
      "$['a']",
      "$['a'][0]",
      "$['a'][1]",
      "$['a'][1]['b/c']",
    ]);
  });

  it("rejects with an install message when the engine is missing", async () => {
    await expect(loadJsonPath(async () => undefined)).rejects.toThrow(
      "pnpm add jsonpath-rfc9535",
    );
    await expect(loadJsonPath(async () => ({ paths: 1 }))).rejects.toThrow(
      TypeError,
    );
  });

  it("retries the import after a failed load", async () => {
    vi.resetModules();
    vi.doMock("jsonpath-rfc9535", () => {
      throw new Error("Cannot find package 'jsonpath-rfc9535'");
    });
    const fresh = await import("../../src/overlay/load.ts");
    await expect(fresh.loadJsonPath()).rejects.toThrow(
      "pnpm add jsonpath-rfc9535",
    );
    vi.doUnmock("jsonpath-rfc9535");
    const engine = await fresh.loadJsonPath();
    expect(engine.paths({ a: 1 }, "$.a")).toEqual(["$['a']"]);
  });

  it("accepts a module from a custom importer", async () => {
    const engine = { paths: () => ["$"] };
    expect(await loadJsonPath(async () => engine)).toBe(engine);
  });
});
