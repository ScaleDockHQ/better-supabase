import { describe, expect, it } from "vitest";

import { createCatalog } from "../../../src/blocks/catalog/index.ts";
import { money } from "../../../src/commerce/index.ts";

function recorder(...results: unknown[]) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    transport: {
      call(_schema: string, fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });

        return Promise.resolve(
          results.length > 1 ? results.shift() : results[0],
        );
      },
    },
  };
}

const silent = { debug() {}, info() {}, warn() {}, error() {} };

describe("catalog row mapping", () => {
  it("maps sparse variants, options and prices", async () => {
    const { transport } = recorder(
      { id: "v1", rank: "a", fields: { color: "red" } },
      { id: "v2", sku: "S", rank: "b", fields: "no" },
      {
        options: [
          { id: "o1", name: "Size", values: [{ id: "ov1", value: "S" }] },
        ],
        variants: [
          { id: "v1", sku: "S", optionValueIds: ["ov1"] },
          { id: "v2", optionValueIds: "none" },
        ],
      },
      {
        id: "pr1",
        variantId: "v1",
        amount: "1200",
        currency: "EUR",
        compareAt: "1500",
        priceListId: "l1",
      },
    );

    const catalog = createCatalog({ transport, logger: silent });

    const bare = await catalog
      .createVariant({ productId: "p1", input: { sku: "X" } })
      .orThrow();

    expect(bare).toEqual({ id: "v1", rank: "a", fields: { color: "red" } });

    const full = await catalog
      .updateVariant({ productId: "p1", variantId: "v2", input: {} })
      .orThrow();

    expect(full).toEqual({ id: "v2", sku: "S", rank: "b" });

    const matrix = await catalog
      .setOptions({
        productId: "p1",
        options: [{ name: "Size", values: ["S"] }],
        settings: { titleSeparator: " / " },
      })
      .orThrow();

    expect(matrix.variants[0]).toEqual({
      id: "v1",
      sku: "S",
      optionValueIds: ["ov1"],
    });
    expect(matrix.variants[1]?.sku).toBeUndefined();

    const price = await catalog
      .variantPrice({ variantId: "v1", currency: "EUR" })
      .orThrow();

    expect(price?.compareAt).toEqual(money(1500, "EUR"));
    expect(price?.priceListId).toBe("l1");
  });

  it("omits the title separator without settings", async () => {
    const { calls, transport } = recorder({ options: [], variants: [] });

    await createCatalog({ transport })
      .setOptions({ productId: "p1", options: [] })
      .orThrow();

    expect(calls[0]?.args).toEqual({ product: "p1", options: [] });
  });

  it("clears every nullable variant column", async () => {
    const { calls, transport } = recorder({ id: "v1", rank: "a" });

    await createCatalog({ transport })
      .updateVariant({
        productId: "p1",
        variantId: "v1",
        input: { sku: null, title: null, barcode: null, weightGrams: null },
      })
      .orThrow();

    expect(calls[0]?.args["clear"]).toEqual([
      "sku",
      "title",
      "barcode",
      "weight",
    ]);
  });

  it("sets a price with validity dates and reports the previous amount", async () => {
    const { calls, transport } = recorder(
      { id: "pr1", amount: "900", previousAmount: "1000" },
      { id: "pr2", amount: "900" },
    );

    const catalog = createCatalog({ transport });

    const changed = await catalog
      .setPrice({
        variantId: "v1",
        input: {
          amount: money(900, "EUR"),
          compareAt: money(1200, "EUR"),
          priceListId: "l1",
          validFrom: Temporal.Instant.from("2026-01-01T00:00:00Z"),
          validUntil: Temporal.Instant.from("2026-02-01T00:00:00Z"),
        },
      })
      .orThrow();

    expect(changed.previousAmount).toEqual(money(1000, "EUR"));
    expect(calls[0]?.args["starts_at"]).not.toBeNull();
    expect(calls[0]?.args["expires_at"]).not.toBeNull();

    const first = await catalog
      .setPrice({ variantId: "v1", input: { amount: money(900, "EUR") } })
      .orThrow();

    expect(first.previousAmount).toBeUndefined();
    expect(calls[1]?.args).toMatchObject({
      starts_at: null,
      expires_at: null,
      price_list: null,
      compare_at: null,
    });
  });

  it("refuses a compare-at price in another currency", async () => {
    const { calls, transport } = recorder(true);

    const result = await createCatalog({ transport }).setPrice({
      variantId: "v1",
      input: { amount: money(900, "EUR"), compareAt: money(1200, "USD") },
    });

    expect(result.ok).toBe(false);
    expect(calls).toHaveLength(0);
  });
});

