import { AsyncResult, type StandardSchemaV1 } from "better-supabase";
import { createBlocks, sqlTransport } from "better-supabase/blocks";
import { createApprovals } from "better-supabase/blocks/approvals";
import { createCatalog } from "better-supabase/blocks/catalog";
import {
  fixedRates,
  money,
  type Payment,
  type PaymentProvider,
} from "better-supabase/blocks/commerce";
import {
  createImports,
  defineImport,
  runImport,
} from "better-supabase/blocks/imports";
import { createInventory } from "better-supabase/blocks/inventory";
import { createMetrics } from "better-supabase/blocks/metrics";
import { createOrders } from "better-supabase/blocks/orders";
import { createPromotions } from "better-supabase/blocks/promotions";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { received, watching } from "./flow.ts";
import { commerce, commerceMetrics } from "./recipes.ts";
import { dbUrl, reachable, withRecipe } from "./stack.ts";

const live = await reachable();

const ADDRESS = { country: "NL", city: "Amsterdam", line1: "Dam 1" };

/** The commerce page's event mapping: the order's watchers hear it was paid and shipped. */
const ORDER_EVENTS = {
  "order.paid": "order.paid",
  "fulfillment.shipped": "order.shipped",
} as const;

const PRODUCTS = `Title,SKU,Price
Tee,TEE,2000
Mug,MUG,1250
`;

interface ProductRow {
  readonly title: string;
  readonly sku: string;
  readonly price: string;
}

const productRow: StandardSchemaV1<unknown, ProductRow> = {
  "~standard": {
    version: 1,
    vendor: "validation-recipes",
    validate: (value) => {
      // SAFETY: dryRun hands each mapped row over as a record of strings.
      const row = value as Partial<ProductRow>;
      return row.title && row.sku && row.price && /^\d+$/.test(row.price)
        ? { value: { title: row.title, sku: row.sku, price: row.price } }
        : { issues: [{ message: "title, sku and a price in cents" }] };
    },
  },
};

/** A payment provider that settles at once, one payment per idempotency key. */
function fakePayments(): PaymentProvider {
  const byKey = new Map<string, Payment>();
  let refunds = 0;
  return {
    apiVersion: 1,
    name: "fake",
    createPayment(input, options) {
      const key = options?.idempotencyKey ?? "";
      const payment: Payment = byKey.get(key) ?? {
        id: `pi_${String(byKey.size + 1)}`,
        provider: "fake",
        status: "succeeded",
        amount: input.amount,
        captured: input.amount,
        refunded: money(0, input.amount.currency),
        reference: input.reference,
        clientSecret: "secret",
        metadata: input.metadata ?? {},
      };
      byKey.set(key, payment);
      return AsyncResult.ok(payment);
    },
    capture: (paymentId) => AsyncResult.ok(byKey.get(paymentId)!),
    refund: (paymentId, input) =>
      AsyncResult.ok({
        id: `re_${String((refunds += 1))}`,
        paymentId,
        amount: input?.amount ?? money(0, "EUR"),
        status: "succeeded",
      }),
    parseWebhook: () => AsyncResult.ok([]),
  };
}

