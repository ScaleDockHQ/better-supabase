import { describe, expect, it } from "vitest";

import type { Catalog } from "../../../src/blocks/catalog/index.ts";

import { createCatalog } from "../../../src/blocks/catalog/index.ts";
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
  it("clears a product price and patches a variant without a SKU", async () => {
    const { calls, transport } = recorder(
      { id: "p1", slug: "mug", status: "active" },
      { id: "v1", sku: "MUG", rank: "a" },
    );

    const catalog = createCatalog({ transport });
    await catalog
      .updateProduct("org", "p1", { title: "Mug", price: null })
      .orThrow();
    await catalog.updateVariant("p1", "v1", { allowBackorder: true }).orThrow();
    expect(calls).toEqual([
      {
        fn: "save_product",
        args: {
          tenant: "org",
          product: "p1",
          title: "Mug",
          slug: null,
          description: null,
          kind: null,
          clear: ["price"],
        },
      },
      {
        fn: "save_variant",
        args: {
          product: "p1",
          variant: "v1",
          sku: null,
          option_values: null,
          title: null,
          barcode: null,
          weight_grams: null,
          track_inventory: null,
          allow_backorder: true,
        },
      },
    ]);
  });

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

  it("sends a product's own price and tracking, and variant and category fields", async () => {
    const { calls, transport } = recorder(
      { id: "p1", slug: "shirt", status: "active" },
      { id: "x1", sku: "S", rank: "V", fields: { is_default: true } },
      { id: "c1", slug: "shirts", rank: "V", fields: { icon: "Shirt" } },
    );

    const catalog = createCatalog({ transport });
    await catalog
      .createProduct("org", {
        title: "Shirt",
        price: money(990n, "EUR"),
        trackInventory: false,
      })
      .orThrow();
    expect(
      await catalog
        .createVariant("p1", { sku: "S", fields: { is_default: true } })
        .orThrow(),
    ).toEqual({ id: "x1", sku: "S", rank: "V", fields: { is_default: true } });
    expect(
      await catalog
        .saveCategory("org", { name: "Shirts", fields: { icon: "Shirt" } })
        .orThrow(),
    ).toMatchObject({ fields: { icon: "Shirt" } });
    expect(calls[0]?.args).toMatchObject({
      price: "990",
      currency: "EUR",
      track_inventory: false,
    });
    expect(calls[1]?.args).toMatchObject({ fields: { is_default: true } });
    expect(calls[2]?.args).toMatchObject({ fields: { icon: "Shirt" } });
  });

  it("refuses a status the database doesn't know", async () => {
    const { transport } = recorder({ status: "live", from: "draft" });

    const result = await createCatalog({ transport }).setProductStatus(
      "p1",
      "active",
    );

    expect(result.ok).toBe(false);
  });

  it("sets a variant's status", async () => {
    const { calls, transport } = recorder({
      id: "v1",
      status: "discontinued",
      from: "active",
    });

    const result = await createCatalog({ transport })
      .setVariantStatus("v1", "discontinued")
      .orThrow();

    expect(result).toEqual({ status: "discontinued", from: "active" });
    expect(calls).toEqual([
      {
        fn: "set_variant_status",
        args: { variant: "v1", status: "discontinued" },
      },
    ]);
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

  it("writes whole-number ranks with rankType integer", async () => {
    const { calls, transport } = recorder(true, true, true, "7");
    const catalog = createCatalog({ transport, rankType: "integer" });
    expect(
      await catalog
        .reorderVariant("x1", { previous: "2", next: null })
        .orThrow(),
    ).toBe("3");
    expect(
      await catalog
        .moveCategory("c1", null, { previous: "2", next: "8" })
        .orThrow(),
    ).toBe("5");
    expect(
      await catalog.moveCategory("c1", "c0", { position: 4 }).orThrow(),
    ).toBe("4");
    expect(
      await catalog
        .addToCollection("k1", "p1", { previous: null, next: "1" })
        .orThrow(),
    ).toBe("7");
    expect(calls.map((call) => call.args)).toEqual([
      { variant: "x1", rank: "3" },
      { category: "c1", parent: null, rank: "5" },
      { category: "c1", parent: "c0", rank: "4" },
      { collection: "k1", product: "p1", rank: "0" },
    ]);

    const full = await catalog.reorderVariant("x1", {
      previous: "2",
      next: "3",
    });

    const text = await catalog.reorderVariant("x1", {
      previous: "V",
      next: null,
    });

    const fraction = await catalog.reorderVariant("x1", { position: 1.5 });

    expect([full, text, fraction].map((result) => result.ok)).toEqual([
      false,
      false,
      false,
    ]);
    expect(full.ok ? undefined : full.error.hint).toBe("RANK_KEY_INVALID");
    expect(calls).toHaveLength(4);
  });

  it("refuses a position with text ranks", async () => {
    const { calls, transport } = recorder(true);
    const catalog = createCatalog({ transport });
    const moved = await catalog.moveCategory("c1", null, { position: 2 });

    expect(moved.ok ? undefined : moved.error.hint).toBe("RANK_KEY_INVALID");
    expect(calls).toHaveLength(0);
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

  it("saves channels and lists products on them", async () => {
    const { calls, transport } = recorder(
      { id: "ch1", key: "web", active: true },
      2,
      1,
    );

    const catalog = createCatalog({ transport });

    expect(
      await catalog
        .saveChannel("org", { key: "web", name: "Web", currency: "EUR" })
        .orThrow(),
    ).toEqual({ id: "ch1", key: "web", active: true });
    expect(await catalog.listOnChannel("ch1", ["p1", "p2"]).orThrow()).toBe(2);
    expect(await catalog.unlistFromChannel("ch1", ["p1"]).orThrow()).toBe(1);
    expect(calls).toEqual([
      {
        fn: "save_catalog_channel",
        args: {
          tenant: "org",
          channel: null,
          key: "web",
          name: "Web",
          currency: "EUR",
          price_list: null,
          active: null,
        },
      },
      {
        fn: "set_channel_listing",
        args: { channel: "ch1", products: ["p1", "p2"], listed: true },
      },
      {
        fn: "set_channel_listing",
        args: { channel: "ch1", products: ["p1"], listed: false },
      },
    ]);
  });

  it("reads a channel's products in a locale", async () => {
    const { calls, transport } = recorder([
      {
        id: "p1",
        slug: "linen-shirt",
        status: "active",
        kind: "physical",
        locale: "de",
        title: "Leinenhemd",
        description: null,
        listedAt: "2026-03-01T10:00:00Z",
      },
    ]);

    const products = await createCatalog({ transport })
      .channelProducts("ch1", { locale: "de-AT", limit: 20 })
      .orThrow();

    expect(products).toEqual([
      {
        id: "p1",
        slug: "linen-shirt",
        status: "active",
        kind: "physical",
        locale: "de",
        title: "Leinenhemd",
        listedAt: Temporal.Instant.from("2026-03-01T10:00:00Z"),
      },
    ]);
    expect(calls[0]).toEqual({
      fn: "channel_products",
      args: { channel: "ch1", locale: "de-AT", page_size: 20, after: null },
    });
  });

  it("sets translations and reads the text in a locale", async () => {
    const { calls, transport } = recorder(true, true, {
      id: "p1",
      slug: "linen-shirt",
      locale: "de",
      title: "Leinenhemd",
      description: "Aus Leinen",
      variants: [
        { id: "x1", sku: "TEE-S", title: "Klein" },
        { id: "x2", sku: "TEE-M", title: null },
      ],
    });

    const catalog = createCatalog({ transport });

    await catalog
      .setProductTranslation("p1", "de", { title: "Leinenhemd" })
      .orThrow();
    await catalog.setVariantTranslation("x1", "de", "Klein").orThrow();
    expect(await catalog.productText("p1", { locale: "de" }).orThrow()).toEqual(
      {
        id: "p1",
        slug: "linen-shirt",
        locale: "de",
        title: "Leinenhemd",
        description: "Aus Leinen",
        variants: [
          { id: "x1", sku: "TEE-S", title: "Klein" },
          { id: "x2", sku: "TEE-M" },
        ],
      },
    );
    expect(calls.map((call) => call.args)).toEqual([
      { product: "p1", locale: "de", title: "Leinenhemd", description: null },
      { variant: "x1", locale: "de", title: "Klein" },
      { product: "p1", locale: "de" },
    ]);
  });

  it("resolves a missing product's text to null", async () => {
    const { transport } = recorder(null);

    expect(
      await createCatalog({ transport }).productText("p1").orThrow(),
    ).toBeNull();
  });

  it("clears product and variant columns with null and reorders options", async () => {
    const { calls, transport } = recorder(
      { id: "p1", slug: "mug", status: "active" },
      { id: "v1", sku: null, rank: "a" },
      true,
    );

    const catalog = createCatalog({ transport });
    await catalog
      .updateProduct("org", "p1", { description: null, slug: null })
      .orThrow();
    expect(
      await catalog
        .updateVariant("p1", "v1", { sku: null, barcode: null })
        .orThrow(),
    ).toEqual({ id: "v1", rank: "a" });
    await catalog.reorderOptions("p1", ["o2", "o1"]).orThrow();
    expect(calls.map((call) => call.args)).toEqual([
      expect.objectContaining({ title: null, clear: ["slug", "description"] }),
      expect.objectContaining({ sku: null, clear: ["sku", "barcode"] }),
      { product: "p1", options: ["o2", "o1"] },
    ]);
  });

  it("replaces options and reads the variant matrix", async () => {
    const { calls, transport } = recorder({
      options: [{ id: "o1", name: "Size", values: [{ id: "s", value: "S" }] }],
      variants: [{ id: "v1", sku: null, optionValueIds: ["s"] }],
    });

    expect(
      await createCatalog({ transport })
        .setOptions("p1", [{ name: "Size", values: ["S"] }], {
          titleSeparator: null,
        })
        .orThrow(),
    ).toEqual({
      options: [{ id: "o1", name: "Size", values: [{ id: "s", value: "S" }] }],
      variants: [{ id: "v1", optionValueIds: ["s"] }],
    });
    expect(calls).toEqual([
      {
        fn: "set_product_options",
        args: {
          product: "p1",
          options: [{ name: "Size", values: ["S"] }],
          title_separator: null,
        },
      },
    ]);
  });

  it("adds, orders and reads product media", async () => {
    const { calls, transport } = recorder({ id: "m1", position: 0 }, true, [
      {
        id: "m1",
        attachmentId: "a1",
        variantId: null,
        position: 0,
        alt: "Linen shirt",
        altByLocale: { en: "Linen shirt", de: "Leinenhemd" },
      },
    ]);

    const catalog = createCatalog({ transport });

    expect(
      await catalog
        .addProductMedia("p1", "a1", { alt: { en: "Linen shirt" } })
        .orThrow(),
    ).toEqual({ id: "m1", position: 0 });
    await catalog.reorderProductMedia("p1", ["m1"]).orThrow();
    expect(await catalog.productMedia("p1").orThrow()).toEqual([
      {
        id: "m1",
        attachmentId: "a1",
        position: 0,
        alt: "Linen shirt",
        altByLocale: { en: "Linen shirt", de: "Leinenhemd" },
      },
    ]);
    expect(calls).toEqual([
      {
        fn: "add_product_media",
        args: {
          product: "p1",
          attachment: "a1",
          variant: null,
          alt: { en: "Linen shirt" },
        },
      },
      { fn: "reorder_product_media", args: { product: "p1", media: ["m1"] } },
      { fn: "product_media", args: { product: "p1", locale: null } },
    ]);
  });
});
