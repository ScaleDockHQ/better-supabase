import { describe, expect, it } from "vitest";

import { createCatalog } from "../../../src/blocks/catalog/index.ts";

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

describe("product identifiers", () => {
  it("saves with and without a party and reports whether it was new", async () => {
    const { calls, transport } = recorder(
      { id: "i1", created: true },
      { id: "i2", created: "no" },
    );

    const catalog = createCatalog({ transport });

    const first = await catalog
      .saveProductIdentifier({
        organizationId: "o",
        input: { variantId: "v1", type: "ean", value: "123", partyId: "s1" },
      })
      .orThrow();

    const second = await catalog
      .saveProductIdentifier({
        organizationId: "o",
        input: { variantId: "v1", type: "other", value: "456" },
      })
      .orThrow();

    expect(first).toEqual({ id: "i1", created: true });
    expect(second).toEqual({ id: "i2", created: false });
    expect(calls[0]?.args["party"]).toBe("s1");
    expect(calls[1]?.args["party"]).toBeNull();
  });

  it("deletes, finds and lists identifiers", async () => {
    const { calls, transport } = recorder(
      true,
      [
        {
          identifierId: "i1",
          variantId: "v1",
          productId: "p1",
          sku: "S",
          type: "supplier",
          value: "x",
          partyId: "s1",
        },
        {
          identifierId: "i2",
          variantId: "v2",
          productId: "p2",
          sku: "T",
          type: "manufacturer",
          value: "y",
        },
      ],
      [{ id: "i1", type: "ean", value: "1", partyId: null }],
      [],
    );

    const catalog = createCatalog({ transport });

    await expect(catalog.deleteProductIdentifier("i1").orThrow()).resolves.toBe(
      true,
    );

    const found = await catalog
      .findVariantsByIdentifier({
        organizationId: "o",
        value: "x",
        type: "supplier",
        partyId: "s1",
      })
      .orThrow();

    expect(found[0]).toMatchObject({ type: "supplier", partyId: "s1" });
    expect(found[1]?.partyId).toBeNull();
    expect(calls[1]?.args).toMatchObject({ type: "supplier", party: "s1" });

    const listed = await catalog.variantIdentifiers("v1").orThrow();

    expect(listed).toEqual([
      { id: "i1", type: "ean", value: "1", partyId: null },
    ]);

    await catalog
      .findVariantsByIdentifier({ organizationId: "o", value: "z" })
      .orThrow();

    expect(calls[3]?.args).toMatchObject({ type: null, party: null });
  });

  it("rejects an unknown identifier type", async () => {
    const { transport } = recorder([{ id: "i1", type: "isbn", value: "1" }]);

    const result = await createCatalog({ transport }).variantIdentifiers("v1");

    expect(result.ok).toBe(false);
  });
});

describe("product relations", () => {
  it("saves, deletes and lists relations in both directions", async () => {
    const { calls, transport } = recorder(
      { created: true },
      { created: false },
      true,
      [
        {
          kind: "alternative",
          direction: "incoming",
          variantId: "a",
          sku: "A",
        },
        { kind: "accessory", direction: "other", variantId: "b", sku: "B" },
      ],
      [],
      "v9",
    );

    const catalog = createCatalog({ transport });

    await expect(
      catalog
        .saveProductRelation({
          organizationId: "o",
          input: { fromVariantId: "a", toVariantId: "b", kind: "accessory" },
        })
        .orThrow(),
    ).resolves.toEqual({ created: true });

    await expect(
      catalog
        .saveProductRelation({
          organizationId: "o",
          input: { fromVariantId: "a", toVariantId: "b", kind: "accessory" },
        })
        .orThrow(),
    ).resolves.toEqual({ created: false });

    await expect(
      catalog
        .deleteProductRelation({
          fromVariantId: "a",
          toVariantId: "b",
          kind: "accessory",
        })
        .orThrow(),
    ).resolves.toBe(true);

    const related = await catalog
      .variantRelations({ variantId: "a", kind: "alternative" })
      .orThrow();

    expect(related.map((entry) => entry.direction)).toEqual([
      "incoming",
      "outgoing",
    ]);
    expect(calls[3]?.args["kind"]).toBe("alternative");

    await catalog.variantRelations({ variantId: "a" }).orThrow();
    expect(calls[4]?.args["kind"]).toBeNull();

    await expect(catalog.replacementVariant("a").orThrow()).resolves.toBe("v9");
  });

  it("rejects an unknown relation kind", async () => {
    const { transport } = recorder([
      { kind: "cousin", direction: "incoming", variantId: "a", sku: "A" },
    ]);

    const result = await createCatalog({ transport }).variantRelations({
      variantId: "a",
    });

    expect(result.ok).toBe(false);
  });
});