describe.skipIf(!live)("commerce recipe", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  afterAll(() => pool.end());

  it("sells to an anonymous shopper who signs in, with a code, then ships", async () => {
    await withRecipe(pool, commerce, async (s) => {
      const owner = await s.user("owner");
      const member = await s.user("member");
      const shopper = await s.user("shopper");
      const finance = await s.user("finance");
      const visitor = await s.anonymousUser();
      const organizationId = await s.organization(owner, [member]);

      const transport = sqlTransport(s.sql);
      const service = sqlTransport(s.serviceSql);
      const catalog = createCatalog({ transport });
      const inventory = createInventory({ transport });
      const imports = createImports({ transport });
      const promotions = createPromotions({ transport });
      const orders = createOrders({
        transport,
        service,
        payments: fakePayments(),
        tax: fixedRates({ rates: { NL: { standard: "0.21" } } }),
      });

      // The catalog arrives as a CSV; each batch goes through the catalog block.
      const variants = new Map<string, string>();
      const products = defineImport<ProductRow>({
        kind: "products",
        columns: productRow,
        key: (row) => row.sku,
        async insert(batch, { organizationId: tenant }) {
          for (const row of batch) {
            const product = await catalog
              .createProduct(tenant, { title: row.title })
              .orThrow();
            await catalog.setProductStatus(product.id, "active").orThrow();
            const variant = await catalog
              .createVariant(product.id, { sku: row.sku })
              .orThrow();
            await catalog
              .setPrice(variant.id, { amount: money(BigInt(row.price), "EUR") })
              .orThrow();
            variants.set(row.sku, variant.id);
          }
        },
      });
      await s.as(owner);
      const imported = await runImport(
        products,
        PRODUCTS,
        { Title: "title", SKU: "sku", Price: "price" },
        {
          organizationId,
          start: async () =>
            (await imports.start(organizationId, "products").orThrow()).id,
          finish: async (id, status, count, error) => {
            await s.serviceSql.queryRaw(
              "select better_supabase.finish_import($1, $2, $3, $4)",
              [id, status, count, error],
            );
          },
        },
      );
      expect(imported).toMatchObject({ status: "completed", imported: 2 });
      const tee = { id: variants.get("TEE")! };

      const warehouse = await inventory
        .saveLocation(organizationId, { code: "WH", name: "Warehouse" })
        .orThrow();
      await inventory
        .adjustStock(tee.id, warehouse.id, 10, "receipt")
        .orThrow();
      const rate = await orders
        .saveShippingRate(organizationId, {
          name: "Standard",
          countries: ["NL"],
          amount: money(495, "EUR"),
        })
        .orThrow();
      const welcome = await promotions
        .savePromotion(organizationId, {
          name: "Welcome",
          discount: { kind: "percentage", percent: "10" },
        })
        .orThrow();
      await promotions
        .createCodes(welcome.id, { codes: ["WELCOME10"] })
        .orThrow();

      // The shopper left a tee in a cart on another device.
      await s.as(shopper);
      const saved = await orders
        .createCart(organizationId, {
          currency: "EUR",
          email: shopper.email,
        })
        .orThrow();
      await orders.addToCart(saved.id, tee.id, 1).orThrow();

      await s.as(visitor);
      const browsing = await orders
        .createCart(organizationId, { currency: "EUR" })
        .orThrow();
      await orders.addToCart(browsing.id, tee.id, 2).orThrow();
      await promotions.applyCode(browsing.id, "welcome10").orThrow();

      // Signing in: the callback route merges the carts with the service role.
      expect(await orders.mergeCarts(visitor.id, shopper.id).orThrow()).toBe(1);

      await s.as(shopper);
      await orders
        .setCartDetails(saved.id, {
          shippingAddress: ADDRESS,
          billingAddress: ADDRESS,
        })
        .orThrow();
      await orders.setShippingRate(saved.id, rate.id).orThrow();
      const priced = await orders.priceCart(saved.id).orThrow();
      expect(priced.subtotal).toEqual(money(6000, "EUR"));
      expect(priced.discountTotal).toEqual(money(600, "EUR"));
      expect(priced.promotions).toMatchObject([{ code: "WELCOME10" }]);

      const watchers = await watching(s, ORDER_EVENTS);
      await s.as(shopper);
      const { order } = await orders.checkout(saved.id).orThrow();
      expect(order.status).toBe("paid");
      expect(order.number).toBe("SO-0001");
      expect(order.invoiceNumber).toMatch(/^INV-\d{4}-00001$/);
      expect(order.discountTotal).toEqual(money(600, "EUR"));

      await s.client.query("reset role");
      expect(
        await s.rows(
          "select on_hand, reserved from better_supabase.stock_levels where variant_id = $1",
          [tee.id],
        ),
      ).toEqual([{ on_hand: 7, reserved: 0 }]);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.promotion_redemptions where order_id = $1)",
          [order.id],
        ),
      ).toBe(1);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.outbox_events where type = 'promotion.redeemed')",
        ),
      ).toBe(1);

      await s.watch(member, organizationId, "order", order.id);
      await s.as(owner);
      const fulfillment = await orders.createFulfillment(order.id).orThrow();
      await orders
        .shipFulfillment(fulfillment.id, { carrier: "PostNL" })
        .orThrow();

      await watchers.relay();
      expect(await received(s, member, order.id)).toEqual([
        "order.paid",
        "order.shipped",
      ]);

      // The metrics sink rolls up the order's day when order.paid is relayed.
      const app = createBlocks(
        {
          transport,
          service,
          metricEvents: {
            "order.paid": ["revenue", "average_order_value", "units_sold"],
          },
        },
        {
          metrics: (options) =>
            createMetrics({ ...options, metrics: commerceMetrics }),
        },
      );
      await watchers.send(app.sinks.metrics!);
      await s.as(owner);
      const now = Temporal.Now.instant();
      const today = {
        from: now.subtract({ hours: 48 }),
        until: now.add({ hours: 48 }),
      };
      const kpi = async (key: (typeof commerceMetrics)[number]["key"]) =>
        (await app.metrics.kpi(key, today, { organizationId }).orThrow()).value;
      expect(await kpi("revenue")).toBe(Number(order.total.amount));
      expect(await kpi("average_order_value")).toBe(Number(order.total.amount));
      expect(await kpi("units_sold")).toBe(3);

      // A refund above 50.00 needs an admin to approve a refund request first.
      await s.service();
      await s.client.query(
        "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'admin')",
        [organizationId, finance.id],
      );
      const approvals = createApprovals({ transport });
      await s.as(owner);
      const small = await orders
        .refund(order.id, { amount: money(1000, "EUR") })
        .orThrow();
      expect(small.status).toBe("succeeded");
      const blocked = await orders.refund(order.id);
      expect(blocked.ok ? undefined : blocked.error.hint).toBe(
        "REFUND_APPROVAL_REQUIRED",
      );
      const request = await approvals
        .request({
          organizationId,
          subjectType: "order",
          subjectId: order.id,
          action: "refund",
          reason: "Damaged in transit",
        })
        .orThrow();
      await s.as(finance);
      await approvals.approve(request.id).orThrow();
      await s.as(owner);
      const rest = await orders.refund(order.id).orThrow();
      expect(rest.amount.amount).toBe(order.total.amount - 1000n);
    });
  }, 30_000);
});
