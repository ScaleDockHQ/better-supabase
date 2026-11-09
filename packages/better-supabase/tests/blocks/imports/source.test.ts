import { describe, expect, it } from "vitest";

import type { ImportSourceClient } from "../../../src/blocks/imports/source.ts";

import {
  defineImportSource,
  runImportSource,
} from "../../../src/blocks/imports/source.ts";

const source = defineImportSource({
  id: "books",
  dependencies: [
    { entity: "party" },
    { entity: "product" },
    { entity: "invoice", dependsOn: ["party", "product"] },
  ],
  async read() {
    return {
      party: [{ key: "p", data: { name: "Ada" } }],
      product: [{ key: "g", data: { name: "Guide" } }],
      invoice: [{ key: "i", data: { total: 10 } }],
    };
  },
  map(staged) {
    return staged;
  },
  describe(staged) {
    return {
      entities: Object.keys(staged),
      counts: Object.fromEntries(
        Object.entries(staged).map(([entity, items]) => [entity, items.length]),
      ),
      warnings: [],
    };
  },
});

describe("runImportSource", () => {
  it("describes three entities and writes nothing on a dry run", async () => {
    const calls: string[] = [];

    const client: ImportSourceClient = {
      async start() {
        calls.push("start");

        return { id: "run" };
      },
      async upsert(_run, entity) {
        calls.push(entity);
      },
      async finish() {
        calls.push("finish");
      },
    };

    const dry = await runImportSource(source, null, { client, dryRun: true });

    expect(dry.dryRun).toBe(true);
    expect(dry.description.counts).toEqual({
      party: 1,
      product: 1,
      invoice: 1,
    });
    expect(dry.waves).toEqual([["party", "product"], ["invoice"]]);
    expect(calls).toEqual([]);
  });

  it("writes each wave and finishes the run", async () => {
    const calls: string[] = [];

    const client: ImportSourceClient = {
      async start() {
        calls.push("start");

        return { id: "run" };
      },
      async upsert(_run, entity) {
        calls.push(entity);
      },
      async finish() {
        calls.push("finish");
      },
    };

    const real = await runImportSource(source, null, { client });

    expect(real.runId).toBe("run");
    expect(calls).toEqual(["start", "party", "product", "invoice", "finish"]);
  });
});
