import { describe, expect, it } from "vitest";

import type {
  BlockTransport,
  StripeClient,
} from "../../../src/blocks/billing/index.ts";
import type { SqlClient } from "../../../src/postgres/executor.ts";

import { createBilling } from "../../../src/blocks/billing/index.ts";
import { EventHub } from "../../../src/core/events.ts";

type Answer = (fn: string, args: Record<string, unknown>) => unknown;

function setup(answer: Answer, stripeOverrides: Record<string, unknown> = {}) {
  const calls: [string, Record<string, unknown>][] = [];

  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      calls.push([fn, { ...args }]);

      return answer(fn, { ...args });
    },
  };

  const stripeCalls: [string, unknown, unknown?][] = [];

  const stripe = {
    customers: {
      create: async (params: unknown, options?: unknown) => {
        stripeCalls.push(["customers.create", params, options]);

        return { id: "cus_new" };
      },
    },
    checkout: {
      sessions: {
        create: async (params: unknown, options: unknown) => {
          stripeCalls.push(["checkout.create", { params, options }]);

          return { id: "cs_1", url: null };
        },
      },
    },
    billingPortal: {
      sessions: {
        create: async (params: unknown) => {
          stripeCalls.push(["portal.create", params]);

          return { id: "bps_1", url: "https://billing.stripe.com/p/1" };
        },
      },
    },
    subscriptionItems: {
      update: async (id: string, params: unknown, options: unknown) => {
        stripeCalls.push(["items.update", { id, params, options }]);

        return { id };
      },
    },
    ...stripeOverrides,
  } as unknown as StripeClient;

  const events = new EventHub();
  const seen: unknown[] = [];
  events.on("block", (event) =>
    seen.push({ type: event.type, data: event.data }),
  );

  return { transport, calls, stripe, stripeCalls, events, seen };
}

