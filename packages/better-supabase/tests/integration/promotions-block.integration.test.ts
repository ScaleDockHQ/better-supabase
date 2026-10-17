import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { createOrders } from "../../src/blocks/orders/index.ts";
import {
  createPromotions,
  sqlTransport,
} from "../../src/blocks/promotions/index.ts";
import { money } from "../../src/commerce/index.ts";
import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("promotions block in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let shopper: TestUser;
  let tenant: string;
  let tee: string;

  /** Runs each call in a savepoint, as `role`, so a raised error doesn't end the test's transaction. */
  const transport = (role: () => Promise<void>): BlockTransport => {
    const inner = sqlTransport(session.sql);

    return {
      async call(schema, fn, args) {
        await role();
        await session.client.query("savepoint block_call");

        try {
          const value = await inner.call(schema, fn, args);
          await session.client.query("release savepoint block_call");

          return value;
        } catch (cause) {
          await session.client.query("rollback to savepoint block_call");
          throw cause;
        }
      },
    };
  };

  const call = <T>(sql: string, params: unknown[] = []): Promise<T> =>
    session.value<T>(sql, params);

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(["organizations", "catalog", "orders", "promotions"]);
    owner = await session.user("promotions-block-owner");
    shopper = await session.user("promotions-block-shopper");
    tenant = await session.organization(owner);
    await session.as(owner);

    const product = await call<{ id: string }>(
      "better_supabase.save_product($1, null, 'Tee', null, null, 'physical')",
      [tenant],
    );

    await call("better_supabase.set_product_status($1, 'active')", [
      product.id,
    ]);
    tee = (
      await call<{ id: string }>(
        "better_supabase.save_variant($1, null, 'TEE', '{}'::uuid[], null, null, 200, false, false)",
        [product.id],
      )
    ).id;
    await call(
      "better_supabase.set_price($1, 'EUR', '2000', null, null, null, null)",
      [tee],
    );
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("creates a timed promotion with codes and prices it into a cart", async () => {
    const admin = createPromotions({
      transport: transport(() => session.as(owner)),
    });

    const { id } = await admin
      .savePromotion(tenant, {
        name: "Ten off",
        discount: { kind: "fixed", amount: money(1000, "EUR") },
        minSubtotal: money(3000, "EUR"),
        startsAt: Temporal.Now.instant().subtract({ hours: 1 }),
        endsAt: Temporal.Now.instant().add({ hours: 24 }),
        usageLimit: 10,
      })
      .orThrow();

    const codes = await admin
      .createCodes(id, { count: 2, prefix: "TEN-", usageLimit: 1 })
      .orThrow();

    expect(codes).toHaveLength(2);
    expect(
      await admin.createCodes(id, { codes: ["welcome10"] }).orThrow(),
    ).toMatchObject([{ code: "WELCOME10" }]);

    const asShopper = transport(() => session.as(shopper));
    const orders = createOrders({ transport: asShopper });
    const shop = createPromotions({ transport: asShopper });

    const cart = await orders
      .createCart(tenant, { currency: "EUR", email: shopper.email })
      .orThrow();

    await orders.setCartLine(cart.id, tee, 2).orThrow();
    expect(await shop.applyCode(cart.id, " welcome10 ").orThrow()).toEqual({
      codeId: expect.any(String),
      code: "WELCOME10",
      promotionId: id,
    });
    const priced = await orders.priceCart(cart.id).orThrow();
    expect(priced.discountTotal).toEqual(money(1000, "EUR"));
    expect(priced.promotions).toEqual([
      {
        promotionId: id,
        name: "Ten off",
        kind: "fixed",
        code: "WELCOME10",
        discount: money(1000, "EUR"),
        freeShipping: false,
      },
    ]);

    await orders.setCartLine(cart.id, tee, 1).orThrow();
    expect((await orders.priceCart(cart.id).orThrow()).problems).toEqual([
      {
        problem: "promotion_unavailable",
        promotionId: id,
        code: "WELCOME10",
        reason: "min_subtotal",
      },
    ]);
    expect(await shop.removeCode(cart.id, "WELCOME10").orThrow()).toBe(true);
    expect(await shop.applyCode(cart.id, "NOPE")).toMatchObject({
      ok: false,
      error: { hint: "PROMOTIONS_CODE_INVALID" },
    });
  });
});
