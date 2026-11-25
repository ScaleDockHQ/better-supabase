import { describe, expect, it, vi } from "vitest";

import { getJsonPath } from "../../src/spec/index.ts";

describe("getJsonPath", () => {
  it("loads jsonpath-rfc9535 once and returns normalized paths", async () => {
    const engine = await getJsonPath();
    expect(await getJsonPath()).toBe(engine);
    expect(engine.paths({ a: [1, { "b/c": 2 }] }, "$..*")).toEqual([
      "$['a']",
      "$['a'][0]",
      "$['a'][1]",
      "$['a'][1]['b/c']",
    ]);
  });

  it("rejects with an install message when the engine is missing", async () => {
    await expect(getJsonPath(async () => undefined)).rejects.toThrow(
      "pnpm add jsonpath-rfc9535",
    );
    await expect(getJsonPath(async () => ({ paths: 1 }))).rejects.toThrow(
      TypeError,
    );
  });

  it("retries the import after a failed load", async () => {
    vi.resetModules();
    vi.doMock(import("jsonpath-rfc9535"), () => {
      throw new Error("Cannot find package 'jsonpath-rfc9535'");
    });
    const fresh = await import("../../src/overlay/load.ts");
    await expect(fresh.getJsonPath()).rejects.toThrow(
      "pnpm add jsonpath-rfc9535",
    );
    vi.doUnmock("jsonpath-rfc9535");
    const engine = await fresh.getJsonPath();
    expect(engine.paths({ a: 1 }, "$.a")).toEqual(["$['a']"]);
  });

  it("accepts a module from a custom importer", async () => {
    const engine = { paths: () => ["$"] };
    expect(await getJsonPath(async () => engine)).toBe(engine);
  });
});