describe("createBilling", () => {
  it("creates a customer once and opens checkout and the portal", async () => {
    let linked: string | undefined;

    const t = setup((fn, args) => {
      if (fn === "billing_customer") {
        return linked ?? null;
      }

      if (fn === "link_billing_customer") {
        linked ??= String(args["customer"]);

        return linked;
      }

      return null;
    });

    const billing = createBilling({ ...t, schema: "app" });
    expect(
      await billing.portal({
        organizationId: "org",
        options: { returnUrl: "https://a" },
      }),
    ).toMatchObject({
      ok: false,
      error: { kind: "not_found", hint: "BILLING_NO_CUSTOMER" },
    });

    const session = await billing
      .checkout({
        organizationId: "org",
        options: {
          price: "price_1",
          mode: "payment",
          successUrl: "https://a/ok",
          cancelUrl: "https://a/no",
          email: "a@b.test",
          name: "Acme",
          idempotencyKey: "k1",
          params: { allow_promotion_codes: true },
        },
      })
      .orThrow();

    expect(session).toEqual({ id: "cs_1", url: undefined });
    expect(t.stripeCalls[0]).toEqual([
      "customers.create",
      { email: "a@b.test", name: "Acme", metadata: { organization_id: "org" } },
      { idempotencyKey: "customer:org" },
    ]);
    expect(t.stripeCalls[1]).toEqual([
      "checkout.create",
      {
        params: {
          customer: "cus_new",
          mode: "payment",
          client_reference_id: "org",
          line_items: [{ price: "price_1", quantity: 1 }],
          success_url: "https://a/ok",
          cancel_url: "https://a/no",
          metadata: { organization_id: "org" },
          allow_promotion_codes: true,
        },
        options: { idempotencyKey: "k1" },
      },
    ]);
    expect(
      await billing
        .portal({ organizationId: "org", options: { returnUrl: "https://a" } })
        .orThrow(),
    ).toEqual({ url: "https://billing.stripe.com/p/1" });
    expect(
      await billing.ensureCustomer({ organizationId: "org" }).orThrow(),
    ).toBe("cus_new");
    expect(
      t.stripeCalls.filter(([name]) => name === "customers.create"),
    ).toHaveLength(1);
  });

  it("merges checkout params deeply and keeps the tenant link", async () => {
    const t = setup((fn) => (fn === "billing_customer" ? "cus_1" : null));
    const billing = createBilling(t);
    await billing
      .checkout({
        organizationId: "org",
        options: {
          price: "price_1",
          successUrl: "https://a/ok",
          params: {
            customer: "cus_other",
            client_reference_id: "elsewhere",
            metadata: { campaign: "spring", organization_id: "spoofed" },
            subscription_data: {
              trial_period_days: 14,
              metadata: { source: "pricing" },
            },
            line_items: [{ price: "price_override", quantity: 3 }],
          },
        },
      })
      .orThrow();
    expect(t.stripeCalls.at(-1)).toMatchObject([
      "checkout.create",
      {
        params: {
          customer: "cus_1",
          client_reference_id: "org",
          metadata: { campaign: "spring", organization_id: "org" },
          subscription_data: {
            trial_period_days: 14,
            metadata: { source: "pricing", organization_id: "org" },
          },
          line_items: [{ price: "price_override", quantity: 3 }],
        },
      },
    ]);
    await billing
      .checkout({
        organizationId: "org",
        options: {
          price: "price_1",
          successUrl: "https://a/ok",
          params: { mode: "payment" },
        },
      })
      .orThrow();
    const [, last] = t.stripeCalls.at(-1) as [string, { params: object }];
    expect(last.params).toMatchObject({
      mode: "payment",
      metadata: { organization_id: "org" },
    });
    expect(last.params).not.toHaveProperty("subscription_data");
  });

  it("keeps the earlier customer when two checkouts race", async () => {
    const t = setup((fn) =>
      fn === "link_billing_customer" ? "cus_first" : null,
    );

    const billing = createBilling({ transport: t.transport, stripe: t.stripe });
    expect(
      await billing.ensureCustomer({ organizationId: "org" }).orThrow(),
    ).toBe("cus_first");
    expect(t.seen).toEqual([]);
  });

  it("turns Stripe errors into DbErrors", async () => {
    const t = setup(() => null, {
      customers: {
        create: async () => {
          throw new Error("card declined");
        },
      },
    });

    expect(
      await createBilling(t).ensureCustomer({ organizationId: "org" }),
    ).toMatchObject({ ok: false, error: { message: "card declined" } });
  });

  it("skips seat sync without a subscription or a change", async () => {
    let item: unknown = null;

    const t = setup((fn) =>
      fn === "billing_seat_count"
        ? 3
        : fn === "billing_subscription_item"
          ? item
          : null,
    );

    const billing = createBilling({
      ...t,
      seatPrice: "price_seat",
      prorationBehavior: "none",
    });

    expect(
      await billing.syncSeats({ organizationId: "org" }).orThrow(),
    ).toEqual({ quantity: 3, previousQuantity: undefined, changed: false });
    item = {
      subscription: "sub",
      item: "si",
      price: "price_seat",
      quantity: 3,
      status: "active",
    };
    expect(
      await billing.syncSeats({ organizationId: "org" }).orThrow(),
    ).toMatchObject({ changed: false });
    expect(
      t.calls.find(([fn]) => fn === "billing_subscription_item")?.[1],
    ).toEqual({ tenant: "org", price: "price_seat" });
    item = { ...(item as object), quantity: 1 };
    await billing.syncSeats({ organizationId: "org" }).orThrow();
    expect(t.stripeCalls.at(-1)).toMatchObject([
      "items.update",
      { params: { quantity: 3, proration_behavior: "none" } },
    ]);
  });

  it("cancels the active subscription, and nothing without one", async () => {
    let item: unknown = null;
    const cancelled: string[] = [];

    const t = setup(
      (fn) => (fn === "billing_subscription_item" ? item : null),
      {
        subscriptions: {
          cancel: async (id: string) => {
            cancelled.push(id);

            return { id };
          },
        },
      },
    );

    const billing = createBilling(t);
    expect(await billing.cancelSubscription("org").orThrow()).toBeUndefined();
    item = {
      subscription: "sub_1",
      item: "si",
      price: "price_seat",
      quantity: 3,
      status: "active",
    };
    expect(await billing.cancelSubscription("org").orThrow()).toBe("sub_1");
    expect(cancelled).toEqual(["sub_1"]);

    const failing = createBilling(
      setup(() => item, {
        subscriptions: {
          cancel: async () => {
            throw new Error("No such subscription");
          },
        },
      }),
    );

    expect(await failing.cancelSubscription("org")).toMatchObject({
      ok: false,
      error: { message: "No such subscription" },
    });
  });

  it("syncs each tenant once per batch from the seat sink", async () => {
    const t = setup((fn) =>
      fn === "billing_seat_count"
        ? 2
        : fn === "billing_subscription_item"
          ? { subscription: "sub", item: "si", quantity: 1, status: "active" }
          : null,
    );

    const sink = createBilling(t).seatSink();
    await sink.send([
      {
        specversion: "1.0",
        id: "1",
        source: "s",
        type: "dev.better-supabase.organization.member_added",
        partitionkey: "org",
      },
      {
        specversion: "1.0",
        id: "2",
        source: "s",
        type: "dev.better-supabase.organization.member_removed",
        partitionkey: "org",
      },
      {
        specversion: "1.0",
        id: "3",
        source: "s",
        type: "dev.better-supabase.organization.updated",
        partitionkey: "other",
      },
      {
        specversion: "1.0",
        id: "4",
        source: "s",
        type: "organization.member_left",
      },
    ]);
    const updates = t.stripeCalls.filter(([name]) => name === "items.update");
    expect(updates).toEqual([
      [
        "items.update",
        {
          id: "si",
          params: { quantity: 2, proration_behavior: "create_prorations" },
          options: { idempotencyKey: "seats:si:1:2:2" },
        },
      ],
    ]);
  });

  it("links customers from checkout and subscription events", async () => {
    const tenants = new Map<string, string>();

    const t = setup((fn, args) => {
      if (fn === "link_billing_customer") {
        const tenant = String(args["tenant"]);

        if (!tenants.has(tenant)) {
          tenants.set(tenant, String(args["customer"]));
        }

        return tenants.get(tenant);
      }

      if (fn === "billing_customer_tenant") {
        for (const [tenant, customer] of tenants) {
          if (customer === args["customer"]) {
            return tenant;
          }
        }

        return null;
      }

      if (fn === "billing_status") {
        return { customer: "cus_1", seats: 1, subscription: null };
      }

      return null;
    });

    const invalidated: string[] = [];

    const sql = {
      queryRaw: async () => [{ user_id: "u1" }, { user_id: "u2" }],
    } as unknown as SqlClient;

    const billing = createBilling({
      ...t,
      sessions: { sql, invalidate: (id) => invalidated.push(id) },
    });

    expect(
      await billing
        .handleStripeEvent({
          id: "evt_1",
          type: "checkout.session.completed",
          data: {
            object: {
              customer: "cus_1",
              client_reference_id: "org-1",
              subscription: "sub_1",
            },
          },
        })
        .orThrow(),
    ).toEqual({
      event: "billing.checkout_completed",
      organizationId: "org-1",
      customerId: "cus_1",
      invalidated: [],
    });

    // The subscription carries the tenant in metadata before any checkout event.
    expect(
      await billing
        .handleStripeEvent({
          id: "evt_2",
          type: "customer.subscription.created",
          data: {
            object: {
              id: "sub_2",
              customer: { id: "cus_2" },
              status: "active",
              metadata: { organization_id: "org-2" },
            },
          },
        })
        .orThrow(),
    ).toMatchObject({
      event: "billing.subscription_created",
      organizationId: "org-2",
      invalidated: ["u1", "u2"],
    });
    expect(invalidated).toEqual(["u1", "u2"]);

    for (const event of [
      null,
      {
        id: "e",
        type: "invoice.paid",
        data: { object: { customer: "cus_1" } },
      },
      {
        id: "e",
        type: "customer.subscription.deleted",
        data: { object: { id: "s", customer: "cus_unknown" } },
      },
      {
        id: "e",
        type: "checkout.session.completed",
        data: { object: { customer: "cus_1" } },
      },
      { id: "e", type: "checkout.session.completed", data: { object: "x" } },
    ]) {
      expect(
        (await billing.handleStripeEvent(event).orThrow()).event,
      ).toBeUndefined();
    }

    expect(t.seen.map((event) => (event as { type: string }).type)).toEqual([
      "billing.checkout_completed",
      "billing.subscription_created",
    ]);
    expect(await billing.status("org-1").orThrow()).toEqual({
      customerId: "cus_1",
      seats: 1,
      subscription: undefined,
    });
  });

  it("stores subscription events in webhook mode and guards checkout", async () => {
    let blocked: string | null = null;

    const t = setup((fn) => {
      if (fn === "billing_customer_tenant") {
        return "org-1";
      }

      if (fn === "upsert_billing_subscription") {
        return true;
      }

      if (fn === "billing_checkout_block") {
        return blocked;
      }

      return null;
    });

    const billing = createBilling({ ...t, subscriptions: "webhook" });

    await billing
      .handleStripeEvent({
        id: "evt_1",
        type: "customer.subscription.updated",
        created: 1_700_000_000,
        data: {
          object: {
            id: "sub_1",
            customer: "cus_1",
            status: "active",
            items: { data: [{ price: { id: "price_pro" } }] },
          },
        },
      })
      .orThrow();

    expect(
      t.calls.find(([fn]) => fn === "upsert_billing_subscription"),
    ).toEqual([
      "upsert_billing_subscription",
      {
        tenant: "org-1",
        subscription: "sub_1",
        status: "active",
        price: "price_pro",
        event_at: "2023-11-14T22:13:20.000Z",
      },
    ]);

    blocked = "BILLING_ALREADY_SUBSCRIBED";

    const result = await billing.checkout({
      organizationId: "org-1",
      options: {
        price: "price_pro",
        successUrl: "https://x/ok",
        cancelUrl: "https://x/no",
      },
    });

    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "conflict",
      hint: "BILLING_ALREADY_SUBSCRIBED",
    });

    const external = createBilling({ ...t, external: () => "vercel" });

    const viaProvider = await external.checkout({
      organizationId: "org-1",
      options: {
        price: "price_pro",
        successUrl: "https://x/ok",
        cancelUrl: "https://x/no",
      },
    });

    expect(viaProvider.ok ? undefined : viaProvider.error).toMatchObject({
      kind: "conflict",
      hint: "BILLING_EXTERNAL",
    });
  });

  it("emits block events when given the hub", async () => {
    const t = setup((fn, args) =>
      fn === "link_billing_customer"
        ? args["customer"]
        : fn === "billing_customer_tenant"
          ? "org"
          : null,
    );

    const billing = createBilling(t);
    await billing.ensureCustomer({ organizationId: "org" }).orThrow();
    await billing
      .handleStripeEvent({
        id: "evt",
        type: "customer.subscription.deleted",
        data: {
          object: { id: "sub", customer: "cus_new", status: "canceled" },
        },
      })
      .orThrow();
    expect(t.seen).toEqual([
      {
        type: "billing.customer_linked",
        data: { organizationId: "org", customerId: "cus_new" },
      },
      {
        type: "billing.subscription_deleted",
        data: {
          organizationId: "org",
          customerId: "cus_new",
          subscriptionId: "sub",
          stripeEventId: "evt",
          status: "canceled",
        },
      },
    ]);
  });

  it("checks out by plan key and changes plans", async () => {
    const item = {
      subscription: "sub_1",
      item: "si_1",
      price: "price_basic",
      quantity: 1,
      status: "active",
    };

    const t = setup(
      (fn, args) => {
        if (fn === "billing_customer") {
          return "cus_1";
        }

        if (fn === "billing_plan_price") {
          return args["plan"] === "pro"
            ? `price_pro_${String(args["billing_interval"] ?? "month")}`
            : null;
        }

        if (fn === "billing_subscription_item") {
          return item;
        }

        return null;
      },
      {
        subscriptions: {
          cancel: async () => ({ id: "sub_1" }),
          update: async (id: string, params: unknown, options: unknown) => {
            stripeCalls.push(["subscriptions.update", { id, params, options }]);

            return { id };
          },
        },
      },
    );

    const stripeCalls = t.stripeCalls;
    const billing = createBilling(t);
    await billing
      .checkout({
        organizationId: "org",
        options: { plan: "pro", interval: "year", successUrl: "https://a" },
      })
      .orThrow();
    expect(t.stripeCalls.at(-1)).toMatchObject([
      "checkout.create",
      { params: { line_items: [{ price: "price_pro_year", quantity: 1 }] } },
    ]);
    expect(
      await billing.checkout({
        organizationId: "org",
        options: { plan: "gold", successUrl: "https://a" },
      }),
    ).toMatchObject({ ok: false, error: { hint: "BILLING_PLAN_UNKNOWN" } });
    expect(
      await billing.checkout({
        organizationId: "org",
        options: { successUrl: "https://a" },
      }),
    ).toMatchObject({ ok: false, error: { hint: "BILLING_PRICE_REQUIRED" } });

    expect(
      await billing
        .changePlan({
          organizationId: "org",
          change: { plan: "pro", idempotencyKey: "k" },
        })
        .orThrow(),
    ).toMatchObject({ itemId: "si_1", price: "price_pro_month" });
    expect(t.stripeCalls.at(-1)).toEqual([
      "subscriptions.update",
      {
        id: "sub_1",
        params: {
          items: [{ id: "si_1", price: "price_pro_month" }],
          proration_behavior: "create_prorations",
          cancel_at_period_end: false,
        },
        options: { idempotencyKey: "k" },
      },
    ]);
    expect(
      await billing
        .cancelAtPeriodEnd({ organizationId: "org", cancel: true })
        .orThrow(),
    ).toBe("sub_1");
    expect(t.stripeCalls.at(-1)).toMatchObject([
      "subscriptions.update",
      { params: { cancel_at_period_end: true } },
    ]);
  });

  it("checks out a plan variant with add-on line items", async () => {
    const t = setup((fn, args) => {
      if (fn === "billing_customer") {
        return "cus_1";
      }

      if (fn === "billing_plan_price") {
        if (args["plan"] === "missing") {
          return null;
        }

        return `price_${String(args["plan"])}_${String(args["variant"] ?? "base")}`;
      }

      return null;
    });

    const billing = createBilling(t);
    await billing
      .checkout({
        organizationId: "org",
        options: {
          plan: "pro",
          variant: "annual-team",
          items: [
            { plan: "credits", variant: "5000", quantity: 2 },
            { price: "price_support" },
          ],
          successUrl: "https://a",
        },
      })
      .orThrow();
    expect(t.stripeCalls.at(-1)).toMatchObject([
      "checkout.create",
      {
        params: {
          line_items: [
            { price: "price_pro_annual-team", quantity: 1 },
            { price: "price_credits_5000", quantity: 2 },
            { price: "price_support", quantity: 1 },
          ],
        },
      },
    ]);
    expect(
      t.calls.filter(([fn]) => fn === "billing_plan_price").map(([, a]) => a),
    ).toEqual([
      { plan: "pro", billing_interval: undefined, variant: "annual-team" },
      { plan: "credits", billing_interval: undefined, variant: "5000" },
    ]);
    const before = t.stripeCalls.length;
    expect(
      await billing.checkout({
        organizationId: "org",
        options: {
          price: "price_x",
          items: [{ plan: "missing" }],
          successUrl: "https://a",
        },
      }),
    ).toMatchObject({ ok: false, error: { hint: "BILLING_PLAN_UNKNOWN" } });
    expect(t.stripeCalls).toHaveLength(before);
  });

  it("reads the full subscription and every tenant's for platform staff", async () => {
    const t = setup((fn) => {
      if (fn === "billing_subscription") {
        return { id: "sub_1", items: [] };
      }

      if (fn === "billing_all_subscriptions") {
        return [
          { tenant: "org", customer: "cus_1", subscription: { id: "sub_1" } },
          { tenant: "broken", customer: "cus_2", subscription: null },
        ];
      }

      return null;
    });

    const billing = createBilling(t);
    expect(await billing.subscription("org").orThrow()).toEqual({
      id: "sub_1",
      items: [],
    });
    expect(
      await billing
        .allSubscriptions({ status: "active", limit: 10, cursor: 99 })
        .orThrow(),
    ).toEqual([
      { organizationId: "org", customerId: "cus_1", row: { id: "sub_1" } },
    ]);
    expect(t.calls.at(-1)).toEqual([
      "billing_all_subscriptions",
      { for_status: "active", max_rows: 10, before_created: 99 },
    ]);
    await billing.allSubscriptions().orThrow();
    expect(t.calls.at(-1)![1]).toEqual({
      for_status: undefined,
      max_rows: 100,
      before_created: undefined,
    });

    const invoices = createBilling(
      setup((fn) =>
        fn === "billing_all_invoices"
          ? [{ tenant: "org", customer: "cus_1", invoice: { id: "in_1" } }]
          : null,
      ),
    );

    expect(await invoices.allInvoices({ status: "open" }).orThrow()).toEqual([
      { organizationId: "org", customerId: "cus_1", row: { id: "in_1" } },
    ]);
    const none = createBilling(setup(() => null));
    expect(await none.allInvoices().orThrow()).toEqual([]);
    expect(await none.subscription("org").orThrow()).toBeUndefined();
    expect(await none.allSubscriptions().orThrow()).toEqual([]);
  });

  it("reads, adds and removes the customer's tax ids", async () => {
    let linked: string | undefined;
    const taxCalls: unknown[] = [];
    const taxId = { id: "txi_1", type: "eu_vat", value: "DE123456789" };

    const t = setup(
      (fn, args) => {
        if (fn === "billing_customer") {
          return linked ?? null;
        }

        if (fn === "link_billing_customer") {
          linked = String(args["customer"]);

          return linked;
        }

        return null;
      },
      {
        customers: {
          create: async () => ({ id: "cus_new" }),
          listTaxIds: async (id: string, params: unknown) => {
            taxCalls.push(["list", id, params]);

            return { data: [taxId] };
          },
          createTaxId: async (id: string, params: unknown) => {
            taxCalls.push(["create", id, params]);

            return taxId;
          },
          deleteTaxId: async (id: string, tax: string) => {
            taxCalls.push(["delete", id, tax]);

            return { id: tax, deleted: true };
          },
        },
      },
    );

    const billing = createBilling(t);
    expect(await billing.taxIds({ organizationId: "org" }).orThrow()).toEqual(
      [],
    );
    expect(
      await billing.removeTaxId({ organizationId: "org", taxId: "txi_1" }),
    ).toMatchObject({ error: { hint: "BILLING_NO_CUSTOMER" } });
    expect(
      await billing
        .addTaxId({
          organizationId: "org",
          taxId: { type: "eu_vat", value: "DE123456789" },
        })
        .orThrow(),
    ).toEqual(taxId);
    expect(await billing.taxIds({ organizationId: "org" }).orThrow()).toEqual([
      taxId,
    ]);
    expect(
      await billing
        .removeTaxId({ organizationId: "org", taxId: "txi_1" })
        .orThrow(),
    ).toBe("txi_1");
    expect(taxCalls).toEqual([
      ["create", "cus_new", { type: "eu_vat", value: "DE123456789" }],
      ["list", "cus_new", { limit: 100 }],
      ["delete", "cus_new", "txi_1"],
    ]);
    linked = "cus_1";
    const bare = createBilling(setup(() => "cus_1"));

    for (const result of [
      await bare.taxIds({ organizationId: "org" }),
      await bare.addTaxId({
        organizationId: "org",
        taxId: { type: "eu_vat", value: "x" },
      }),
      await bare.removeTaxId({ organizationId: "org", taxId: "txi_1" }),
    ]) {
      expect(result).toMatchObject({
        error: { hint: "BILLING_STRIPE_CLIENT" },
      });
    }
  });

  it("lists linked customers through billing_all_customers", async () => {
    const t = setup((fn) =>
      fn === "billing_all_customers"
        ? [
            {
              tenant: "org-1",
              customer: "cus_1",
              email: "a@b.c",
              name: "A",
              created: "2026-01-01T00:00:00+00:00",
            },
            {
              tenant: "org-2",
              customer: "cus_2",
              email: null,
              name: null,
              created: null,
            },
            "junk",
          ]
        : null,
    );

    const customers = await createBilling(t).allCustomers().orThrow();
    expect(
      customers.map((entry) => ({
        ...entry,
        created: entry.created?.toString(),
      })),
    ).toEqual([
      {
        organizationId: "org-1",
        customerId: "cus_1",
        email: "a@b.c",
        name: "A",
        created: "2026-01-01T00:00:00Z",
      },
      {
        organizationId: "org-2",
        customerId: "cus_2",
        email: undefined,
        name: undefined,
        created: undefined,
      },
    ]);
    expect(t.calls).toEqual([["billing_all_customers", {}]]);
    expect(
      await createBilling(setup(() => null))
        .allCustomers()
        .orThrow(),
    ).toEqual([]);
  });

  it("reads synced tax ids through billing_tax_ids", async () => {
    const t = setup((fn) =>
      fn === "billing_tax_ids"
        ? [
            {
              id: "txi_1",
              type: "eu_vat",
              value: "DE123456789",
              country: "DE",
              verification: { status: "verified" },
              created: 1,
            },
            { id: "txi_2", type: "gb_vat", value: "GB1", country: null },
            {
              id: "txi_3",
              type: "us_ein",
              value: "12-3456789",
              created: "1767225600",
            },
            { id: "txi_4", type: "us_ein", value: "1", created: true },
            "junk",
          ]
        : null,
    );

    const billing = createBilling(t);
    expect(
      await billing
        .taxIds({ organizationId: "org", options: { from: "sync" } })
        .orThrow(),
    ).toEqual([
      {
        id: "txi_1",
        type: "eu_vat",
        value: "DE123456789",
        country: "DE",
        verification: { status: "verified" },
        created: 1,
      },
      {
        id: "txi_2",
        type: "gb_vat",
        value: "GB1",
        country: null,
        verification: null,
        created: null,
      },
      {
        id: "txi_3",
        type: "us_ein",
        value: "12-3456789",
        country: null,
        verification: null,
        created: 1_767_225_600,
      },
      {
        id: "txi_4",
        type: "us_ein",
        value: "1",
        country: null,
        verification: null,
        created: null,
      },
    ]);
    expect(t.calls).toEqual([["billing_tax_ids", { tenant: "org" }]]);
    const empty = createBilling(setup(() => null));
    expect(
      await empty
        .taxIds({ organizationId: "org", options: { from: "sync" } })
        .orThrow(),
    ).toEqual([]);
  });

  it("reads invoices and payment methods and voids only the tenant's invoices", async () => {
    const t = setup(
      (fn) => {
        if (fn === "billing_invoices") {
          return [{ id: "in_1", status: "open" }, "junk"];
        }

        if (fn === "billing_payment_methods") {
          return [{ id: "pm_1", type: "card" }];
        }

        if (fn === "billing_customer_details") {
          return { id: "cus_1", email: "a@b.c" };
        }

        if (fn === "billing_customer") {
          return "cus_1";
        }

        return null;
      },
      {
        invoices: {
          voidInvoice: async (id: string) => ({ id, status: "void" }),
          markUncollectible: async (id: string) => ({
            id,
            status: "uncollectible",
          }),
        },
        customers: {
          create: async () => ({ id: "cus_1" }),
          update: async (id: string) => ({ id }),
        },
      },
    );

    const billing = createBilling(t);
    expect(await billing.invoices({ organizationId: "org" }).orThrow()).toEqual(
      [{ id: "in_1", status: "open" }],
    );
    expect(await billing.paymentMethods("org").orThrow()).toEqual([
      { id: "pm_1", type: "card" },
    ]);
    expect(await billing.customerDetails("org").orThrow()).toMatchObject({
      email: "a@b.c",
    });
    expect(
      await billing
        .voidInvoice({ organizationId: "org", invoiceId: "in_1" })
        .orThrow(),
    ).toBe("in_1");
    expect(
      await billing
        .markInvoiceUncollectible({ organizationId: "org", invoiceId: "in_1" })
        .orThrow(),
    ).toBe("in_1");
    expect(
      await billing.voidInvoice({
        organizationId: "org",
        invoiceId: "in_other",
      }),
    ).toMatchObject({
      ok: false,
      error: { hint: "BILLING_INVOICE_NOT_FOUND" },
    });
    expect(
      await billing
        .updateCustomer({ organizationId: "org", update: { email: "x@y.z" } })
        .orThrow(),
    ).toBe("cus_1");
  });

  it("explains a Stripe client without the admin methods", async () => {
    const t = setup(
      (fn) =>
        fn === "billing_subscription_item"
          ? { subscription: "s", item: "i", quantity: 1, status: "active" }
          : fn === "billing_invoices"
            ? [{ id: "in_1" }]
            : fn === "billing_customer"
              ? "cus_1"
              : null,
      { subscriptions: { cancel: async () => ({ id: "s" }) } },
    );

    const billing = createBilling(t);

    for (const result of [
      await billing.changePlan({
        organizationId: "org",
        change: { price: "p" },
      }),
      await billing.cancelAtPeriodEnd({ organizationId: "org", cancel: false }),
      await billing.voidInvoice({ organizationId: "org", invoiceId: "in_1" }),
      await billing.markInvoiceUncollectible({
        organizationId: "org",
        invoiceId: "in_1",
      }),
      await billing.updateCustomer({
        organizationId: "org",
        update: { name: "x" },
      }),
    ]) {
      expect(result).toMatchObject({
        ok: false,
        error: { hint: "BILLING_STRIPE_CLIENT" },
      });
    }

    const none = createBilling(setup(() => null));
    expect(
      await none.changePlan({ organizationId: "org", change: { price: "p" } }),
    ).toMatchObject({ ok: false, error: { hint: "BILLING_NO_SUBSCRIPTION" } });
  });
});

