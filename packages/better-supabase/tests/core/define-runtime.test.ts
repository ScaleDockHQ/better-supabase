import { describe, expect, it, vi } from "vitest";

import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

/** A definition connected by a fresh copy of the runtime that has no extras. */
async function leanDb() {
  vi.resetModules();

  const { provideLeanConnectionRuntime } =
    await import("../../src/core/define-runtime.ts");

  provideLeanConnectionRuntime();
  const { createSupabase } = await import("../../src/core/define.ts");
  const { client } = capturingClient();

  return createSupabase(schema).connect(client) as unknown as Record<
    string,
    unknown
  >;
}

describe("the lean connection runtime", () => {
  it("builds repositories and the core helpers", async () => {
    const db = await leanDb();

    expect(typeof db["customers"]).toBe("object");
    expect(typeof db["$rpc"]).toBe("function");
    expect(typeof db["$run"]).toBe("function");
    expect(typeof db["$table"]).toBe("function");
    expect(typeof db["$with"]).toBe("function");
  });

  it("leaves out the helpers the browser bundle drops", async () => {
    const db = await leanDb();

    for (const name of [
      "$many",
      "$search",
      "$stats",
      "$decode",
      "$decodeReadSet",
    ]) {
      expect(db[name]).toBeUndefined();
    }
  });

  it("rejects a filter tree in where until enableFilterTrees runs", async () => {
    const db = await leanDb();

    const customers = db["customers"] as {
      list: (args: unknown) => { orThrow: () => Promise<unknown> };
    };

    await expect(
      customers
        .list({
          where: { type: "group", combinator: "and", id: "root", rules: [] },
        })
        .orThrow(),
    ).rejects.toThrow(/enableFilterTrees/);
  });
});

describe("the full connection runtime", () => {
  it("adds the helpers", async () => {
    vi.resetModules();

    const { provideConnectionRuntime } =
      await import("../../src/core/define-runtime-full.ts");

    provideConnectionRuntime();
    const { createSupabase } = await import("../../src/core/define.ts");
    const { client } = capturingClient();

    const db = createSupabase(schema).connect(client) as unknown as Record<
      string,
      unknown
    >;

    for (const name of [
      "$many",
      "$search",
      "$stats",
      "$decode",
      "$decodeReadSet",
    ]) {
      expect(typeof db[name]).toBe("function");
    }
  });
});