describe("supplier items", () => {
  it("saves with every column or only the required ones", async () => {
    const { calls, transport } = recorder(
      { id: "s1", code: "C1" },
      { id: "s2", code: "C2" },
    );

    const catalog = createCatalog({ transport });

    await catalog
      .saveSupplierItem({
        organizationId: "o",
        input: {
          id: "s1",
          supplierId: "sup",
          code: "C1",
          description: "Bolt",
          price: 1250n,
          currency: "EUR",
          unit: "pc",
          keywords: "steel",
        },
      })
      .orThrow();

    await catalog
      .saveSupplierItem({
        organizationId: "o",
        input: { supplierId: "sup", code: "C2" },
      })
      .orThrow();

    expect(calls[0]?.args).toMatchObject({
      item: "s1",
      price: "1250",
      keywords: "steel",
    });
    expect(calls[1]?.args).toEqual({
      tenant: "o",
      item: null,
      supplier: "sup",
      code: "C2",
      description: null,
      price: null,
      currency: null,
      unit: null,
      keywords: null,
    });
  });

  it("deletes, searches and promotes", async () => {
    const { calls, transport } = recorder(
      true,
      [
        {
          id: "s1",
          supplierId: "sup",
          code: "C1",
          description: "Bolt",
          price: "1250",
          currency: "EUR",
          unit: "pc",
          variantId: "v1",
        },
        { id: "s2", supplierId: "sup", code: "C2" },
      ],
      [],
      { productId: "p1", variantId: "v1", created: true },
      { productId: "p1", variantId: "v1" },
    );

    const catalog = createCatalog({ transport });

    await expect(catalog.deleteSupplierItem("s1").orThrow()).resolves.toBe(
      true,
    );

    const found = await catalog
      .searchSupplierItems({
        organizationId: "o",
        query: "bolt",
        supplierId: "sup",
        limit: 5,
      })
      .orThrow();

    expect(found[0]).toMatchObject({ price: 1250n, variantId: "v1" });
    expect(found[1]).toEqual({
      id: "s2",
      supplierId: "sup",
      code: "C2",
      description: null,
      price: null,
      currency: null,
      unit: null,
      variantId: null,
    });
    expect(calls[1]?.args).toMatchObject({ supplier: "sup", row_limit: 5 });

    await catalog
      .searchSupplierItems({ organizationId: "o", query: "x" })
      .orThrow();
    expect(calls[2]?.args).toMatchObject({ supplier: null, row_limit: null });

    await expect(
      catalog.promoteSupplierItem({ itemId: "s1", sku: "SKU" }).orThrow(),
    ).resolves.toEqual({ productId: "p1", variantId: "v1", created: true });
    expect(calls[3]?.args["sku"]).toBe("SKU");

    const again = await catalog.promoteSupplierItem({ itemId: "s1" }).orThrow();

    expect(again.created).toBe(false);
    expect(calls[4]?.args["sku"]).toBeNull();
  });
});

describe("supplier item mappings", () => {
  it("sets, reads and deletes a mapping", async () => {
    const { calls, transport } = recorder(
      {
        supplierId: "sup",
        columns: { code: "Art", keywords: ["a", "b"] },
        defaults: { currency: "EUR" },
      },
      { supplierId: "sup", columns: "none", defaults: null },
      null,
      true,
    );

    const catalog = createCatalog({ transport });

    const saved = await catalog
      .setSupplierItemMapping({
        organizationId: "o",
        supplierId: "sup",
        input: {
          columns: { code: "Art", keywords: ["a", "b"] },
          defaults: { currency: "EUR" },
        },
      })
      .orThrow();

    expect(saved).toEqual({
      supplierId: "sup",
      columns: { code: "Art", keywords: ["a", "b"] },
      defaults: { currency: "EUR" },
    });
    expect(calls[0]?.args["defaults"]).toEqual({ currency: "EUR" });

    const sparse = await catalog
      .supplierItemMapping({ organizationId: "o", supplierId: "sup" })
      .orThrow();

    expect(sparse).toEqual({ supplierId: "sup", columns: {}, defaults: {} });

    await expect(
      catalog
        .supplierItemMapping({ organizationId: "o", supplierId: "none" })
        .orThrow(),
    ).resolves.toBeNull();

    await expect(
      catalog
        .deleteSupplierItemMapping({ organizationId: "o", supplierId: "sup" })
        .orThrow(),
    ).resolves.toBe(true);
  });

  it("defaults the mapping defaults to an empty object", async () => {
    const { calls, transport } = recorder({
      supplierId: "sup",
      columns: {},
      defaults: {},
    });

    await createCatalog({ transport })
      .setSupplierItemMapping({
        organizationId: "o",
        supplierId: "sup",
        input: { columns: { code: "Art" } },
      })
      .orThrow();

    expect(calls[0]?.args["defaults"]).toEqual({});
  });

  it("maps a price list row and sets a trade code", async () => {
    const { calls, transport } = recorder(
      {
        code: "C1",
        description: "Bolt",
        price: "1250",
        currency: "EUR",
        unit: "pc",
        keywords: "steel",
      },
      {},
      true,
    );

    const catalog = createCatalog({ transport });

    const mapped = await catalog
      .mapSupplierRow({
        organizationId: "o",
        supplierId: "sup",
        row: { Art: "C1" },
      })
      .orThrow();

    expect(mapped).toEqual({
      code: "C1",
      description: "Bolt",
      price: 1250n,
      currency: "EUR",
      unit: "pc",
      keywords: "steel",
    });
    expect(calls[0]?.args["source"]).toEqual({ Art: "C1" });

    const empty = await catalog
      .mapSupplierRow({ organizationId: "o", supplierId: "sup", row: {} })
      .orThrow();

    expect(empty).toEqual({
      code: null,
      description: null,
      price: null,
      currency: null,
      unit: null,
      keywords: null,
    });

    await expect(
      catalog
        .setVariantTradeCode({ variantId: "v1", tradeCode: null })
        .orThrow(),
    ).resolves.toBe(true);
    expect(calls[2]?.args).toEqual({ variant: "v1", trade_code: null });
  });
});