interface Row {
  customer: string | null;
  account: string | null;
}

/** A fake `billing_customers` table behind the module's functions. */
function harness(
  rows: Record<string, Row> = {},
  stripeOverrides: Record<string, unknown> = {},
) {
  const calls: [string, Record<string, unknown>][] = [];

  const rowOf = (tenant: string): Row => {
    const row = rows[tenant] ?? { customer: null, account: null };
    rows[tenant] = row;

    return row;
  };

  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      calls.push([fn, { ...args }]);
      const tenant = String(args["tenant"]);

      switch (fn) {
        case "billing_customer": {
          return rows[tenant]?.customer ?? null;
        }

        case "billing_account": {
          return rows[tenant]?.account ?? null;
        }

        case "link_billing_account": {
          const row = rowOf(tenant);
          row.account ??= String(args["account"]);

          return row.account;
        }

        case "link_billing_customer": {
          const row = rowOf(tenant);
          row.customer ??= String(args["customer"]);

          return row.customer;
        }

        case "billing_customer_tenant": {
          const id = String(args["customer"]);

          return (
            Object.entries(rows).find(
              ([, row]) => row.customer === id || row.account === id,
            )?.[0] ?? null
          );
        }

        case "billing_status": {
          return {
            customer: rows[tenant]?.customer ?? null,
            account: rows[tenant]?.account ?? null,
            seats: 1,
            subscription: null,
          };
        }

        default: {
          return null;
        }
      }
    },
  };

  const stripeCalls: [string, unknown, unknown?][] = [];

  const stripe = {
    customers: {
      create: async (params: unknown) => {
        stripeCalls.push(["customers.create", params]);

        return { id: "cus_v1" };
      },
    },
    checkout: {
      sessions: {
        create: async (params: unknown) => {
          stripeCalls.push(["checkout.create", params]);

          return { id: "cs_1", url: "https://checkout.stripe.com/c/cs_1" };
        },
      },
    },
    billingPortal: {
      sessions: {
        create: async (params: unknown) => {
          stripeCalls.push(["portal.create", params]);

          return { id: "bps_1", url: "https://billing.stripe.com/p/1" };
        },
      },
    },
    v2: {
      core: {
        accounts: {
          create: async (params: unknown, options: unknown) => {
            stripeCalls.push(["accounts.create", params, options]);

            return { id: "acct_new" };
          },
        },
      },
    },
    ...stripeOverrides,
  } as unknown as StripeClient;

  const events = new EventHub();
  const seen: { type: string; data: unknown }[] = [];
  events.on("block", (event) =>
    seen.push({ type: event.type, data: event.data }),
  );

  return { transport, calls, stripe, stripeCalls, events, seen, rows };
}

