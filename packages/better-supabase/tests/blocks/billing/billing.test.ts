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
      if (fn === "billing_customer") return linked ?? null;
      if (fn === "link_billing_customer") {
        linked ??= String(args["customer"]);
        return linked;
      }
      return null;
    });
    const billing = createBilling({ ...t, schema: "app" });
    expect(
      await billing.portal("org", { returnUrl: "https://a" }),
    ).toMatchObject({
      ok: false,
      error: { kind: "not_found", hint: "BILLING_NO_CUSTOMER" },
    });
    const session = await billing
      .checkout("org", {
        price: "price_1",
        mode: "payment",
        successUrl: "https://a/ok",
        cancelUrl: "https://a/no",
        email: "a@b.test",
        name: "Acme",
        idempotencyKey: "k1",
        params: { allow_promotion_codes: true },
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
      await billing.portal("org", { returnUrl: "https://a" }).orThrow(),
    ).toEqual({ url: "https://billing.stripe.com/p/1" });
    expect(await billing.ensureCustomer("org").orThrow()).toBe("cus_new");
    expect(
      t.stripeCalls.filter(([name]) => name === "customers.create"),
    ).toHaveLength(1);
  });

  it("merges checkout params deeply and keeps the tenant link", async () => {
    const t = setup((fn) => (fn === "billing_customer" ? "cus_1" : null));
    const billing = createBilling(t);
    await billing
      .checkout("org", {
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
      .checkout("org", {
        price: "price_1",
        successUrl: "https://a/ok",
        params: { mode: "payment" },
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
    expect(await billing.ensureCustomer("org").orThrow()).toBe("cus_first");
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
    expect(await createBilling(t).ensureCustomer("org")).toMatchObject({
      ok: false,
      error: { message: "card declined" },
    });
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
    expect(await billing.syncSeats("org").orThrow()).toEqual({
      quantity: 3,
      previousQuantity: undefined,
      changed: false,
    });
    item = {
      subscription: "sub",
      item: "si",
      price: "price_seat",
      quantity: 3,
      status: "active",
    };
    expect(await billing.syncSeats("org").orThrow()).toMatchObject({
      changed: false,
    });
    expect(
      t.calls.find(([fn]) => fn === "billing_subscription_item")?.[1],
    ).toEqual({
      tenant: "org",
      price: "price_seat",
    });
    item = { ...(item as object), quantity: 1 };
    await billing.syncSeats("org").orThrow();
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
    expect(await billing.cancelSubscription("org").orThrow()).toBe(undefined);
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
        if (!tenants.has(tenant)) tenants.set(tenant, String(args["customer"]));
        return tenants.get(tenant);
      }
      if (fn === "billing_customer_tenant") {
        for (const [tenant, customer] of tenants)
          if (customer === args["customer"]) return tenant;
        return null;
      }
      if (fn === "billing_status")
        return { customer: "cus_1", seats: 1, subscription: null };
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

  it("emits block events when given the hub", async () => {
    const t = setup((fn, args) =>
      fn === "link_billing_customer"
        ? args["customer"]
        : fn === "billing_customer_tenant"
          ? "org"
          : null,
    );
    const billing = createBilling(t);
    await billing.ensureCustomer("org").orThrow();
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
        if (fn === "billing_customer") return "cus_1";
        if (fn === "billing_plan_price")
          return args["plan"] === "pro"
            ? `price_pro_${String(args["billing_interval"] ?? "month")}`
            : null;
        if (fn === "billing_subscription_item") return item;
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
      .checkout("org", {
        plan: "pro",
        interval: "year",
        successUrl: "https://a",
      })
      .orThrow();
    expect(t.stripeCalls.at(-1)).toMatchObject([
      "checkout.create",
      { params: { line_items: [{ price: "price_pro_year", quantity: 1 }] } },
    ]);
    expect(
      await billing.checkout("org", { plan: "gold", successUrl: "https://a" }),
    ).toMatchObject({ ok: false, error: { hint: "BILLING_PLAN_UNKNOWN" } });
    expect(
      await billing.checkout("org", { successUrl: "https://a" }),
    ).toMatchObject({ ok: false, error: { hint: "BILLING_PRICE_REQUIRED" } });

    expect(
      await billing
        .changePlan("org", { plan: "pro", idempotencyKey: "k" })
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
    expect(await billing.cancelAtPeriodEnd("org", true).orThrow()).toBe(
      "sub_1",
    );
    expect(t.stripeCalls.at(-1)).toMatchObject([
      "subscriptions.update",
      { params: { cancel_at_period_end: true } },
    ]);
  });

  it("checks out a plan variant with add-on line items", async () => {
    const t = setup((fn, args) => {
      if (fn === "billing_customer") return "cus_1";
      if (fn === "billing_plan_price") {
        if (args["plan"] === "missing") return null;
        return `price_${String(args["plan"])}_${String(args["variant"] ?? "base")}`;
      }
      return null;
    });
    const billing = createBilling(t);
    await billing
      .checkout("org", {
        plan: "pro",
        variant: "annual-team",
        items: [
          { plan: "credits", variant: "5000", quantity: 2 },
          { price: "price_support" },
        ],
        successUrl: "https://a",
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
      await billing.checkout("org", {
        price: "price_x",
        items: [{ plan: "missing" }],
        successUrl: "https://a",
      }),
    ).toMatchObject({ ok: false, error: { hint: "BILLING_PLAN_UNKNOWN" } });
    expect(t.stripeCalls).toHaveLength(before);
  });

  it("reads the full subscription and every tenant's for platform staff", async () => {
    const t = setup((fn) => {
      if (fn === "billing_subscription") return { id: "sub_1", items: [] };
      if (fn === "billing_all_subscriptions")
        return [
          { tenant: "org", customer: "cus_1", subscription: { id: "sub_1" } },
          { tenant: "broken", customer: "cus_2", subscription: null },
        ];
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
        if (fn === "billing_customer") return linked ?? null;
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
    expect(await billing.taxIds("org").orThrow()).toEqual([]);
    expect(await billing.removeTaxId("org", "txi_1")).toMatchObject({
      error: { hint: "BILLING_NO_CUSTOMER" },
    });
    expect(
      await billing
        .addTaxId("org", { type: "eu_vat", value: "DE123456789" })
        .orThrow(),
    ).toEqual(taxId);
    expect(await billing.taxIds("org").orThrow()).toEqual([taxId]);
    expect(await billing.removeTaxId("org", "txi_1").orThrow()).toBe("txi_1");
    expect(taxCalls).toEqual([
      ["create", "cus_new", { type: "eu_vat", value: "DE123456789" }],
      ["list", "cus_new", { limit: 100 }],
      ["delete", "cus_new", "txi_1"],
    ]);
    linked = "cus_1";
    const bare = createBilling(setup(() => "cus_1"));
    for (const result of [
      await bare.taxIds("org"),
      await bare.addTaxId("org", { type: "eu_vat", value: "x" }),
      await bare.removeTaxId("org", "txi_1"),
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
    expect(await billing.taxIds("org", { from: "sync" }).orThrow()).toEqual([
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
    expect(await empty.taxIds("org", { from: "sync" }).orThrow()).toEqual([]);
  });

  it("reads invoices and payment methods and voids only the tenant's invoices", async () => {
    const t = setup(
      (fn) => {
        if (fn === "billing_invoices")
          return [{ id: "in_1", status: "open" }, "junk"];
        if (fn === "billing_payment_methods")
          return [{ id: "pm_1", type: "card" }];
        if (fn === "billing_customer_details")
          return { id: "cus_1", email: "a@b.c" };
        if (fn === "billing_customer") return "cus_1";
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
    expect(await billing.invoices("org").orThrow()).toEqual([
      { id: "in_1", status: "open" },
    ]);
    expect(await billing.paymentMethods("org").orThrow()).toEqual([
      { id: "pm_1", type: "card" },
    ]);
    expect(await billing.customerDetails("org").orThrow()).toMatchObject({
      email: "a@b.c",
    });
    expect(await billing.voidInvoice("org", "in_1").orThrow()).toBe("in_1");
    expect(
      await billing.markInvoiceUncollectible("org", "in_1").orThrow(),
    ).toBe("in_1");
    expect(await billing.voidInvoice("org", "in_other")).toMatchObject({
      ok: false,
      error: { hint: "BILLING_INVOICE_NOT_FOUND" },
    });
    expect(
      await billing.updateCustomer("org", { email: "x@y.z" }).orThrow(),
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
      await billing.changePlan("org", { price: "p" }),
      await billing.cancelAtPeriodEnd("org", false),
      await billing.voidInvoice("org", "in_1"),
      await billing.markInvoiceUncollectible("org", "in_1"),
      await billing.updateCustomer("org", { name: "x" }),
    ]) {
      expect(result).toMatchObject({
        ok: false,
        error: { hint: "BILLING_STRIPE_CLIENT" },
      });
    }
    const none = createBilling(setup(() => null));
    expect(await none.changePlan("org", { price: "p" })).toMatchObject({
      ok: false,
      error: { hint: "BILLING_NO_SUBSCRIPTION" },
    });
  });
});
