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

      expect(await billing.subscription(organization).orThrow()).toMatchObject({
        id: "sub_1",
        status: "active",
        items: [{ id: "si_1", price: "price_seat" }],
      });
      const all = await billing
        .allSubscriptions({ status: "active" })
        .orThrow();
      expect(
        all.find((entry) => entry.organizationId === organization),
      ).toMatchObject({ customerId: "cus_test1", row: { id: "sub_1" } });
      expect(
        await billing.allSubscriptions({ status: "canceled" }).orThrow(),
      ).not.toContainEqual(
        expect.objectContaining({ organizationId: organization }),
      );
      const staff = await s.user("staff");
      await s.asRole(staff, { platform_permissions: ["billing.read"] });
      expect((await billing.subscription(organization).orThrow())?.["id"]).toBe(
        "sub_1",
      );
      expect(
        (await billing.allSubscriptions().orThrow()).some(
          (entry) => entry.organizationId === organization,
        ),
      ).toBe(true);
      await s.asRole(staff);
      expect(await billing.subscription(organization)).toMatchObject({
        error: { hint: "BILLING_FORBIDDEN" },
      });
      expect(await billing.allSubscriptions()).toMatchObject({
        error: { hint: "BILLING_FORBIDDEN" },
      });
      await s.service();

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

  it("prices plans from the catalog and reads Stripe rows for readers only", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.rows(
        `create table public.bs_test_plan_prices (
           plan_key text not null, billing_interval text not null,
           price_id text not null, live boolean not null default true,
           pack text
         );
         insert into public.bs_test_plan_prices values
           ('pro', 'month', 'price_pro_m', true, null),
           ('pro', 'year', 'price_pro_y', true, null),
           ('old', 'month', 'price_old', false, null),
           ('credits', 'month', 'price_credits_5000', true, '5000'),
           ('credits', 'month', 'price_credits_1000', true, '1000'),
           ('credits', 'month', 'price_credits_base', true, null);`,
      );
      await s.install(["organizations", "billing"], {
        modules: {
          billing: {
            options: {
              plans: {
                table: "bs_test_plan_prices",
                key: "plan_key",
                price: "price_id",
                interval: "billing_interval",
                active: "live",
                variant: "pack",
              },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });
      await s.service();
      if (
        !(await s.value<boolean>("to_regclass('stripe.invoices') is not null"))
      ) {
        await s.rows(`create schema if not exists stripe;
          create table stripe.invoices (id text primary key, customer text, status text, total bigint, created bigint);
          create table stripe.payment_methods (id text primary key, customer text, type text, created bigint);
          create table if not exists stripe.customers (id text primary key, email text, name text, created bigint)`);
      }
      await s.rows(
        `select better_supabase.link_billing_customer($1, 'cus_bs_plans')`,
        [organization],
      );
      await s.rows(`insert into stripe.invoices (id, customer, status, total, created) values
          ('in_bs_1', 'cus_bs_plans', 'paid', 1000, 1), ('in_bs_2', 'cus_bs_plans', 'open', 500, 2),
          ('in_bs_x', 'cus_someone_else', 'open', 1, 3)`);
      const price = (
        plan: string,
        interval: string | null = null,
        variant: string | null = null,
      ) =>
        s.value<string | null>(
          "better_supabase.billing_plan_price($1, $2, $3)",
          [plan, interval, variant],
        );
      expect(await price("pro")).toBe("price_pro_m");
      expect(await price("pro", "year")).toBe("price_pro_y");
      expect(await price("old")).toBeNull();
      expect(await price("credits", null, "1000")).toBe("price_credits_1000");
      expect(await price("credits")).toBe("price_credits_base");
      expect(await price("credits", null, "9")).toBeNull();

      const billing = createBilling({
        stripe: { secretKey: "sk_test_unused" },
        transport: sqlTransport(s.sql),
      });
      await s.asRole(owner);
      const invoices = await billing.invoices(organization).orThrow();
      expect(invoices.map((row) => row["id"])).toEqual(["in_bs_2", "in_bs_1"]);
      await s.asRole(member);
      expect((await billing.invoices(organization)).ok).toBe(false);
      expect(await billing.allInvoices()).toMatchObject({
        error: { hint: "BILLING_FORBIDDEN" },
      });
      await s.service();
      const staff = await s.user("staff");
      await s.asRole(staff, { platform_permissions: ["billing.read"] });
      expect(
        (await billing.invoices(organization).orThrow()).map(
          (row) => row["id"],
        ),
      ).toEqual(["in_bs_2", "in_bs_1"]);
      const open = await billing.allInvoices({ status: "open" }).orThrow();
      expect(
        open
          .filter((entry) => entry.organizationId === organization)
          .map((entry) => entry.row["id"]),
      ).toEqual(["in_bs_2"]);
      expect(open.some((entry) => entry.row["id"] === "in_bs_x")).toBe(false);
      expect(
        (await billing.allInvoices({ before: 2, limit: 5 }).orThrow()).map(
          (entry) => entry.row["id"],
        ),
      ).toContain("in_bs_1");

      await s.service();
      await s.rows(`create table if not exists stripe.tax_ids (
          id text primary key, customer text, type text, value text, country text,
          verification jsonb, created bigint);
        insert into stripe.tax_ids (id, customer, type, value, country, verification, created) values
          ('txi_bs_1', 'cus_bs_plans', 'eu_vat', 'DE123456789', 'DE', '{"status": "verified"}', 1),
          ('txi_bs_2', 'cus_bs_plans', 'gb_vat', 'GB123456789', 'GB', null, 2),
          ('txi_bs_x', 'cus_someone_else', 'eu_vat', 'NL1', 'NL', null, 3)`);
      await s.asRole(owner);
      expect(
        await billing.taxIds(organization, { from: "sync" }).orThrow(),
      ).toEqual([
        {
          id: "txi_bs_2",
          type: "gb_vat",
          value: "GB123456789",
          country: "GB",
          verification: null,
          created: 2,
        },
        {
          id: "txi_bs_1",
          type: "eu_vat",
          value: "DE123456789",
          country: "DE",
          verification: { status: "verified" },
          created: 1,
        },
      ]);
      await s.asRole(member);
      expect(
        await billing.taxIds(organization, { from: "sync" }),
      ).toMatchObject({ error: { hint: "BILLING_FORBIDDEN" } });

      await s.service();
      for (const [table, columns] of [
        [
          "subscriptions",
          "id text primary key, customer text, status text, created bigint",
        ],
        [
          "subscription_items",
          "id text primary key, subscription text, price text, quantity integer, created bigint",
        ],
        ["prices", "id text primary key, unit_amount bigint, currency text"],
      ] as const) {
        if (
          !(await s.value<boolean>(
            `to_regclass('stripe.${table}') is not null`,
          ))
        )
          await s.rows(`create table stripe.${table} (${columns})`);
      }
      await s.rows(`insert into stripe.subscriptions (id, customer, status, created) values
          ('sub_bs_old', 'cus_bs_plans', 'canceled', 1), ('sub_bs_new', 'cus_bs_plans', 'active', 5);
        insert into stripe.subscription_items (id, subscription, price, quantity, created) values
          ('si_bs_new', 'sub_bs_new', 'price_pro_y', 3, 5);
        insert into stripe.prices (id, unit_amount, currency) values ('price_pro_y', 1200, 'eur')`);
      await s.rows(`alter table stripe.subscriptions add column if not exists current_period_start bigint;
        alter table stripe.prices add column if not exists recurring jsonb;
        alter table stripe.invoices add column if not exists amount_remaining bigint;
        alter table stripe.invoices add column if not exists hosted_invoice_url text;
        alter table stripe.invoices add column if not exists invoice_pdf text;
        alter table stripe.invoices add column if not exists customer_email text;
        alter table stripe.invoices add column if not exists status_transitions jsonb;
        alter table stripe.invoices add column if not exists customer_name text;
        alter table stripe.invoices add column if not exists updated_at timestamptz;
        alter table stripe.prices add column if not exists metadata jsonb;
        insert into stripe.customers (id, email, name, created)
          values ('cus_bs_plans', 'owner@example.com', 'Example Ltd', 1)
          on conflict (id) do update set email = excluded.email, name = excluded.name;
        update stripe.prices set metadata = '{"plan": "pro"}' where id = 'price_pro_y';
        update stripe.subscriptions set current_period_start = 4 where id = 'sub_bs_new';
        update stripe.prices set recurring = '{"interval": "year", "interval_count": 1}' where id = 'price_pro_y';
        update stripe.invoices set amount_remaining = 0, hosted_invoice_url = 'https://invoice.stripe.com/i/in_bs_1',
          invoice_pdf = 'https://pay.stripe.com/invoice/in_bs_1/pdf', customer_email = 'billing@example.com',
          status_transitions = '{"finalized_at": 6, "paid_at": 7}', updated_at = to_timestamp(8)
          where id = 'in_bs_1'`);
      await s.asRole(staff, { platform_permissions: ["billing.read"] });
      expect(
        await s.rows(
          `select s.subscription, s.customer_email, s.customer_name, s.status, s.price, s.price_metadata,
             s.plan, s.quantity, s.amount, s.currency,
             s.recurring_interval, s.current_period_start = to_timestamp(4) as period_start,
             s.created = to_timestamp(5) as created, s.cancel_at_period_end
           from better_supabase.billing_platform_subscriptions() s
           where s.tenant = $1`,
          [organization],
        ),
      ).toEqual([
        {
          subscription: "sub_bs_new",
          customer_email: "owner@example.com",
          customer_name: "Example Ltd",
          status: "active",
          price: "price_pro_y",
          price_metadata: { plan: "pro" },
          plan: "pro",
          quantity: "3",
          amount: "3600",
          currency: "eur",
          recurring_interval: "year",
          period_start: true,
          created: true,
          cancel_at_period_end: false,
        },
      ]);
      await s.service();
      expect(
        await s.rows(
          `select o.name, s.plan from better_supabase.billing_platform_subscriptions() s
           join better_supabase.organizations o on o.id = s.tenant
           where s.tenant = $1`,
          [organization],
        ),
      ).toEqual([{ name: expect.any(String), plan: "pro" }]);
      expect(
        await s.rows(
          `select i.invoice, i.amount_remaining, i.finalized_at = to_timestamp(6) as finalized,
             i.paid_at = to_timestamp(7) as paid, i.hosted_invoice_url, i.invoice_pdf, i.customer_email,
             i.customer_name, i.updated_at = to_timestamp(8) as updated
           from better_supabase.billing_platform_invoices() i
           where i.tenant = $1 order by i.invoice`,
          [organization],
        ),
      ).toEqual([
        {
          invoice: "in_bs_1",
          amount_remaining: "0",
          finalized: true,
          paid: true,
          hosted_invoice_url: "https://invoice.stripe.com/i/in_bs_1",
          invoice_pdf: "https://pay.stripe.com/invoice/in_bs_1/pdf",
          customer_email: "billing@example.com",
          customer_name: "Example Ltd",
          updated: true,
        },
        {
          invoice: "in_bs_2",
          amount_remaining: null,
          finalized: null,
          paid: null,
          hosted_invoice_url: null,
          invoice_pdf: null,
          customer_email: "owner@example.com",
          customer_name: "Example Ltd",
          updated: null,
        },
      ]);
      expect(
        await s.rows(
          `select i.status, count(*)::int as n, sum(i.total)::int as total
           from better_supabase.billing_platform_invoices() i
           where i.tenant = $1 group by i.status order by i.status`,
          [organization],
        ),
      ).toEqual([
        { status: "open", n: 1, total: 500 },
        { status: "paid", n: 1, total: 1000 },
      ]);
      await s.asRole(member);
      expect(
        await s.hint(
          "select * from better_supabase.billing_platform_invoices()",
        ),
      ).toBe("BILLING_FORBIDDEN");
    } finally {
      await s.close();
    }
  });

  it("reads a tenant's subscription for the app's definer functions only", async () => {
    const s = await BlockSession.open(pool);
    const fn = `public.bs_plan_of_${crypto.randomUUID().slice(0, 8)}`;
    try {
      await s.install(["organizations", "billing"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });
      await s.service();
      if (
        !(await s.value<boolean>(
          "to_regclass('stripe.subscription_items') is not null",
        ))
      ) {
        await s.rows(`create schema if not exists stripe;
          create table stripe.subscriptions (id text primary key, customer text, status text, created bigint);
          create table stripe.subscription_items (id text primary key, subscription text, price text, quantity integer, created bigint)`);
      }
      await s.rows(
        "select better_supabase.link_billing_customer($1, 'cus_bs_internal')",
        [organization],
      );
      await s.rows(`insert into stripe.subscriptions (id, customer, status, created) values ('sub_bs_internal', 'cus_bs_internal', 'active', 1);
        insert into stripe.subscription_items (id, subscription, price, quantity, created) values ('si_bs_internal', 'sub_bs_internal', 'price_team', 1, 1)`);
      await s.client.query(`
        create function ${fn}(tenant uuid) returns text
        language sql stable security definer set search_path = '' as $$
          select better_supabase.billing_tenant_subscription(tenant) -> 'items' -> 0 ->> 'price'
        $$;
        grant execute on function ${fn}(uuid) to authenticated;`);
      await s.asRole(member);
      expect(
        await s.hint("better_supabase.billing_subscription($1)", [
          organization,
        ]),
      ).toBe("BILLING_FORBIDDEN");
      expect(await s.value(`${fn}($1)`, [organization])).toBe("price_team");
      expect(
        await s.hint("better_supabase.billing_tenant_subscription($1)", [
          organization,
        ]),
      ).toMatch(/permission denied for function billing_tenant_subscription/);
      await s.service();
      await s.client.query("set local role service_role");
      expect(
        await s.hint("better_supabase.billing_tenant_subscription($1)", [
          organization,
        ]),
      ).toMatch(/permission denied/);
      await s.client.query("reset role");
      await s.asRole(owner);
      expect(
        await s.value("better_supabase.billing_subscription($1) ->> 'id'", [
          organization,
        ]),
      ).toBe("sub_bs_internal");
    } finally {
      await s.close();
    }
  });

  it("lists every linked customer for platform staff", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "billing"]);
      const owner = await s.user("owner");
      const first = await s.organization(owner);
      const second = await s.organization(owner);
      await s.service();
      if (
        !(await s.value<boolean>("to_regclass('stripe.customers') is not null"))
      ) {
        await s.rows(`create schema if not exists stripe;
          create table stripe.customers (id text primary key, email text, name text, created bigint)`);
      }
      await s.rows(
        `select better_supabase.link_billing_customer($1, 'cus_bs_list_1'), better_supabase.link_billing_customer($2, 'cus_bs_list_2')`,
        [first, second],
      );
      await s.rows(
        "insert into stripe.customers (id, email, name, created) values ('cus_bs_list_1', 'billing@first.test', 'First', 1767225600)",
      );
      const billing = createBilling({
        stripe: { secretKey: "sk_test_unused" },
        transport: sqlTransport(s.sql),
      });
      await s.asRole(owner);
      expect(await billing.allCustomers()).toMatchObject({
        error: { hint: "BILLING_FORBIDDEN" },
      });
      await s.service();
      const staff = await s.user("staff");
      await s.asRole(staff, { platform_permissions: ["billing.read"] });
      const listed = (await billing.allCustomers().orThrow()).filter(
        (entry) =>
          entry.organizationId === first || entry.organizationId === second,
      );
      expect(
        listed.map((entry) => ({
          ...entry,
          created: entry.created?.toString(),
        })),
      ).toEqual(
        [
          {
            organizationId: first,
            customerId: "cus_bs_list_1",
            email: "billing@first.test",
            name: "First",
            created: "2026-01-01T00:00:00Z",
          },
          {
            organizationId: second,
            customerId: "cus_bs_list_2",
            email: undefined,
            name: undefined,
            created: undefined,
          },
        ].sort((a, b) => a.organizationId.localeCompare(b.organizationId)),
      );
      const rows = await s.rows<Record<string, unknown>>(
        "select tenant::text, customer, email from better_supabase.billing_platform_customers() where tenant = any ($1::uuid[]) order by customer",
        [[first, second]],
      );
      expect(rows).toEqual([
        {
          tenant: first,
          customer: "cus_bs_list_1",
          email: "billing@first.test",
        },
        { tenant: second, customer: "cus_bs_list_2", email: null },
      ]);
    } finally {
      await s.close();
    }
  });
});