describe("createBilling with customerAccounts", () => {
  it("creates the tenant's account once and bills it as customer_account", async () => {
    const t = harness();

    const billing = createBilling({
      ...t,
      customerAccounts: {
        params: (tenant) => ({
          identity: { country: "de" },
          metadata: { source: tenant },
        }),
      },
    });

    const session = await billing
      .checkout({
        organizationId: "org",
        options: {
          price: "price_1",
          successUrl: "https://a/ok",
          email: "billing@acme.test",
          name: "Acme",
          params: { customer: "cus_ignored" },
        },
      })
      .orThrow();

    expect(session.id).toBe("cs_1");
    expect(t.stripeCalls[0]).toEqual([
      "accounts.create",
      {
        contact_email: "billing@acme.test",
        display_name: "Acme",
        configuration: { customer: {} },
        identity: { country: "de" },
        metadata: { source: "org", organization_id: "org" },
      },
      { idempotencyKey: "account:org" },
    ]);
    expect(t.stripeCalls[1]).toEqual([
      "checkout.create",
      {
        customer_account: "acct_new",
        mode: "subscription",
        client_reference_id: "org",
        line_items: [{ price: "price_1", quantity: 1 }],
        success_url: "https://a/ok",
        metadata: { organization_id: "org" },
        subscription_data: { metadata: { organization_id: "org" } },
      },
    ]);
    expect(t.seen).toContainEqual({
      type: "billing.account_linked",
      data: { organizationId: "org", accountId: "acct_new" },
    });

    await billing
      .checkout({
        organizationId: "org",
        options: { price: "price_1", successUrl: "https://a/ok" },
      })
      .orThrow();
    expect(
      t.stripeCalls.filter(([name]) => name === "accounts.create"),
    ).toHaveLength(1);
    expect(t.stripeCalls.some(([name]) => name === "customers.create")).toBe(
      false,
    );

    expect(
      await billing
        .portal({ organizationId: "org", options: { returnUrl: "https://a" } })
        .orThrow(),
    ).toEqual({ url: "https://billing.stripe.com/p/1" });
    expect(t.stripeCalls.at(-1)).toEqual([
      "portal.create",
      { customer_account: "acct_new", return_url: "https://a" },
    ]);
    expect(await billing.account("org").orThrow()).toBe("acct_new");
    expect(await billing.status("org").orThrow()).toMatchObject({
      customerId: undefined,
      accountId: "acct_new",
    });
  });

  it("reuses the account resolve returns and keeps a tenant's v1 customer", async () => {
    const t = harness({ legacy: { customer: "cus_old", account: null } });

    const billing = createBilling({
      ...t,
      customerAccounts: { resolve: (tenant) => `acct_${tenant}` },
    });

    expect(
      await billing.ensureAccount({ organizationId: "shop" }).orThrow(),
    ).toBe("acct_shop");
    expect(t.stripeCalls).toEqual([]);

    await billing
      .checkout({
        organizationId: "legacy",
        options: { price: "price_1", successUrl: "https://a" },
      })
      .orThrow();
    expect(t.stripeCalls.at(-1)).toMatchObject([
      "checkout.create",
      { customer: "cus_old" },
    ]);
    expect(t.stripeCalls.at(-1)?.[1]).not.toHaveProperty("customer_account");
  });

  it("waits for Stripe's customer before ensureCustomer returns one", async () => {
    const t = harness();
    const billing = createBilling({ ...t, customerAccounts: true });

    expect(
      await billing.ensureCustomer({ organizationId: "org" }),
    ).toMatchObject({
      ok: false,
      error: { kind: "not_found", hint: "BILLING_CUSTOMER_PENDING" },
    });
    expect(t.rows["org"]).toEqual({ customer: null, account: "acct_new" });
    expect(t.stripeCalls.some(([name]) => name === "customers.create")).toBe(
      false,
    );

    t.rows["org"]!.customer = "cus_linked";
    expect(
      await billing.ensureCustomer({ organizationId: "org" }).orThrow(),
    ).toBe("cus_linked");
  });

  it("explains a Stripe client without the v2 API", async () => {
    const t = harness({}, { v2: undefined });
    const billing = createBilling({ ...t, customerAccounts: true });

    expect(
      await billing.ensureAccount({ organizationId: "org" }),
    ).toMatchObject({ ok: false, error: { hint: "BILLING_STRIPE_CLIENT" } });
  });

  it("records the customer Stripe creates for the account from webhooks", async () => {
    const t = harness({ org: { customer: null, account: "acct_1" } });
    const billing = createBilling({ ...t, customerAccounts: true });

    const outcome = await billing
      .handleStripeEvent({
        id: "evt_1",
        type: "customer.subscription.created",
        data: {
          object: {
            id: "sub_1",
            status: "active",
            customer: "cus_made",
            customer_account: "acct_1",
          },
        },
      })
      .orThrow();

    expect(outcome).toEqual({
      event: "billing.subscription_created",
      organizationId: "org",
      customerId: "cus_made",
      accountId: "acct_1",
      invalidated: [],
    });
    expect(t.rows["org"]).toEqual({ customer: "cus_made", account: "acct_1" });
    expect(t.seen.at(-1)).toEqual({
      type: "billing.subscription_created",
      data: {
        organizationId: "org",
        customerId: "cus_made",
        accountId: "acct_1",
        subscriptionId: "sub_1",
        stripeEventId: "evt_1",
        status: "active",
      },
    });
  });

  it("records the customer from a checkout session and from other events", async () => {
    const t = harness({
      org: { customer: null, account: "acct_1" },
      other: { customer: null, account: "acct_2" },
    });

    const billing = createBilling({ ...t, customerAccounts: true });

    const completed = await billing
      .handleStripeEvent({
        id: "evt_1",
        type: "checkout.session.completed",
        data: {
          object: {
            client_reference_id: "org",
            customer: "cus_1",
            customer_account: "acct_1",
            subscription: "sub_1",
          },
        },
      })
      .orThrow();

    expect(completed).toMatchObject({
      event: "billing.checkout_completed",
      organizationId: "org",
      customerId: "cus_1",
      accountId: "acct_1",
    });
    expect(t.rows["org"]?.customer).toBe("cus_1");

    const invoice = await billing
      .handleStripeEvent({
        id: "evt_2",
        type: "invoice.paid",
        data: {
          object: {
            id: "in_1",
            customer: { id: "cus_2" },
            customer_account: "acct_2",
          },
        },
      })
      .orThrow();

    expect(invoice).toEqual({
      event: undefined,
      organizationId: "other",
      customerId: "cus_2",
      accountId: "acct_2",
      invalidated: [],
    });
    expect(t.rows["other"]?.customer).toBe("cus_2");

    const elsewhere = await billing
      .handleStripeEvent({
        id: "evt_3",
        type: "checkout.session.completed",
        data: {
          object: {
            client_reference_id: "org",
            customer: "cus_x",
            customer_account: "acct_other",
          },
        },
      })
      .orThrow();

    expect(elsewhere.event).toBeUndefined();
    expect(t.rows["org"]).toEqual({ customer: "cus_1", account: "acct_1" });
  });

  it("links an account a subscription claims through its metadata", async () => {
    const t = harness();
    const billing = createBilling({ ...t, customerAccounts: true });

    const outcome = await billing
      .handleStripeEvent({
        id: "evt_1",
        type: "customer.subscription.updated",
        data: {
          object: {
            id: "sub_1",
            customer: "cus_1",
            customer_account: "acct_1",
            metadata: { organization_id: "org" },
          },
        },
      })
      .orThrow();

    expect(outcome.organizationId).toBe("org");
    expect(t.rows["org"]).toEqual({ customer: "cus_1", account: "acct_1" });
  });
});

