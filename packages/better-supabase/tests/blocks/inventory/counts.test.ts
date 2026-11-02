import { describe, expect, it } from "vitest";

import { createInventory } from "../../../src/blocks/inventory/index.ts";

describe("inventory counts", () => {
  it("posts a count and reads the variance", async () => {
    const inventory = createInventory({
      transport: {
        call: (_schema: string, fn: string) =>
          Promise.resolve(
            fn === "post_stock_count"
              ? { posted: true, movements: 2, variance: "-3" }
              : null,
          ),
      },
    });

    expect(await inventory.postStockCount("c1").orThrow()).toEqual({
      posted: true,
      movements: 2,
      variance: "-3",
    });
  });
});

describe("inventory counts calls", () => {
  const record: { fn: string; args: unknown }[] = [];

  const inventory = createInventory({
    transport: {
      call(_schema: string, fn: string, args: unknown) {
        record.push({ fn, args });

        const replies: Record<string, unknown> = {
          open_stock_count: { id: "c1", lines: 4 },
          record_count_line: { id: "l1", expected: "5", counted: "3" },
          post_stock_count: { posted: false },
          cancel_stock_count: true,
        };

        return Promise.resolve(replies[fn]);
      },
    },
  });

  it("opens a count with and without options", async () => {
    expect(
      await inventory
        .openStockCount({
          organizationId: "org",
          locationId: "loc",
          input: { note: "year end", variantIds: ["v1"] },
        })
        .orThrow(),
    ).toEqual({ id: "c1", lines: 4 });
    expect(
      await inventory
        .openStockCount({ organizationId: "org", locationId: "loc" })
        .orThrow(),
    ).toEqual({ id: "c1", lines: 4 });
    expect(record[0]?.args).toEqual({
      tenant: "org",
      location: "loc",
      attrs: { note: "year end", variantIds: ["v1"] },
    });
  });

  it("records a line, defaulting the variance, and reads a repeat post", async () => {
    expect(
      await inventory
        .recordCountLine({
          countId: "c1",
          input: { variantId: "v1", counted: 3, binId: "b1" },
        })
        .orThrow(),
    ).toEqual({ id: "l1", expected: "5", counted: "3", variance: "0" });
    expect(await inventory.postStockCount("c1").orThrow()).toEqual({
      posted: false,
      movements: 0,
      variance: "0",
    });
    expect(await inventory.cancelStockCount("c1").orThrow()).toBe(true);
  });
});
