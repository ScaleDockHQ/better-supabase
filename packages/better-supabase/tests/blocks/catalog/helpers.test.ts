import { describe, expect, it, vi } from "vitest";

import type { Catalog } from "../../../src/blocks/catalog/catalog.ts";

import { catalogHelpers } from "../../../src/blocks/catalog/helpers.ts";
import { money } from "../../../src/commerce/money.ts";
import { AsyncResult } from "../../../src/core/result.ts";

function setup() {
  const client = {
    createProduct: vi.fn(() =>
      AsyncResult.ok({ id: "p1", slug: "mug", status: "draft" }),
    ),
    createVariant: vi.fn(() => AsyncResult.ok({ id: "v1", rank: "a" })),
    setPrice: vi.fn(() =>
      AsyncResult.ok({ id: "pr1", amount: money(1500, "EUR") }),
    ),
    setProductStatus: vi.fn(() =>
      AsyncResult.ok({ status: "active", from: "draft" }),
    ),
  };

  // SAFETY: the stub implements the methods the helper calls.
  const helpers = catalogHelpers(() => client as unknown as Catalog);

  return { client, helpers };
}

describe("catalog helpers", () => {
  it("createSimpleProduct makes a draft product with a variant and a price", async () => {
    const { client, helpers } = setup();

    const made = await helpers
      .createSimpleProduct({
        organizationId: "o",
        title: "Mug",
        price: money(1500, "EUR"),
        sku: "MUG-1",
      })
      .orThrow();

    expect(made.product.status).toBe("draft");
    expect(client.createVariant).toHaveBeenCalledWith({
      productId: "p1",
      input: { sku: "MUG-1" },
    });
    expect(client.setPrice).toHaveBeenCalledWith({
      variantId: "v1",
      input: { amount: money(1500, "EUR") },
    });
    expect(client.setProductStatus).not.toHaveBeenCalled();
  });

  it("createSimpleProduct publishes with publish", async () => {
    const { client, helpers } = setup();

    const made = await helpers
      .createSimpleProduct({
        organizationId: "o",
        title: "Mug",
        price: money(1500, "EUR"),
        publish: true,
      })
      .orThrow();

    expect(made.product.status).toBe("active");
    expect(client.setProductStatus).toHaveBeenCalledWith({
      productId: "p1",
      status: "active",
    });
  });
});