describe("channels and listings", () => {
  it("saves a channel with and without the optional columns", async () => {
    const { calls, transport } = recorder(
      { id: "c1", key: "web", active: true },
      { id: "c2", key: "pos", active: "yes" },
    );

    const catalog = createCatalog({ transport });

    await catalog
      .saveChannel({
        organizationId: "o",
        input: {
          id: "c1",
          key: "web",
          name: "Web",
          currency: "EUR",
          priceListId: "l1",
          active: true,
        },
      })
      .orThrow();

    const bare = await catalog
      .saveChannel({ organizationId: "o", input: { key: "pos", name: "POS" } })
      .orThrow();

    expect(bare.active).toBe(false);
    expect(calls[0]?.args).toMatchObject({
      channel: "c1",
      currency: "EUR",
      price_list: "l1",
      active: true,
    });
    expect(calls[1]?.args).toMatchObject({
      channel: null,
      currency: null,
      price_list: null,
      active: null,
    });
  });

  it("counts listed products from a number or text and rejects other values", async () => {
    const { transport } = recorder(2, "3", "abc");
    const catalog = createCatalog({ transport });

    await expect(
      catalog.listOnChannel({ channelId: "c", productIds: ["a"] }).orThrow(),
    ).resolves.toBe(2);
    await expect(
      catalog
        .unlistFromChannel({ channelId: "c", productIds: ["a"] })
        .orThrow(),
    ).resolves.toBe(3);

    const bad = await catalog.listOnChannel({
      channelId: "c",
      productIds: ["a"],
    });

    expect(bad.ok).toBe(false);
  });

  it("reads channel products without a kind, locale or page", async () => {
    const { calls, transport } = recorder([
      {
        id: "p1",
        slug: "s",
        status: "active",
        kind: null,
        locale: "en",
        title: "T",
        description: "D",
        listedAt: "2026-03-01T10:00:00Z",
      },
    ]);

    const [product] = await createCatalog({ transport })
      .channelProducts({ channelId: "c1" })
      .orThrow();

    expect(product).toMatchObject({ description: "D" });
    expect(product).not.toHaveProperty("kind");
    expect(calls[0]?.args).toEqual({
      channel: "c1",
      locale: null,
      page_size: null,
      after: null,
    });
  });

  it("rejects an unknown product kind", async () => {
    const { transport } = recorder([
      {
        id: "p1",
        slug: "s",
        status: "active",
        kind: "bogus",
        locale: "en",
        title: "T",
        listedAt: "2026-03-01T10:00:00Z",
      },
    ]);

    const result = await createCatalog({ transport }).channelProducts({
      channelId: "c1",
    });

    expect(result.ok).toBe(false);
  });

  it("prices a variant on a channel as of a moment", async () => {
    const { calls, transport } = recorder(
      { id: "pr", variantId: "v", amount: "100", currency: "EUR" },
      "none",
    );

    const catalog = createCatalog({ transport });

    await catalog
      .channelPrice({
        channelId: "c1",
        variantId: "v",
        at: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      })
      .orThrow();

    expect(calls[0]?.args["as_of"]).not.toBeNull();

    await expect(
      catalog.channelPrice({ channelId: "c1", variantId: "v" }).orThrow(),
    ).resolves.toBeNull();
    expect(calls[1]?.args["as_of"]).toBeNull();
  });
});

