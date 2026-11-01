import { describe, expect, it } from "vitest";

import { createPromotions } from "../../../src/blocks/promotions/index.ts";

function setup(codes: (args: Record<string, unknown>) => unknown) {
  const calls: [string, Record<string, unknown>][] = [];

  const promotions = createPromotions({
    transport: {
      call(_schema: string, fn: string, args: Record<string, unknown>) {
        calls.push([fn, args]);

        if (fn === "save_promotion") {
          return Promise.resolve({ id: "p1" });
        }

        if (fn === "create_promotion_codes") {
          return Promise.resolve().then(() => codes(args));
        }

        return Promise.resolve(true);
      },
    },
  });

  return { promotions, calls };
}

const INPUT = {
  name: "Black Friday",
  discount: { kind: "percentage", percent: "20" },
} as const;

describe("promotions helpers", () => {
  it("createWithCode saves the promotion and one code", async () => {
    const { promotions, calls } = setup(() => [{ id: "c1", code: "BF20" }]);

    const made = await promotions
      .createWithCode({
        organizationId: "o",
        input: INPUT,
        code: "bf20",
        usageLimit: 50,
      })
      .orThrow();

    expect(made.promotion.id).toBe("p1");
    expect(made.code).toEqual({ id: "c1", code: "BF20" });
    expect(calls[1]).toEqual([
      "create_promotion_codes",
      {
        promotion: "p1",
        codes: ["bf20"],
        count: null,
        prefix: null,
        usage_limit: 50,
      },
    ]);
  });

  it("deletes a new promotion again when the code is refused", async () => {
    const { promotions, calls } = setup(() => {
      throw new Error("boom");
    });

    const made = await promotions.createWithCode({
      organizationId: "o",
      input: INPUT,
      code: "BF20",
    });

    expect(made.ok).toBe(false);
    expect(calls.map(([fn]) => fn)).toEqual([
      "save_promotion",
      "create_promotion_codes",
      "delete_promotion",
    ]);
  });

  it("keeps an existing promotion when its code is refused", async () => {
    const { promotions, calls } = setup(() => {
      throw new Error("boom");
    });

    await promotions.createWithCode({
      organizationId: "o",
      input: { ...INPUT, id: "p1" },
      code: "BF20",
    });

    expect(calls.map(([fn]) => fn)).not.toContain("delete_promotion");
  });
});
