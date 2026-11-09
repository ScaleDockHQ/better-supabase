import { describe, expect, it } from "vitest";

import { createImports } from "../../../src/blocks/imports/imports.ts";

const COUNTS = {
  inserted: 0,
  updated: 0,
  unchanged: 0,
  conflicted: 0,
  errors: [],
  dryRun: false,
};

/** A transport whose `import_upsert_batch` runs `batch(size)` for each call. */
function transport(batch: (size: number) => unknown) {
  const sizes: number[] = [];

  return {
    sizes,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      if (fn === "start_import_run") {
        return Promise.resolve({ id: "run-1" });
      }

      if (fn === "mark_import_running") {
        return Promise.resolve(true);
      }

      if (fn === "finish_import_run") {
        return Promise.resolve({});
      }

      if (fn === "cancel_import_run") {
        return Promise.resolve(true);
      }

      const items = args["items"] as unknown[];
      sizes.push(items.length);

      return Promise.resolve(batch(items.length));
    },
  };
}

const items = (count: number) => ({
  entity: "customer",
  items: Array.from({ length: count }, (_, at) => ({
    key: `c${String(at)}`,
    data: {},
  })),
});

describe("imports.run batches", () => {
  it("splits a batch that hits the statement timeout and sends each half again", async () => {
    const t = transport((size) => {
      if (size > 4) {
        throw Object.assign(new Error("canceling statement"), {
          code: "57014",
        });
      }

      return { ...COUNTS, inserted: size };
    });

    const result = await createImports({ transport: t })
      .run({
        organizationId: "org-1",
        source: "erp",
        entities: [items(16)],
        batchSize: 16,
      })
      .orThrow();

    expect(t.sizes).toEqual([16, 8, 4, 4, 8, 4, 4]);
    expect(result.suggestedBatchSize).toBe(4);
  });

  it("fails the run when a single item still times out", async () => {
    const t = transport(() => {
      throw Object.assign(new Error("canceling statement"), { code: "57014" });
    });

    const result = await createImports({ transport: t }).run({
      organizationId: "org-1",
      source: "erp",
      entities: [items(2)],
      batchSize: 2,
    });

    expect(result.ok).toBe(false);
    expect(t.sizes).toEqual([2, 1]);
  });

  it("grows the batch to maxBatchSize while batches stay fast and never shrinks without a slow batch", async () => {
    const t = transport((size) => ({ ...COUNTS, inserted: size }));

    const result = await createImports({ transport: t })
      .run({
        organizationId: "org-1",
        source: "erp",
        entities: [items(70)],
        batchSize: 10,
        maxBatchSize: 40,
      })
      .orThrow();

    expect(t.sizes).toEqual([10, 20, 40]);
    expect(result.suggestedBatchSize).toBe(40);
  });

  it("keeps the batch size without a maxBatchSize", async () => {
    const t = transport((size) => ({ ...COUNTS, inserted: size }));

    await createImports({ transport: t })
      .run({
        organizationId: "org-1",
        source: "erp",
        entities: [items(25)],
        batchSize: 10,
      })
      .orThrow();

    expect(t.sizes).toEqual([10, 10, 5]);
  });
});
