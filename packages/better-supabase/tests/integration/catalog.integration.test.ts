import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
  modules: { catalog: { options: { storefront: "public" } } },
};

interface Saved {
  readonly id: string;
  readonly slug?: string;
  readonly status?: string;
  readonly rank?: string;
}

describe.skipIf(!live)("catalog module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let tenant: string;
  let other: string;

  const call = <T>(sql: string, params: unknown[] = []): Promise<T> =>
    session.value<T>(sql, params);

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(["organizations", "catalog", "outbox"], layout);
    owner = await session.user("catalog-owner");
    member = await session.user("catalog-member");
    tenant = await session.organization(owner, { member });
    other = await session.organization(await session.user("catalog-other"));
    await session.as(owner);
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  const saveProduct = (title: string, slug: string | null = null) =>
    call<Saved>(
      "better_supabase.save_product($1, null, $2, $3, null, 'physical')",
      [tenant, title, slug],
    );

  it("creates products with a derived slug and refuses a taken one", async () => {
    await session.as(owner);
    const product = await saveProduct("Linen Shirt");
    expect(product).toMatchObject({ slug: "linen-shirt", status: "draft" });
    expect(
      await session.hint(
        "better_supabase.save_product($1, null, 'Other', 'linen-shirt', null, null)",
        [tenant],
      ),
    ).toBe("CATALOG_SLUG_TAKEN");

    const events = await session.rows<{ type: string }>(
      "select type from better_supabase.outbox_events where organization_id = $1 order by position",
      [tenant],
    );

    expect(events.map((event) => event.type)).toContain("product.created");
  });

  it("lets only catalog managers write", async () => {
    await session.as(member);
    expect(
      await session.hint(
        "better_supabase.save_product($1, null, 'Nope', null, null, null)",
        [tenant],
      ),
    ).toBe("CATALOG_FORBIDDEN");
    await session.as(owner);
  });

  it("builds variants from one value per option and refuses duplicates", async () => {
    await session.as(owner);
    const product = await saveProduct("Tee");

    const size = await call<{
      id: string;
      values: { id: string; value: string }[];
    }>(
      "better_supabase.save_product_option($1, null, 'Size', array['S', 'M'])",
      [product.id],
    );

    const color = await call<{
      id: string;
      values: { id: string; value: string }[];
    }>("better_supabase.save_product_option($1, null, 'Color', array['Red'])", [
      product.id,
    ]);

    const [small, medium] = size.values;
    const [red] = color.values;

    const variant = await call<Saved>(
      "better_supabase.save_variant($1, null, 'TEE-S-RED', $2::uuid[], null, null, null, null, null)",
      [product.id, [small!.id, red!.id]],
    );

    expect(variant.rank).toBe("V");
    expect(
      await session.hint(
        "better_supabase.save_variant($1, null, 'TEE-S-RED-2', $2::uuid[], null, null, null, null, null)",
        [product.id, [red!.id, small!.id]],
      ),
    ).toBe("CATALOG_VARIANT_DUPLICATE");
    expect(
      await session.hint(
        "better_supabase.save_variant($1, null, 'TEE-M', $2::uuid[], null, null, null, null, null)",
        [product.id, [medium!.id]],
      ),
    ).toBe("CATALOG_VARIANT_OPTIONS");
    expect(
      await session.hint(
        "better_supabase.save_variant($1, null, 'TEE-S-RED', $2::uuid[], null, null, null, null, null)",
        [product.id, [medium!.id, red!.id]],
      ),
    ).toBe("CATALOG_SKU_TAKEN");
    expect(
      await session.hint(
        "better_supabase.save_product_option($1, $2, 'Size', array['M'])",
        [product.id, size.id],
      ),
    ).toBe("no error");
    expect(
      await call<boolean>(
        "exists (select 1 from better_supabase.product_variants where id = $1)",
        [variant.id],
      ),
    ).toBe(false);
    expect(
      await session.hint(
        "better_supabase.save_product_option($1, null, 'Fit', array['Slim'])",
        [product.id],
      ),
    ).toBe("no error");
    expect(
      await session.hint(
        "better_supabase.save_variant($1, $2, null, $3::uuid[], null, null, null, null, null)",
        [product.id, variant.id, [small!.id, red!.id]],
      ),
    ).toBe("CATALOG_VARIANT_OPTIONS");
  });

  it("moves products through draft, active and archived", async () => {
    await session.as(owner);
    const product = await saveProduct("Status Hat");
    expect(
      await call<{ status: string; from: string }>(
        "better_supabase.set_product_status($1, 'active')",
        [product.id],
      ),
    ).toMatchObject({ status: "active", from: "draft" });
    await call("better_supabase.set_product_status($1, 'archived')", [
      product.id,
    ]);
    expect(
      await session.hint("better_supabase.set_product_status($1, 'active')", [
        product.id,
      ]),
    ).toBe("CATALOG_TRANSITION_INVALID");
  });

  describe("prices", () => {
    let variant: string;

    beforeAll(async () => {
      await session.as(owner);
      const product = await saveProduct("Priced Mug");
      variant = (
        await call<Saved>(
          "better_supabase.save_variant($1, null, 'MUG-1', null, null, null, 350, null, null)",
          [product.id],
        )
      ).id;
    });

    it("stores bigint minor units and emits price changes", async () => {
      await session.as(owner);

      const first = await call<{
        id: string;
        amount: string;
        previousAmount: string | null;
      }>(
        "better_supabase.set_price($1, 'EUR', '1299', null, null, null, null)",
        [variant],
      );

      expect(first).toMatchObject({ amount: "1299", previousAmount: null });

      const large = await call<{
        id: string;
        amount: string;
        previousAmount: string;
      }>(
        "better_supabase.set_price($1, 'EUR', '900719925474099300', null, null, null, null)",
        [variant],
      );

      expect(large).toMatchObject({
        id: first.id,
        amount: "900719925474099300",
        previousAmount: "1299",
      });

      const events = await session.rows<{ payload: Record<string, unknown> }>(
        "select payload from better_supabase.outbox_events where type = 'catalog.price_changed' and organization_id = $1 order by position",
        [tenant],
      );

      expect(events.at(-1)?.payload).toMatchObject({
        variantId: variant,
        currency: "EUR",
        amount: "900719925474099300",
        previousAmount: "1299",
      });
    });

    it("refuses unknown currencies, fractional amounts and overlapping windows", async () => {
      await session.as(owner);
      expect(
        await session.hint(
          "better_supabase.set_price($1, 'XYZ', '100', null, null, null, null)",
          [variant],
        ),
      ).toBe("CATALOG_CURRENCY_INVALID");
      expect(
        await session.hint(
          "better_supabase.set_price($1, 'USD', '1.50', null, null, null, null)",
          [variant],
        ),
      ).toBe("CATALOG_AMOUNT_INVALID");
      expect(
        await session.hint(
          "better_supabase.set_price($1, 'USD', '100', '90', null, null, null)",
          [variant],
        ),
      ).toBe("CATALOG_COMPARE_AT_INVALID");
      await call(
        "better_supabase.set_price($1, 'USD', '500', null, null, '2026-01-01', '2026-02-01')",
        [variant],
      );
      expect(
        await session.hint(
          "better_supabase.set_price($1, 'USD', '400', null, null, '2026-01-15', '2026-03-01')",
          [variant],
        ),
      ).toBe("CATALOG_PRICE_OVERLAP");
    });

    it("resolves a price list price before the base price", async () => {
      await session.as(owner);

      const list = await call<Saved>(
        "better_supabase.save_price_list($1, null, 'Wholesale', 'b2b')",
        [tenant],
      );

      await call(
        "better_supabase.set_price($1, 'GBP', '1000', null, null, null, null)",
        [variant],
      );
      await call(
        "better_supabase.set_price($1, 'GBP', '800', null, $2, null, null)",
        [variant, list.id],
      );
      expect(
        await call<{ amount: string }>(
          "better_supabase.variant_price($1, 'GBP', $2)",
          [variant, list.id],
        ),
      ).toMatchObject({ amount: "800", priceListId: list.id });
      expect(
        await call<{ amount: string }>(
          "better_supabase.variant_price($1, 'GBP')",
          [variant],
        ),
      ).toMatchObject({ amount: "1000", priceListId: null });
      expect(
        await call<{ amount: string } | null>(
          "better_supabase.variant_price($1, 'USD', null, '2026-01-10')",
          [variant],
        ),
      ).toMatchObject({ amount: "500" });
    });
  });

  it("keeps the category tree free of cycles", async () => {
    await session.as(owner);

    const apparel = await call<Saved>(
      "better_supabase.save_category($1, null, null, 'Apparel', null, null)",
      [tenant],
    );

    const shirts = await call<Saved>(
      "better_supabase.save_category($1, null, $2, 'Shirts', null, null)",
      [tenant, apparel.id],
    );

    expect(
      await session.hint("better_supabase.move_category($1, $2, 'V')", [
        apparel.id,
        shirts.id,
      ]),
    ).toBe("CATALOG_CATEGORY_CYCLE");
    expect(
      await session.hint("better_supabase.delete_category($1)", [apparel.id]),
    ).toBe("CATALOG_CATEGORY_HAS_CHILDREN");
    const product = await saveProduct("Oxford");
    expect(
      await call<boolean>(
        "better_supabase.set_product_categories($1, $2::uuid[])",
        [product.id, [shirts.id]],
      ),
    ).toBe(true);
  });

  it("ranks manual collections and stores rule collections as filter trees", async () => {
    await session.as(owner);

    const manual = await call<Saved>(
      "better_supabase.save_collection($1, null, 'Summer', null, 'manual', null)",
      [tenant],
    );

    const first = await saveProduct("Sandal");
    const second = await saveProduct("Sunhat");
    expect(
      await call<string>("better_supabase.add_to_collection($1, $2, null)", [
        manual.id,
        first.id,
      ]),
    ).toBe("V");
    expect(
      await call<string>("better_supabase.add_to_collection($1, $2, null)", [
        manual.id,
        second.id,
      ]),
    ).toBe("k");

    const rule = {
      id: "root",
      type: "group",
      combinator: "and",
      rules: [{ id: "r1", field: "kind", operator: "is", value: "physical" }],
    };

    const smart = await call<Saved>(
      "better_supabase.save_collection($1, null, 'Physical', null, 'rule', $2::jsonb)",
      [tenant, JSON.stringify(rule)],
    );

    expect(
      await session.hint("better_supabase.add_to_collection($1, $2, null)", [
        smart.id,
        first.id,
      ]),
    ).toBe("CATALOG_COLLECTION_RULE");
    expect(
      await session.hint(
        "better_supabase.save_collection($1, null, 'Broken', null, 'rule', '{\"type\": \"rule\"}'::jsonb)",
        [tenant],
      ),
    ).toBe("CATALOG_COLLECTION_RULE");
  });

  it("shows members the tenant's catalog through RLS", async () => {
    await session.asRole(owner);

    const own = await session.rows<{ id: string }>(
      "select id from better_supabase.products where tenant_id = $1",
      [tenant],
    );

    expect(own.length).toBeGreaterThan(0);
    await session.asRole(member);
    expect(
      await session.rows(
        "select id from better_supabase.products where tenant_id = $1",
        [tenant],
      ),
    ).toEqual([]);
    await session.as(owner);
  });

  it("serves active products of a published storefront to anon", async () => {
    await session.as(owner);
    const shown = await saveProduct("Public Lamp");
    await saveProduct("Hidden Lamp");

    const variant = await call<Saved>(
      "better_supabase.save_variant($1, null, 'LAMP-1', null, null, null, null, null, null)",
      [shown.id],
    );

    await call(
      "better_supabase.set_price($1, 'EUR', '4999', null, null, null, null)",
      [variant.id],
    );
    await call("better_supabase.set_product_status($1, 'active')", [shown.id]);
    await session.asRole("anon");
    expect(
      await session.rows(
        "select id from better_supabase.products where tenant_id = $1",
        [tenant],
      ),
    ).toEqual([]);
    await session.as(owner);
    expect(
      await call<boolean>("better_supabase.publish_storefront($1, true)", [
        tenant,
      ]),
    ).toBe(true);
    await session.asRole("anon");

    const visible = await session.rows<{ id: string }>(
      "select id from better_supabase.products where tenant_id = $1",
      [tenant],
    );

    expect(visible.map((row) => row.id)).toEqual([shown.id]);
    expect(
      await call<{ amount: string }>(
        "better_supabase.variant_price($1, 'EUR')",
        [variant.id],
      ),
    ).toMatchObject({ amount: "4999" });
    expect(
      await session.rows(
        "select id from better_supabase.products where tenant_id = $1",
        [other],
      ),
    ).toEqual([]);
    await session.as(owner);
  });
});
