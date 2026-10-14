import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

interface Applied {
  readonly promotionId: string;
  readonly name: string;
  readonly kind: string;
  readonly code: string | null;
  readonly amount: string;
}

interface Totals {
  readonly subtotal: string;
  readonly discountTotal: string;
  readonly shippingTotal: string;
  readonly total: string;
  readonly lines: readonly {
    readonly id: string;
    readonly sku: string;
    readonly discount: string;
    readonly total: string;
  }[];
  readonly promotions: readonly Applied[];
  readonly problems: readonly Record<string, unknown>[];
}

const ADDRESS = { country: "NL", city: "Amsterdam", line1: "Dam 1" };

/** Each line's sku, discount and total, by sku. */
const discounts = (totals: Totals): string[][] =>
  totals.lines
    .map((line) => [line.sku, line.discount, line.total])
    .toSorted(([a = ""], [b = ""]) => a.localeCompare(b));

describe.skipIf(!live)("promotions module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let shopper: TestUser;
  let other: TestUser;
  let tenant: string;
  let tee: { product: string; variant: string };
  let mug: { product: string; variant: string };
  let rate: string;

  const call = <T>(sql: string, params: unknown[] = []): Promise<T> =>
    session.value<T>(sql, params);

  const item = async (
    sku: string,
    amount: string,
  ): Promise<{ product: string; variant: string }> => {
    const product = await call<{ id: string }>(
      "better_supabase.save_product($1, null, $2, null, null, 'physical')",
      [tenant, sku],
    );
    await call("better_supabase.set_product_status($1, 'active')", [
      product.id,
    ]);
    const variant = await call<{ id: string }>(
      "better_supabase.save_variant($1, null, $2, '{}'::uuid[], null, null, 500, false, false)",
      [product.id, sku],
    );
    await call(
      "better_supabase.set_price($1, 'EUR', $2, null, null, null, null)",
      [variant.id, amount],
    );
    return { product: product.id, variant: variant.id };
  };

  const promotion = async (data: Record<string, unknown>): Promise<string> => {
    await session.as(owner);
    return (
      await call<{ id: string }>(
        "better_supabase.save_promotion($1, null, $2)",
        [tenant, JSON.stringify(data)],
      )
    ).id;
  };

  const codes = async (
    promotionId: string,
    list: readonly string[],
    usageLimit: number | null = null,
  ): Promise<void> => {
    await session.as(owner);
    await call(
      "better_supabase.create_promotion_codes($1, $2, null, null, $3)",
      [promotionId, list, usageLimit],
    );
  };

  /** A fresh open cart for `user` with two tees and a mug (5000 EUR). */
  const cart = async (user: TestUser, email = user.email): Promise<string> => {
    await session.as(user);
    const created = await call<{ id: string }>(
      "better_supabase.create_cart($1, 'EUR', null, $2)",
      [tenant, email],
    );
    await session.client.query(
      "delete from better_supabase.cart_promotion_codes where cart_id = $1",
      [created.id],
    );
    await call("better_supabase.set_cart_line($1, $2, 2)", [
      created.id,
      tee.variant,
    ]);
    await call("better_supabase.set_cart_line($1, $2, 1)", [
      created.id,
      mug.variant,
    ]);
    await call("better_supabase.set_cart_details($1, $2, $3, $3)", [
      created.id,
      email,
      JSON.stringify(ADDRESS),
    ]);
    await call("better_supabase.set_cart_shipping_rate($1, $2)", [
      created.id,
      rate,
    ]);
    return created.id;
  };

  const price = (cartId: string): Promise<Totals> =>
    call<Totals>("better_supabase.price_cart($1)", [cartId]);

  const apply = (cartId: string, code: string): Promise<unknown> =>
    call("better_supabase.apply_promotion_code($1, $2)", [cartId, code]);

  const place = async (cartId: string): Promise<{ id: string }> => {
    await session.service();
    return call<{ id: string }>(
      "better_supabase.place_order($1, null, null, null)",
      [cartId],
    );
  };

  /** Pauses every promotion so a test sees only the ones it creates. */
  const reset = async (): Promise<void> => {
    await session.client.query(
      "update better_supabase.promotions set active = false where tenant_id = $1",
      [tenant],
    );
  };

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install([
      "organizations",
      "catalog",
      "outbox",
      "orders",
      "promotions",
    ]);
    owner = await session.user("promotions-owner");
    member = await session.user("promotions-member");
    shopper = await session.user("promotions-shopper");
    other = await session.user("promotions-other");
    tenant = await session.organization(owner, { member });
    await session.as(owner);
    tee = await item("PTEE", "2000");
    mug = await item("PMUG", "1000");
    rate = (
      await call<{ id: string }>(
        "better_supabase.save_shipping_rate($1, null, $2)",
        [
          tenant,
          JSON.stringify({
            name: "Standard",
            countries: ["NL"],
            currency: "EUR",
            kind: "flat",
            amount: "495",
          }),
        ],
      )
    ).id;
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("stacks an automatic percentage under a fixed code by priority", async () => {
    await reset();
    await promotion({
      name: "Autumn 10%",
      kind: "percentage",
      percent: "10",
      automatic: true,
      stackable: true,
    });
    const fixed = await promotion({
      name: "5 off",
      kind: "fixed",
      currency: "EUR",
      amount: "500",
      minSubtotal: "3000",
      stackable: true,
      priority: 10,
    });
    await codes(fixed, ["save5"]);
    const id = await cart(shopper);
    expect(await apply(id, " Save5 ")).toMatchObject({ code: "SAVE5" });
    const totals = await price(id);
    expect(totals).toMatchObject({
      subtotal: "5000",
      discountTotal: "950",
      shippingTotal: "495",
      total: "4545",
      problems: [],
    });
    expect(
      totals.promotions.map((entry) => [entry.name, entry.amount]),
    ).toEqual([
      ["5 off", "500"],
      ["Autumn 10%", "450"],
    ]);
    expect(discounts(totals)).toEqual([
      ["PMUG", "190", "810"],
      ["PTEE", "760", "3240"],
    ]);
  });

  it("keeps a non-stackable promotion alone and reports the code that loses", async () => {
    await reset();
    const best = await promotion({
      name: "VIP 20%",
      kind: "percentage",
      percent: "20",
      priority: 5,
    });
    const weaker = await promotion({
      name: "Welcome 5%",
      kind: "percentage",
      percent: "5",
    });
    await promotion({
      name: "Auto 1%",
      kind: "percentage",
      percent: "1",
      automatic: true,
      stackable: true,
    });
    await codes(best, ["VIP"]);
    await codes(weaker, ["WELCOME"]);
    const id = await cart(shopper);
    await apply(id, "VIP");
    await apply(id, "WELCOME");
    const totals = await price(id);
    expect(totals.discountTotal).toBe("1000");
    expect(totals.promotions.map((entry) => entry.code)).toEqual(["VIP"]);
    expect(totals.problems).toEqual([
      {
        problem: "promotion_unavailable",
        promotionId: weaker,
        code: "WELCOME",
        reason: "not_combinable",
      },
    ]);
    expect(
      await session.hint("better_supabase.place_order($1, null, null, null)", [
        id,
      ]),
    ).toBe("ORDERS_FORBIDDEN");
    await session.service();
    expect(
      await session.hint("better_supabase.place_order($1, null, null, null)", [
        id,
      ]),
    ).toBe("ORDERS_CART_INVALID");
    await session.as(shopper);
    expect(
      await call("better_supabase.remove_promotion_code($1, 'welcome')", [id]),
    ).toBe(true);
    expect((await price(id)).problems).toEqual([]);
  });

  it("scopes discounts to products, categories with their children, and collections", async () => {
    await reset();
    await session.as(owner);
    const apparel = await call<{ id: string }>(
      "better_supabase.save_category($1, null, null, 'Apparel', null, null)",
      [tenant],
    );
    const tees = await call<{ id: string }>(
      "better_supabase.save_category($1, null, $2, 'Tees', null, null)",
      [tenant, apparel.id],
    );
    await call("better_supabase.set_product_categories($1, $2)", [
      tee.product,
      [tees.id],
    ]);
    const kitchen = await call<{ id: string }>(
      "better_supabase.save_collection($1, null, 'Kitchen', null, 'manual', null)",
      [tenant],
    );
    await call("better_supabase.add_to_collection($1, $2, null)", [
      kitchen.id,
      mug.product,
    ]);
    const byCategory = await promotion({
      name: "Apparel 50%",
      kind: "percentage",
      percent: "50",
      scope: "categories",
      targets: [apparel.id],
      automatic: true,
      stackable: true,
    });
    await promotion({
      name: "Kitchen 1 off",
      kind: "fixed",
      currency: "EUR",
      amount: "100",
      scope: "collections",
      targets: [kitchen.id],
      automatic: true,
      stackable: true,
    });
    const id = await cart(shopper);
    const totals = await price(id);
    expect(discounts(totals)).toEqual([
      ["PMUG", "100", "900"],
      ["PTEE", "2000", "2000"],
    ]);
    await session.as(owner);
    await call("better_supabase.save_promotion($1, $2, $3)", [
      tenant,
      byCategory,
      JSON.stringify({
        name: "Mug only",
        kind: "percentage",
        percent: "12.5",
        scope: "products",
        targets: [mug.product],
        automatic: true,
        stackable: true,
        priority: 1,
      }),
    ]);
    expect(discounts(await price(id))).toEqual([
      ["PMUG", "225", "775"],
      ["PTEE", "0", "4000"],
    ]);
    expect(
      await session.value("better_supabase.round_half_even($1)", ["90.5"]),
    ).toBe("90");
    expect(
      await session.value("better_supabase.round_half_even($1)", ["91.5"]),
    ).toBe("92");
  });

  it("frees shipping and reports a minimum the cart doesn't reach", async () => {
    await reset();
    const free = await promotion({
      name: "Free shipping",
      kind: "free_shipping",
      currency: "EUR",
      minSubtotal: "4000",
    });
    await codes(free, ["SHIPFREE"]);
    const id = await cart(shopper);
    await apply(id, "SHIPFREE");
    expect(await price(id)).toMatchObject({
      shippingTotal: "0",
      total: "5000",
      promotions: [{ kind: "free_shipping", amount: "0" }],
    });
    await session.as(shopper);
    await call("better_supabase.set_cart_line($1, $2, 1)", [id, tee.variant]);
    expect((await price(id)).problems).toEqual([
      {
        problem: "promotion_unavailable",
        promotionId: free,
        code: "SHIPFREE",
        reason: "min_subtotal",
      },
    ]);
  });

  it("redeems inside checkout, enforces limits and releases on cancel", async () => {
    await reset();
    const once = await promotion({
      name: "One per customer",
      kind: "fixed",
      currency: "EUR",
      amount: "1000",
      perCustomerLimit: 1,
      stackable: true,
    });
    await codes(once, ["ONCE"]);
    await codes(once, ["SINGLE"], 1);
    const first = await cart(shopper);
    await apply(first, "SINGLE");
    expect((await price(first)).discountTotal).toBe("1000");
    const order = await place(first);
    const redemptions = await session.rows<{
      status: string;
      amount: string;
      customer_id: string;
    }>(
      "select status, amount::text, customer_id from better_supabase.promotion_redemptions where order_id = $1",
      [order.id],
    );
    expect(redemptions).toEqual([
      { status: "redeemed", amount: "1000", customer_id: shopper.id },
    ]);
    const events = await session.rows<{ data: Record<string, unknown> }>(
      "select payload as data from better_supabase.outbox_events where organization_id = $1 and type = 'promotion.redeemed'",
      [tenant],
    );
    expect(events.at(-1)?.data).toMatchObject({
      promotionId: once,
      code: "SINGLE",
      orderId: order.id,
      currency: "EUR",
      amount: "1000",
    });

    const second = await cart(shopper);
    await session.as(shopper);
    expect(
      await session.hint("better_supabase.apply_promotion_code($1, 'SINGLE')", [
        second,
      ]),
    ).toBe("PROMOTIONS_LIMIT_REACHED");
    await apply(second, "ONCE");
    expect((await price(second)).problems).toMatchObject([
      { code: "ONCE", reason: "limit_reached" },
    ]);
    const anonymous = await cart(other, shopper.email);
    await apply(anonymous, "ONCE");
    expect((await price(anonymous)).problems).toMatchObject([
      { code: "ONCE", reason: "limit_reached" },
    ]);

    await session.as(owner);
    await call("better_supabase.cancel_order($1, 'changed mind')", [order.id]);
    expect(
      await session.value(
        "(select status from better_supabase.promotion_redemptions where order_id = $1)",
        [order.id],
      ),
    ).toBe("released");
    await session.as(shopper);
    expect((await price(second)).problems).toEqual([]);
    await apply(second, "SINGLE");
    expect(
      await session.value(
        "(select redemptions from better_supabase.promotions where id = $1)",
        [once],
      ),
    ).toBe(0);
  });

  it("moves a cart's codes when carts merge", async () => {
    await reset();
    const welcome = await promotion({
      name: "Welcome",
      kind: "percentage",
      percent: "10",
    });
    await codes(welcome, ["MERGE10"]);
    const anonymous = await cart(other, "merge@example.test");
    await apply(anonymous, "MERGE10");
    const target = await cart(shopper);
    await session.service();
    expect(
      await call("better_supabase.merge_carts($1, $2)", [other.id, shopper.id]),
    ).toBe(1);
    await session.as(shopper);
    expect(await price(target)).toMatchObject({
      discountTotal: "1000",
      promotions: [{ code: "MERGE10" }],
    });
  });

  it("checks who manages promotions and what they save", async () => {
    await reset();
    await session.as(member);
    expect(
      await session.hint("better_supabase.save_promotion($1, null, $2)", [
        tenant,
        JSON.stringify({ name: "x", kind: "percentage", percent: "5" }),
      ]),
    ).toBe("PROMOTIONS_FORBIDDEN");
    await session.as(owner);
    const invalid = async (data: Record<string, unknown>): Promise<string> =>
      session.hint("better_supabase.save_promotion($1, null, $2)", [
        tenant,
        JSON.stringify(data),
      ]);
    for (const data of [
      { name: "x", kind: "bogus" },
      { name: "x", kind: "percentage", percent: "150" },
      { name: "x", kind: "fixed", amount: "100" },
      { name: "x", kind: "fixed", currency: "EUR", amount: "0" },
      { name: "x", kind: "free_shipping", scope: "products" },
      { name: "x", kind: "free_shipping", scope: "products", targets: [rate] },
      {
        name: "x",
        kind: "free_shipping",
        startsAt: "2026-02-01T00:00:00Z",
        endsAt: "2026-01-01T00:00:00Z",
      },
      { name: "x", kind: "free_shipping", usageLimit: 0 },
    ])
      expect(await invalid(data)).toBe("PROMOTIONS_INVALID");

    const ended = await promotion({
      name: "Ended",
      kind: "percentage",
      percent: "5",
      endsAt: "2026-01-01T00:00:00Z",
      startsAt: "2025-12-01T00:00:00Z",
    });
    await codes(ended, ["ENDED"]);
    const generated = await call<{ code: string }[]>(
      "better_supabase.create_promotion_codes($1, null, 3, 'bf-', null)",
      [ended],
    );
    expect(generated).toHaveLength(3);
    for (const entry of generated)
      expect(entry.code).toMatch(/^BF-[A-HJ-NP-Z2-9]{8}$/);
    expect(
      await session.hint(
        "better_supabase.create_promotion_codes($1, $2, null, null, null)",
        [ended, ["ENDED"]],
      ),
    ).toBe("PROMOTIONS_CODE_TAKEN");
    expect(
      await session.hint(
        "better_supabase.create_promotion_codes($1, $2, null, null, null)",
        [ended, ["a"]],
      ),
    ).toBe("PROMOTIONS_CODE_FORMAT");
    const id = await cart(shopper);
    expect(
      await session.hint("better_supabase.apply_promotion_code($1, 'ENDED')", [
        id,
      ]),
    ).toBe("PROMOTIONS_CODE_INVALID");
    await session.as(other);
    expect(
      await session.hint("better_supabase.apply_promotion_code($1, 'ENDED')", [
        id,
      ]),
    ).toBe("ORDERS_CART_NOT_FOUND");

    await session.as(owner);
    expect(
      await call("better_supabase.delete_promotion_code($1)", [
        (
          await session.rows<{ id: string }>(
            "select id from better_supabase.promotion_codes where code = 'ENDED' and tenant_id = $1",
            [tenant],
          )
        )[0]?.id,
      ]),
    ).toBe(true);
    expect(
      await call("better_supabase.set_promotion_active($1, false)", [ended]),
    ).toBe(true);
    expect(await call("better_supabase.delete_promotion($1)", [ended])).toBe(
      true,
    );
    const used = await session.rows<{ promotion_id: string }>(
      "select promotion_id from better_supabase.promotion_redemptions where tenant_id = $1 limit 1",
      [tenant],
    );
    expect(
      await session.hint("better_supabase.delete_promotion($1)", [
        used[0]?.promotion_id,
      ]),
    ).toBe("PROMOTIONS_IN_USE");

    await session.asRole(shopper);
    expect(
      await session.rows("select id from better_supabase.promotions", []),
    ).toEqual([]);
    expect(
      (
        await session.rows(
          "select id from better_supabase.promotion_redemptions",
          [],
        )
      ).length,
    ).toBeGreaterThan(0);
    await session.as(owner);
  });
});