describe("translations and media", () => {
  it("sends partial translations as nulls", async () => {
    const { calls, transport } = recorder(true);
    const catalog = createCatalog({ transport });

    await catalog
      .setProductTranslation({
        productId: "p1",
        locale: "de",
        translation: { description: "Beschreibung" },
      })
      .orThrow();

    expect(calls[0]?.args).toMatchObject({
      title: null,
      description: "Beschreibung",
    });

    await catalog
      .setProductTranslation({
        productId: "p1",
        locale: "de",
        translation: { title: "Titel" },
      })
      .orThrow();

    expect(calls[1]?.args).toMatchObject({ title: "Titel", description: null });
  });

  it("maps localized product text with and without optional parts", async () => {
    const { transport } = recorder(
      {
        id: "p1",
        slug: "s",
        locale: "en",
        title: "T",
        description: "D",
        variants: [
          { id: "v1", sku: "S", title: "VT" },
          { id: "v2", sku: "S2" },
        ],
      },
      { id: "p1", slug: "s", locale: "en", title: "T", variants: [] },
      null,
    );

    const catalog = createCatalog({ transport });
    const full = await catalog.productText({ productId: "p1" }).orThrow();

    expect(full?.description).toBe("D");
    expect(full?.variants[0]?.title).toBe("VT");
    expect(full?.variants[1]).not.toHaveProperty("title");

    const bare = await catalog.productText({ productId: "p1" }).orThrow();

    expect(bare).not.toHaveProperty("description");
    await expect(
      catalog.productText({ productId: "p1" }).orThrow(),
    ).resolves.toBeNull();
  });

  it("adds and updates media with and without variant and alt text", async () => {
    const { calls, transport } = recorder(
      { id: "m1", position: "1" },
      { id: "m2", position: 2 },
      true,
      true,
    );

    const catalog = createCatalog({ transport });

    await catalog
      .addProductMedia({ productId: "p1", attachmentId: "a1" })
      .orThrow();
    await catalog
      .addProductMedia({
        productId: "p1",
        attachmentId: "a2",
        input: { variantId: "v1", alt: { en: "Front" } },
      })
      .orThrow();
    await catalog.updateProductMedia({ mediaId: "m1", input: {} }).orThrow();
    await catalog
      .updateProductMedia({
        mediaId: "m1",
        input: { variantId: "v1", alt: { en: "Back" } },
      })
      .orThrow();

    expect(calls[0]?.args).toMatchObject({ variant: null, alt: null });
    expect(calls[1]?.args).toMatchObject({
      variant: "v1",
      alt: { en: "Front" },
    });
    expect(calls[2]?.args).toMatchObject({ variant: null, alt: null });
    expect(calls[3]?.args).toMatchObject({
      variant: "v1",
      alt: { en: "Back" },
    });
  });

  it("maps media rows with and without variant and alt text", async () => {
    const { transport } = recorder([
      {
        id: "m1",
        attachmentId: "a1",
        variantId: "v1",
        position: 0,
        alt: "Front",
        altByLocale: { en: "Front", de: 1 },
      },
      { id: "m2", attachmentId: "a2", position: 1, altByLocale: "none" },
    ]);

    const media = await createCatalog({ transport })
      .productMedia({ productId: "p1" })
      .orThrow();

    expect(media[0]).toEqual({
      id: "m1",
      attachmentId: "a1",
      variantId: "v1",
      position: 0,
      alt: "Front",
      altByLocale: { en: "Front" },
    });
    expect(media[1]).toEqual({
      id: "m2",
      attachmentId: "a2",
      position: 1,
      altByLocale: {},
    });
  });
});

describe("channels and simple products", () => {
  it("deletes a channel", async () => {
    const { calls, transport } = recorder(true);

    await expect(
      createCatalog({ transport }).deleteChannel("c1").orThrow(),
    ).resolves.toBe(true);
    expect(calls[0]).toEqual({
      fn: "delete_catalog_channel",
      args: { channel: "c1" },
    });
  });

  it("creates a simple product through the hooked client", async () => {
    const { calls, transport } = recorder(
      { id: "p1", slug: "mug", status: "draft" },
      { id: "v1", rank: "a" },
      { id: "pr1", amount: "900" },
    );

    const created = await createCatalog({ transport })
      .createSimpleProduct({
        organizationId: "o",
        title: "Mug",
        price: money(900, "EUR"),
      })
      .orThrow();

    expect(created.product.id).toBe("p1");
    expect(calls.map((call) => call.fn)).toEqual([
      "save_product",
      "save_variant",
      "set_price",
    ]);
  });
});

describe("logger", () => {
  it("passes the logger to the block hooks", async () => {
    const { transport } = recorder(true);
    const catalog = createCatalog({ transport, logger: silent });

    await expect(catalog.removeProductMedia("m1").orThrow()).resolves.toBe(
      true,
    );
  });
});
