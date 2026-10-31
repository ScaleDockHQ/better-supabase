import { describe, expect, it } from "vitest";

import { createCatalog } from "../../../src/blocks/catalog/index.ts";

describe("catalog discounts", () => {
  it("resolves a line discount over the transport", async () => {
    const calls: { fn: string; args: unknown }[] = [];

    const catalog = createCatalog({
      transport: {
        call(_schema: string, fn: string, args: unknown) {
          calls.push({ fn, args });

          return Promise.resolve({
            discountBps: 1500,
            fixedPrice: null,
            currency: null,
            ruleId: "r1",
          });
        },
      },
    });

    const resolved = await catalog
      .resolveLineDiscount("org", "c1", "v1", 12, { on: "2026-10-31" })
      .orThrow();

    expect(resolved).toEqual({
      discountBps: 1500,
      fixedPrice: null,
      currency: null,
      ruleId: "r1",
    });
    expect(calls[0]).toEqual({
      fn: "resolve_line_discount",
      args: {
        tenant: "org",
        party: "c1",
        product: "v1",
        quantity: "12",
        on: "2026-10-31",
        currency: null,
      },
    });
  });
});

describe("catalog discount groups and rules", () => {
  const record: { fn: string; args: Record<string, unknown> }[] = [];

  const catalog = createCatalog({
    transport: {
      call(_schema: string, fn: string, args: Record<string, unknown>) {
        record.push({ fn, args });

        return Promise.resolve(fn.startsWith("save_") ? { id: "x1" } : true);
      },
    },
  });

  it("saves and deletes groups and assigns members", async () => {
    expect(
      await catalog
        .saveDiscountGroup("org", {
          kind: "customer",
          code: "VIP",
          name: "VIP",
        })
        .orThrow(),
    ).toEqual({ id: "x1" });
    expect(
      await catalog
        .saveDiscountGroup("org", {
          id: "g1",
          kind: "product",
          code: "P",
          name: "P",
        })
        .orThrow(),
    ).toEqual({ id: "x1" });
    expect(await catalog.deleteDiscountGroup("g1").orThrow()).toBe(true);
    expect(
      await catalog.setPartyDiscountGroup("org", "c1", null).orThrow(),
    ).toBe(true);
    expect(await catalog.setVariantDiscountGroup("v1", "g1").orThrow()).toBe(
      true,
    );
    expect(record[0]?.args["group"]).toBeNull();
    expect(record[1]?.args["group"]).toBe("g1");
  });

  it("saves a rule with text quantities and deletes it", async () => {
    await catalog
      .saveDiscountRule("org", {
        customerGroupId: "g1",
        discountBps: 500,
        minQuantity: 10,
        fixedPrice: 995n,
        currency: "EUR",
      })
      .orThrow();
    await catalog
      .saveDiscountRule("org", { id: "r1", discountBps: 100 })
      .orThrow();

    const [first, second] = record.slice(-2);

    expect(first?.args["attrs"]).toMatchObject({
      minQuantity: "10",
      fixedPrice: "995",
    });
    expect(second?.args["attrs"]).toMatchObject({
      minQuantity: undefined,
      fixedPrice: undefined,
    });
    expect(await catalog.deleteDiscountRule("r1").orThrow()).toBe(true);
  });
});

describe("catalog resolveLineDiscount defaults", () => {
  it("defaults the date to today and reads a bare reply", async () => {
    const seen: Record<string, unknown>[] = [];

    const catalog = createCatalog({
      transport: {
        call(_schema: string, _fn: string, args: Record<string, unknown>) {
          seen.push(args);

          return Promise.resolve({ discountBps: 0 });
        },
      },
    });

    const none = await catalog
      .resolveLineDiscount("org", null, "v1", "3", { currency: "EUR" })
      .orThrow();

    expect(none).toEqual({
      discountBps: 0,
      fixedPrice: null,
      currency: null,
      ruleId: null,
    });
    expect(seen[0]?.["on"]).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(seen[0]).toMatchObject({ party: null, currency: "EUR" });
  });
});