describe("customerAccounts edge cases", () => {
  it("reports a failing resolve, a failed account create and a tenant without either id", async () => {
    const thrown = createBilling({
      ...harness(),
      customerAccounts: {
        resolve: () => {
          throw new Error("lookup down");
        },
      },
    });

    expect(await thrown.ensureAccount({ organizationId: "org" })).toMatchObject(
      { ok: false },
    );

    const t = harness(
      {},
      {
        v2: {
          core: {
            accounts: {
              create: async () => {
                throw new Error("stripe down");
              },
            },
          },
        },
      },
    );

    const failing = createBilling({ ...t, customerAccounts: true });
    expect(
      await failing.ensureCustomer({ organizationId: "org" }),
    ).toMatchObject({ ok: false });
    expect(
      await failing.checkout({
        organizationId: "org",
        options: { price: "p", successUrl: "https://a" },
      }),
    ).toMatchObject({ ok: false });
    expect(
      await failing.portal({
        organizationId: "org",
        options: { returnUrl: "https://a" },
      }),
    ).toMatchObject({ ok: false, error: { hint: "BILLING_NO_CUSTOMER" } });
  });

  it("creates an account with plain params and no contact", async () => {
    const t = harness();

    await createBilling({
      ...t,
      customerAccounts: { params: { dashboard: "none" } },
    })
      .ensureAccount({ organizationId: "org" })
      .orThrow();
    expect(t.stripeCalls[0]?.[1]).toEqual({
      configuration: { customer: {} },
      dashboard: "none",
      metadata: { organization_id: "org" },
    });

    const plain = harness();
    await createBilling({ ...plain, customerAccounts: true })
      .ensureAccount({ organizationId: "org" })
      .orThrow();
    expect(plain.stripeCalls[0]?.[1]).toEqual({
      configuration: { customer: {} },
      metadata: { organization_id: "org" },
    });
  });

  it("opens the portal for an account-only tenant without customerAccounts", async () => {
    const t = harness({ org: { customer: null, account: "acct_1" } });

    await createBilling(t)
      .portal({ organizationId: "org", options: { returnUrl: "https://a" } })
      .orThrow();
    expect(t.stripeCalls.at(-1)).toEqual([
      "portal.create",
      { customer_account: "acct_1", return_url: "https://a" },
    ]);
  });

  it("handles account events without a customer, and unknown accounts", async () => {
    const t = harness({ org: { customer: null, account: "acct_1" } });
    const billing = createBilling({ ...t, customerAccounts: true });

    const completed = await billing
      .handleStripeEvent({
        id: "evt_1",
        type: "checkout.session.completed",
        data: {
          object: { client_reference_id: "org", customer_account: "acct_1" },
        },
      })
      .orThrow();

    expect(completed).toMatchObject({
      event: "billing.checkout_completed",
      customerId: undefined,
      accountId: "acct_1",
    });

    const updated = await billing
      .handleStripeEvent({
        id: "evt_2",
        type: "customer.subscription.updated",
        data: { object: { id: "sub_1", customer_account: "acct_1" } },
      })
      .orThrow();

    expect(updated).toMatchObject({
      organizationId: "org",
      accountId: "acct_1",
    });

    const claimed = await billing
      .handleStripeEvent({
        id: "evt_3",
        type: "customer.subscription.updated",
        data: {
          object: {
            id: "sub_2",
            customer_account: "acct_new",
            metadata: { organization_id: "fresh" },
          },
        },
      })
      .orThrow();

    expect(claimed.organizationId).toBe("fresh");

    const refused = await billing
      .handleStripeEvent({
        id: "evt_4",
        type: "customer.subscription.updated",
        data: {
          object: {
            id: "sub_3",
            customer: "cus_9",
            customer_account: "acct_other",
            metadata: { organization_id: "org" },
          },
        },
      })
      .orThrow();

    expect(refused).toMatchObject({
      event: undefined,
      organizationId: undefined,
      accountId: "acct_other",
    });

    expect(
      await billing
        .handleStripeEvent({
          id: "evt_5",
          type: "invoice.paid",
          data: {
            object: { customer: "cus_x", customer_account: "acct_none" },
          },
        })
        .orThrow(),
    ).toMatchObject({ organizationId: undefined, accountId: "acct_none" });
    expect(
      await billing
        .handleStripeEvent({
          id: "evt_6",
          type: "invoice.paid",
          data: { object: { customer: "cus_x" } },
        })
        .orThrow(),
    ).toMatchObject({ organizationId: undefined, customerId: undefined });
    expect(
      await billing
        .handleStripeEvent({
          id: "evt_7",
          type: "customer.subscription.updated",
          data: { object: { id: "sub_4" } },
        })
        .orThrow(),
    ).toMatchObject({ event: undefined });
  });

  it("passes database errors through", async () => {
    const t = harness();

    const failing: BlockTransport = {
      async call(schema, fn, args) {
        if (fn === "billing_customer_tenant" || fn.startsWith("link_")) {
          throw new Error("db down");
        }

        return t.transport.call(schema, fn, args);
      },
    };

    const billing = createBilling({
      ...t,
      transport: failing,
      customerAccounts: { resolve: () => "acct_1" },
    });

    expect(
      await billing.ensureAccount({ organizationId: "org" }),
    ).toMatchObject({ ok: false });

    for (const object of [
      { client_reference_id: "org", customer_account: "acct_1" },
      { client_reference_id: "org", customer: "cus_1" },
    ]) {
      expect(
        await billing.handleStripeEvent({
          id: "evt",
          type: "checkout.session.completed",
          data: { object },
        }),
      ).toMatchObject({ ok: false });
    }

    for (const type of ["customer.subscription.updated", "invoice.paid"]) {
      expect(
        await billing.handleStripeEvent({
          id: "evt",
          type,
          data: { object: { customer: "cus_1", customer_account: "acct_1" } },
        }),
      ).toMatchObject({ ok: false });
      expect(
        await billing.handleStripeEvent({
          id: "evt",
          type,
          data: { object: { customer_account: "acct_1" } },
        }),
      ).toMatchObject({ ok: type === "invoice.paid" });
    }
  });
});

describe("createBilling with connectEvents", () => {
  const connect = {
    id: "evt_1",
    type: "checkout.session.completed",
    account: "acct_connected",
    data: { object: { client_reference_id: "org", customer: "cus_1" } },
  };

  it("handles Connect events by default", async () => {
    const t = harness();

    expect(
      (await createBilling(t).handleStripeEvent(connect).orThrow()).event,
    ).toBe("billing.checkout_completed");
  });

  it("skips them with connectEvents: ignore", async () => {
    const t = harness();
    const billing = createBilling({ ...t, connectEvents: "ignore" });

    expect(await billing.handleStripeEvent(connect).orThrow()).toEqual({
      event: undefined,
      organizationId: undefined,
      customerId: undefined,
      accountId: undefined,
      invalidated: [],
    });
    expect(t.calls).toEqual([]);

    expect(
      (await billing.handleStripeEvent({ ...connect, account: null }).orThrow())
        .event,
    ).toBe("billing.checkout_completed");
  });
});
