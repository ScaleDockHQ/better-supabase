import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { StripeClient } from "../../src/blocks/billing/index.ts";

import { createBilling, sqlTransport } from "../../src/blocks/billing/index.ts";
import { EventHub } from "../../src/core/events.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("billing", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("links customers, syncs seats and handles Stripe events", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "billing", "entitlements"], {
        modules: { billing: { options: { seatRoles: ["owner", "member"] } } },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });
      await s.service();
      // The Stripe Sync Engine's tables, when the local stack has none.
      if (
        !(await s.value<boolean>(
          "to_regclass('stripe.subscription_items') is not null",
        ))
      ) {
        await s.rows(`create schema if not exists stripe;
          create table stripe.subscriptions (id text primary key, customer text, status text, created bigint);
          create table stripe.subscription_items (id text primary key, subscription text, price text, quantity integer, created bigint)`);
      }

      const calls: [string, unknown][] = [];
      const stripe = {
        customers: {
          create: async (params: unknown) => {
            calls.push(["customers.create", params]);
            return { id: "cus_test1" };
          },
        },
        checkout: {
          sessions: {
            create: async (params: unknown) => {
              calls.push(["checkout.create", params]);
              return { id: "cs_1", url: "https://checkout.stripe.com/c/cs_1" };
            },
          },
        },
        subscriptionItems: {
          update: async (id: string, params: unknown, options: unknown) => {
            calls.push(["items.update", { id, params, options }]);
            return { id };
          },
        },
      } as unknown as StripeClient;
      const events = new EventHub();
      const seen: string[] = [];
      events.on("block", (event) => seen.push(event.type));
      const billing = createBilling({
        stripe,
        transport: sqlTransport(s.sql),
        events,
      });

      const session = await billing
        .checkout(organization, {
          price: "price_seat",
          quantity: "seats",
          successUrl: "https://app.test/billing",
        })
        .orThrow();
      expect(session).toEqual({
        id: "cs_1",
        url: "https://checkout.stripe.com/c/cs_1",
      });
      expect(calls[1]).toMatchObject([
        "checkout.create",
        {
          customer: "cus_test1",
          line_items: [{ price: "price_seat", quantity: 2 }],
          metadata: { organization_id: organization },
        },
      ]);
      expect(await billing.customer(organization).orThrow()).toBe("cus_test1");
      // A second checkout reuses the customer.
      await billing
        .checkout(organization, {
          price: "price_seat",
          successUrl: "https://app.test",
        })
        .orThrow();
      expect(
        calls.filter(([name]) => name === "customers.create"),
      ).toHaveLength(1);
      // The entitlements module now reads billing_customers.
      expect(
        await s.value(
          `better_supabase.tenant_stripe_customer('${organization}')`,
        ),
      ).toBe("cus_test1");

      await s.rows(`insert into stripe.subscriptions (id, customer, status, created) values ('sub_1', 'cus_test1', 'active', 1);
        insert into stripe.subscription_items (id, subscription, price, quantity, created) values ('si_1', 'sub_1', 'price_seat', 1, 1)`);
      expect(
        await billing.syncSeats(organization, { key: "evt" }).orThrow(),
      ).toEqual({
        quantity: 2,
        previousQuantity: 1,
        changed: true,
      });
      expect(calls.at(-1)).toEqual([
        "items.update",
        {
          id: "si_1",
          params: { quantity: 2, proration_behavior: "create_prorations" },
          options: { idempotencyKey: "seats:si_1:1:2:evt" },
        },
      ]);
      const status = await billing.status(organization).orThrow();
      expect(status).toMatchObject({
        customerId: "cus_test1",
        seats: 2,
        subscription: { itemId: "si_1", quantity: 1, status: "active" },
      });

      const outcome = await billing
        .handleStripeEvent({
          id: "evt_1",
          type: "customer.subscription.updated",
          data: {
            object: { id: "sub_1", customer: "cus_test1", status: "past_due" },
          },
        })
        .orThrow();
      expect(outcome).toMatchObject({
        event: "billing.subscription_updated",
        organizationId: organization,
      });
      expect(seen).toEqual([
        "billing.customer_linked",
        "billing.seats_synced",
        "billing.subscription_updated",
      ]);

      // Members without billing.read cannot read the status.
      await s.asRole(member);
      expect(await billing.status(organization)).toMatchObject({
        ok: false,
        error: { hint: "BILLING_FORBIDDEN" },
      });
    } finally {
      await s.close();
    }
  });
});
