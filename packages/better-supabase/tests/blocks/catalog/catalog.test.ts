import { describe, expect, it } from "vitest";

import type { Catalog } from "../../../src/blocks/catalog/index.ts";

import {
  catalogSubjects,
  createCatalog,
} from "../../../src/blocks/catalog/index.ts";
import { money } from "../../../src/commerce/index.ts";

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

describe("catalog block", () => {
  it("creates and updates products through save_product", async () => {
    const { calls, transport } = recorder({
      id: "p1",
      slug: "linen-shirt",
      status: "draft",
    });

    const catalog = createCatalog({ transport });
    expect(
      await catalog
        .createProduct("org", { title: "Linen Shirt", kind: "physical" })
        .orThrow(),
    ).toEqual({ id: "p1", slug: "linen-shirt", status: "draft" });
    await catalog
      .updateProduct("org", "p1", { title: "Linen Shirt", slug: "linen" })
      .orThrow();
    expect(calls).toEqual([
      {
        fn: "save_product",
        args: {
          tenant: "org",
          product: null,
          title: "Linen Shirt",
          slug: null,
          description: null,
          kind: "physical",
        },
      },
      {
        fn: "save_product",
        args: {
          tenant: "org",
          product: "p1",
          title: "Linen Shirt",
          slug: "linen",
          description: null,
          kind: null,
        },
      },
    ]);
  });

  it("refuses a status the database doesn't know", async () => {
    const { transport } = recorder({ status: "live", from: "draft" });

    const result = await createCatalog({ transport }).setProductStatus(
      "p1",
      "active",
    );

    expect(result.ok).toBe(false);
  });

  it("maps options and variants", async () => {
    const { calls, transport } = recorder(
      { id: "o1", values: [{ id: "v1", value: "S" }] },
      { id: "x1", sku: "TEE-S", rank: "V" },
    );

    const catalog = createCatalog({ transport });
    expect(
      await catalog.saveOption("p1", { name: "Size", values: ["S"] }).orThrow(),
    ).toEqual({ id: "o1", values: [{ id: "v1", value: "S" }] });
    expect(
      await catalog
        .createVariant("p1", {
          sku: "TEE-S",
          optionValues: ["v1"],
          weightGrams: 200,
        })
        .orThrow(),
    ).toEqual({ id: "x1", sku: "TEE-S", rank: "V" });
    expect(calls[1]).toEqual({
      fn: "save_variant",
      args: {
        product: "p1",
        variant: null,
        sku: "TEE-S",
        option_values: ["v1"],
        title: null,
        barcode: null,
        weight_grams: 200,
        track_inventory: null,
        allow_backorder: null,
      },
    });
  });

  it("sends amounts as minor-unit strings and reads them back as bigint", async () => {
    const { calls, transport } = recorder({
      id: "pr1",
      amount: "900719925474099300",
      previousAmount: "1299",
    });

    const catalog = createCatalog({ transport });

    const saved = await catalog
      .setPrice("x1", {
        amount: money(900_719_925_474_099_300n, "EUR"),
        compareAt: money(900_719_925_474_099_400n, "EUR"),
        validFrom: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      })
      .orThrow();

    expect(saved.amount).toEqual(money(900_719_925_474_099_300n, "EUR"));
    expect(saved.previousAmount).toEqual(money(1299n, "EUR"));
    expect(calls[0]).toEqual({
      fn: "set_price",
      args: {
        variant: "x1",
        currency: "EUR",
        amount: "900719925474099300",
        compare_at: "900719925474099400",
        price_list: null,
        valid_from: "2026-01-01T00:00:00Z",
        valid_until: null,
      },
    });
  });

  it("refuses a compare-at amount in another currency without a call", async () => {
    const { calls, transport } = recorder(null);

    const result = await createCatalog({ transport }).setPrice("x1", {
      amount: money(100, "EUR"),
      compareAt: money(200, "USD"),
    });

    expect(result).toMatchObject({
      ok: false,
      error: { hint: "CATALOG_COMPARE_AT_INVALID" },
    });
    expect(calls).toEqual([]);
  });

  it("resolves a variant price or null", async () => {
    const { transport } = recorder(
      {
        id: "pr1",
        variantId: "x1",
        currency: "JPY",
        amount: "1200",
        compareAt: null,
        priceListId: "l1",
      },
      null,
    );

    const catalog = createCatalog({ transport });
    expect(
      await catalog.variantPrice("x1", "JPY", { priceListId: "l1" }).orThrow(),
    ).toEqual({
      id: "pr1",
      variantId: "x1",
      amount: money(1200, "JPY"),
      priceListId: "l1",
    });
    expect(await catalog.variantPrice("x1", "JPY").orThrow()).toBeNull();
  });

  it("computes rank keys for variants, categories and collections", async () => {
    const { calls, transport } = recorder(true, true, "k");
    const catalog = createCatalog({ transport });
    expect(
      await catalog
        .reorderVariant("x1", { previous: "V", next: null })
        .orThrow(),
    ).toBe("k");
    expect(
      await catalog
        .moveCategory("c1", null, { previous: null, next: "V" })
        .orThrow(),
    ).toBe("F");
    expect(await catalog.addToCollection("k1", "p1").orThrow()).toBe("k");
    expect(calls.map((call) => call.args)).toEqual([
      { variant: "x1", rank: "k" },
      { category: "c1", parent: null, rank: "F" },
      { collection: "k1", product: "p1", rank: null },
    ]);

    const invalid = await catalog.reorderVariant("x1", {
      previous: "k",
      next: "V",
    });

    expect(invalid.ok).toBe(false);
  });

  it("stores a rule collection's filter tree", async () => {
    const { calls, transport } = recorder({
      id: "k1",
      slug: "physical",
      kind: "rule",
    });

    const rule = {
      id: "root",
      type: "group" as const,
      combinator: "and" as const,
      rules: [],
    };

    await createCatalog({ transport })
      .saveCollection("org", { title: "Physical", kind: "rule", rule })
      .orThrow();
    expect(calls[0]?.args).toMatchObject({ kind: "rule", rule });
  });

  it("runs hooks around a method", async () => {
    const { transport } = recorder(true);
    const seen: string[] = [];

    const catalog = createCatalog({
      transport,
      hooks: {
        deleteProduct: {
          before: (args) => {
            seen.push(`before ${args[0]}`);

            return args;
          },
          after: (result, _args, info) => {
            seen.push(`after ${info.block} ${String(result.ok)}`);
          },
        },
      },
    });

    await catalog.deleteProduct("p1").orThrow();
    expect(seen).toEqual(["before p1", "after catalog true"]);
  });

  it("describes products and variants as subjects with search columns", () => {
    const subjects = catalogSubjects({ schema: "shop" });
    expect(subjects["product"]).toMatchObject({
      table: "shop.products",
      tenant: "tenant_id",
      search: { title: "title", body: ["description", "slug"] },
    });
    expect(subjects["product_variant"]?.title).toBe("sku");
  });

  it("calls one function per method", async () => {
    const cases: [string, unknown, (catalog: Catalog) => Promise<unknown>][] = [
      [
        "set_product_status",
        { status: "active", from: "draft" },
        (c) => c.setProductStatus("p1", "active").orThrow(),
      ],
      ["delete_product_option", true, (c) => c.deleteOption("o1").orThrow()],
      [
        "save_variant",
        { id: "x1", sku: "S", rank: "V" },
        (c) => c.updateVariant("p1", "x1", { sku: "S" }).orThrow(),
      ],
      ["delete_variant", true, (c) => c.deleteVariant("x1").orThrow()],
      [
        "save_price_list",
        { id: "l1" },
        (c) => c.savePriceList("org", { name: "B2B" }).orThrow(),
      ],
      ["delete_price_list", true, (c) => c.deletePriceList("l1").orThrow()],
      ["delete_price", true, (c) => c.deletePrice("r1").orThrow()],
      [
        "save_category",
        { id: "c1", slug: "shirts", rank: "V" },
        (c) => c.saveCategory("org", { name: "Shirts" }).orThrow(),
      ],
      ["delete_category", true, (c) => c.deleteCategory("c1").orThrow()],
      [
        "set_product_categories",
        true,
        (c) => c.setProductCategories("p1", ["c1"]).orThrow(),
      ],
      [
        "save_collection",
        { id: "k1", slug: "new", kind: "manual" },
        (c) =>
          c.saveCollection("org", { title: "New", kind: "manual" }).orThrow(),
      ],
      ["delete_collection", true, (c) => c.deleteCollection("k1").orThrow()],
      [
        "add_to_collection",
        "k",
        (c) =>
          c
            .addToCollection("k1", "p1", { previous: "V", next: null })
            .orThrow(),
      ],
      [
        "remove_from_collection",
        true,
        (c) => c.removeFromCollection("k1", "p1").orThrow(),
      ],
      [
        "publish_storefront",
        true,
        (c) => c.publishStorefront("org", true).orThrow(),
      ],
    ];

    for (const [fn, result, run] of cases) {
      const { calls, transport } = recorder(result);
      await run(createCatalog({ transport }));
      expect(calls.map((call) => call.fn)).toEqual([fn]);
    }
  });

  it("refuses neighbors out of order without a call", async () => {
    const { calls, transport } = recorder(true);
    const catalog = createCatalog({ transport });
    const backwards = { previous: "V", next: "A" };
    expect((await catalog.moveCategory("c1", null, backwards)).ok).toBe(false);
    expect((await catalog.addToCollection("k1", "p1", backwards)).ok).toBe(
      false,
    );
    expect(calls).toEqual([]);
  });
});
