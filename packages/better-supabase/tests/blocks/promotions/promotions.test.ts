import { describe, expect, it } from "vitest";

import { money } from "../../../src/blocks/commerce/index.ts";
import {
  createPromotions,
  PROMOTION_KINDS,
  PROMOTION_SCOPES,
} from "../../../src/blocks/promotions/index.ts";

function recorder(...results: unknown[]) {
  const calls: { fn: string; args: unknown }[] = [];
  return {
    calls,
    transport: {
      call(_schema: string, fn: string, args: unknown) {
        calls.push({ fn, args });
        return Promise.resolve(
          results.length > 1 ? results.shift() : results[0],
        );
      },
    },
  };
}

describe("promotions block", () => {
  it("lists its kinds and scopes", () => {
    expect(PROMOTION_KINDS).toEqual(["percentage", "fixed", "free_shipping"]);
    expect(PROMOTION_SCOPES).toEqual([
      "order",
      "products",
      "categories",
      "collections",
    ]);
  });

  it("saves a fixed promotion with its currency and limits", async () => {
    const { calls, transport } = recorder({ id: "p1" });
    const promotions = createPromotions({ transport });
    expect(
      await promotions
        .savePromotion("org", {
          name: "Ten off",
          discount: { kind: "fixed", amount: money(1000n, "EUR") },
          minSubtotal: money(5000n, "EUR"),
          scope: "categories",
          targets: ["c1"],
          startsAt: Temporal.Instant.from("2026-11-27T00:00:00Z"),
          endsAt: Temporal.Instant.from("2026-12-01T00:00:00Z"),
          usageLimit: 100,
          perCustomerLimit: 1,
          stackable: true,
          priority: 5,
        })
        .orThrow(),
    ).toEqual({ id: "p1" });
    expect(calls).toEqual([
      {
        fn: "save_promotion",
        args: {
          tenant: "org",
          promotion: null,
          data: {
            name: "Ten off",
            description: null,
            kind: "fixed",
            percent: null,
            amount: "1000",
            currency: "EUR",
            minSubtotal: "5000",
            scope: "categories",
            targets: ["c1"],
            startsAt: "2026-11-27T00:00:00Z",
            endsAt: "2026-12-01T00:00:00Z",
            usageLimit: 100,
            perCustomerLimit: 1,
            stackable: true,
            priority: 5,
            automatic: false,
            active: true,
          },
        },
      },
    ]);
  });

  it("saves percentage and free-shipping promotions with defaults", async () => {
    const { calls, transport } = recorder({ id: "p2" });
    const promotions = createPromotions({ transport });
    await promotions
      .savePromotion("org", {
        id: "p2",
        name: "Autumn",
        description: "Ten percent",
        discount: { kind: "percentage", percent: "10" },
        automatic: true,
        active: false,
      })
      .orThrow();
    await promotions
      .savePromotion("org", {
        name: "Ship free",
        discount: { kind: "free_shipping" },
        minSubtotal: money(4000n, "USD"),
      })
      .orThrow();
    expect(calls.map((entry) => entry.args)).toMatchObject([
      {
        promotion: "p2",
        data: {
          kind: "percentage",
          percent: "10",
          amount: null,
          currency: null,
          scope: "order",
          targets: [],
          startsAt: null,
          automatic: true,
          active: false,
          description: "Ten percent",
        },
      },
      {
        promotion: null,
        data: {
          kind: "free_shipping",
          percent: null,
          currency: "USD",
          minSubtotal: "4000",
        },
      },
    ]);
  });

  it("refuses a minimum in another currency than the discount", async () => {
    const { calls, transport } = recorder({ id: "p1" });
    const result = await createPromotions({ transport }).savePromotion("org", {
      name: "Mixed",
      discount: { kind: "fixed", amount: money(100n, "EUR") },
      minSubtotal: money(5000n, "USD"),
    });
    expect(result).toMatchObject({
      ok: false,
      error: { hint: "PROMOTIONS_INVALID" },
    });
    expect(calls).toEqual([]);
  });

  it("activates and deletes promotions and codes", async () => {
    const { calls, transport } = recorder(true, false, true);
    const promotions = createPromotions({ transport });
    expect(await promotions.setPromotionActive("p1", false).orThrow()).toBe(
      true,
    );
    expect(await promotions.deletePromotion("p1").orThrow()).toBe(false);
    expect(await promotions.deleteCode("k1").orThrow()).toBe(true);
    expect(calls).toEqual([
      { fn: "set_promotion_active", args: { promotion: "p1", active: false } },
      { fn: "delete_promotion", args: { promotion: "p1" } },
      { fn: "delete_promotion_code", args: { code: "k1" } },
    ]);
  });

  it("creates explicit and generated codes", async () => {
    const { calls, transport } = recorder(
      [{ id: "k1", code: "SAVE10" }],
      [
        { id: "k2", code: "BF-ABCDEFGH" },
        { id: "k3", code: "BF-JKLMNPQR" },
      ],
      null,
    );
    const promotions = createPromotions({ transport });
    expect(
      await promotions.createCodes("p1", { codes: ["save10"] }).orThrow(),
    ).toEqual([{ id: "k1", code: "SAVE10" }]);
    expect(
      await promotions
        .createCodes("p1", { count: 2, prefix: "BF-", usageLimit: 1 })
        .orThrow(),
    ).toHaveLength(2);
    expect(await promotions.createCodes("p1", { count: 1 }).orThrow()).toEqual(
      [],
    );
    expect(calls.map((entry) => entry.args)).toEqual([
      {
        promotion: "p1",
        codes: ["save10"],
        count: null,
        prefix: null,
        usage_limit: null,
      },
      {
        promotion: "p1",
        codes: null,
        count: 2,
        prefix: "BF-",
        usage_limit: 1,
      },
      {
        promotion: "p1",
        codes: null,
        count: 1,
        prefix: null,
        usage_limit: null,
      },
    ]);
  });

  it("applies and removes codes on a cart", async () => {
    const { calls, transport } = recorder(
      { codeId: "k1", code: "SAVE10", promotionId: "p1" },
      true,
    );
    const promotions = createPromotions({ transport });
    expect(await promotions.applyCode("c1", "save10").orThrow()).toEqual({
      codeId: "k1",
      code: "SAVE10",
      promotionId: "p1",
    });
    expect(await promotions.removeCode("c1", "SAVE10").orThrow()).toBe(true);
    expect(calls).toEqual([
      { fn: "apply_promotion_code", args: { cart: "c1", code: "save10" } },
      { fn: "remove_promotion_code", args: { cart: "c1", code: "SAVE10" } },
    ]);
  });

  it("runs hooks around its methods", async () => {
    const { transport } = recorder(true);
    const seen: string[] = [];
    const promotions = createPromotions({
      transport,
      hooks: {
        setPromotionActive: {
          before: ([promotionId, active]) => {
            seen.push(`before ${promotionId}`);
            return [promotionId, active];
          },
        },
      },
    });
    await promotions.setPromotionActive("p1", true).orThrow();
    expect(seen).toEqual(["before p1"]);
  });
});
