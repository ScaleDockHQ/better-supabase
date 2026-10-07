import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { StripeClient } from "../../src/blocks/usage/index.ts";

import {
  createUsage,
  reportUsageToStripe,
  sqlTransport,
} from "../../src/blocks/usage/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("usage", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("meters idempotently, enforces quotas and reports to Stripe", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "usage"]);
      await s.clear(["better_supabase.usage_counters"]);
      const owner = await s.user("owner");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner);
      const usage = createUsage({ transport: sqlTransport(s.sql) });

      await s.service();
      await s.rows(
        `insert into better_supabase.usage_quotas (plan, meter, "limit", period)
         values ('*', 'api_calls', 3, 'month')`,
      );

      await s.asRole(owner);
      expect(
        await usage
          .record(organization, "api_calls", { idempotencyKey: "a" })
          .orThrow(),
      ).toEqual({ recorded: true, today: 1, used: 1 });
      expect(
        await usage
          .record(organization, "api_calls", { idempotencyKey: "a" })
          .orThrow(),
      ).toEqual({ recorded: false, today: 1, used: 1 });
      expect(
        await usage
          .consume(organization, "api_calls", { quantity: 2 })
          .orThrow(),
      ).toEqual({ recorded: true, today: 3, used: 3 });

      const over = await usage.consume(organization, "api_calls");
      expect(over).toMatchObject({
        ok: false,
        error: {
          kind: "quota_exceeded",
          status: 429,
          meter: "api_calls",
          limit: 3,
          hint: "QUOTA_EXCEEDED",
          retryAfter: expect.any(Number),
        },
      });

      const status = await usage.current(organization, "api_calls").orThrow();
      expect(status).toMatchObject({
        used: 3,
        limit: 3,
        remaining: 0,
        period: "month",
      });
      expect(status.resetsAt.epochMilliseconds).toBeGreaterThan(Date.now());
      expect(
        await s.value(
          `better_supabase.within_quota('${organization}', 'api_calls')`,
        ),
      ).toBe(false);
      expect(await usage.remaining(organization, "storage").orThrow()).toBe(
        undefined,
      );

      // A tenant quota overrides the plan quota.
      await s.service();
      await s.rows(
        `insert into better_supabase.usage_quotas (organization_id, meter, "limit", period)
         values ('${organization}', 'api_calls', 10, 'day')`,
      );
      await s.asRole(owner);
      expect(await usage.remaining(organization, "api_calls").orThrow()).toBe(
        7,
      );

      await s.service();
      await s.rows(
        `insert into better_supabase.usage_quotas (plan, meter, "limit", period)
         values ('*', 'seats', 2, 'month');
         insert into better_supabase.usage_quotas (organization_id, meter, "limit", period)
         values ('${organization}', 'seats', null, 'year')`,
      );
      await s.asRole(owner);
      expect(
        await usage.consume(organization, "seats", { quantity: 5 }).orThrow(),
      ).toEqual({ recorded: true, today: 5, used: 5 });
      expect(
        await usage.current(organization, "seats").orThrow(),
      ).toMatchObject({
        used: 5,
        limit: undefined,
        remaining: undefined,
        unlimited: true,
        period: "year",
      });
      expect(
        await s.value(
          `better_supabase.within_quota('${organization}', 'seats', 1000)`,
        ),
      ).toBe(true);
      expect(
        (await usage.current(organization, "storage").orThrow()).unlimited,
      ).toBe(false);
      expect(
        (await usage.overview(organization).orThrow()).map((status) => [
          status.meter,
          status.used,
          status.limit,
          status.unlimited,
        ]),
      ).toEqual([
        ["api_calls", 3, 10, false],
        ["seats", 5, undefined, true],
      ]);

      await s.asRole(outsider);
      expect(await usage.overview(organization)).toMatchObject({
        ok: false,
        error: { kind: "forbidden", hint: "USAGE_FORBIDDEN" },
      });
      expect(await usage.record(organization, "api_calls")).toMatchObject({
        ok: false,
        error: { kind: "forbidden", hint: "USAGE_FORBIDDEN" },
      });

      await s.service();
      const sent: unknown[] = [];
      const stripe = {
        billing: {
          meterEvents: {
            create: async (params: unknown, options: unknown) => {
              sent.push({ params, options });
              return {};
            },
          },
        },
      } as unknown as StripeClient;
      const report = () =>
        reportUsageToStripe({
          transport: sqlTransport(s.sql),
          stripe,
          customer: async (id) => (id === organization ? "cus_1" : undefined),
        });
      expect(await report()).toEqual({ reported: 2, skipped: 0 });
      expect(sent).toMatchObject([
        {
          params: {
            event_name: "api_calls",
            payload: { stripe_customer_id: "cus_1", value: "3" },
          },
        },
        { params: { event_name: "seats", payload: { value: "5" } } },
      ]);
      expect(await report()).toEqual({ reported: 0, skipped: 0 });
    } finally {
      await s.close();
    }
  });

  it("keeps a tenant's usage and quota from members without usage.read and from outsiders", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "usage"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { member });
      const usage = createUsage({ transport: sqlTransport(s.sql) });
      await s.service();
      await s.rows(
        `insert into better_supabase.usage_quotas (plan, meter, "limit", period)
         values ('*', 'projects', 5, 'month')`,
      );
      await usage.record(organization, "projects", { quantity: 3 }).orThrow();
      const fits = (quantity: number) =>
        s.value<boolean>(
          `better_supabase.within_quota('${organization}', 'projects', ${quantity})`,
        );

      await s.asRole(outsider);
      expect(await fits(1)).toBe(false);
      expect(await fits(0)).toBe(false);

      await s.asRole(member);
      expect(await fits(2)).toBe(true);
      expect(await fits(3)).toBe(false);
      for (const result of [
        await usage.current(organization, "projects"),
        await usage.overview(organization),
      ]) {
        expect(result).toMatchObject({
          ok: false,
          error: { kind: "forbidden", hint: "USAGE_FORBIDDEN" },
        });
      }

      await s.asRole(owner);
      expect(
        await usage.current(organization, "projects").orThrow(),
      ).toMatchObject({ used: 3, limit: 5, remaining: 2 });
    } finally {
      await s.close();
    }
  });

  it("reports past counters it can't send without waiting for them", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "usage"]);
      await s.clear(["better_supabase.usage_counters"]);
      const owner = await s.user("owner");
      const billed = await s.organization(owner);
      const unbilled = await s.organization(owner);
      await s.service();
      await s.rows(
        `insert into better_supabase.usage_counters (organization_id, meter, day, value)
         values ($1, 'internal', current_date - 3, 5),
                ($2, 'api_calls', current_date - 2, 4),
                ($1, 'api_calls', current_date - 1, 2)`,
        [billed, unbilled],
      );
      const sent: unknown[] = [];
      const stripe = {
        billing: {
          meterEvents: {
            create: async (params: unknown) => {
              sent.push(params);
              return {};
            },
          },
        },
      } as unknown as StripeClient;
      const report = () =>
        reportUsageToStripe({
          transport: sqlTransport(s.sql),
          stripe,
          batch: 1,
          eventName: (meter) => (meter === "internal" ? undefined : meter),
          customer: async (id) => (id === billed ? "cus_1" : undefined),
        });
      expect(await report()).toEqual({ reported: 1, skipped: 2 });
      expect(sent).toMatchObject([
        { event_name: "api_calls", payload: { value: "2" } },
      ]);
      expect(await report()).toEqual({ reported: 0, skipped: 2 });
      expect(
        await s.rows(
          "select meter, reported_value::text as reported from better_supabase.usage_counters where organization_id = any($1) order by day",
          [[billed, unbilled]],
        ),
      ).toEqual([
        { meter: "internal", reported: "0" },
        { meter: "api_calls", reported: "0" },
        { meter: "api_calls", reported: "2" },
      ]);
    } finally {
      await s.close();
    }
  });

  it("keeps who and what used a meter with options.history", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "usage"], {
        modules: { usage: { options: { history: true } } },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });
      const usage = createUsage({ transport: sqlTransport(s.sql) });
      await s.asRole(member);
      await s.rows("savepoint member");
      expect(await usage.record(organization, "tokens")).toMatchObject({
        error: { kind: "forbidden", hint: "USAGE_FORBIDDEN" },
      });
      await s.rows("rollback to savepoint member");
      await s.service();
      await usage
        .record(organization, "tokens", {
          quantity: 2,
          source: "feature:summary",
          metadata: { doc: "d1" },
          actor: member.id,
        })
        .orThrow();
      await usage
        .consume(organization, "tokens", { quantity: 3, actor: owner.id })
        .orThrow();
      await s.asRole(owner);
      const history = await usage.history(organization).orThrow();
      expect(
        history.map((entry) => [entry.quantity, entry.actor, entry.source]),
      ).toEqual([
        [3, owner.id, undefined],
        [2, member.id, "feature:summary"],
      ]);
      expect(history[1]!.metadata).toEqual({ doc: "d1" });
      expect(
        await usage.history(organization, { before: history[0]!.id }).orThrow(),
      ).toHaveLength(1);
      expect(
        (await usage.breakdown(organization, "tokens").orThrow()).map(
          (entry) => [entry.actor, entry.quantity],
        ),
      ).toEqual([
        [owner.id, 3],
        [member.id, 2],
      ]);
      await s.asRole(member);
      expect(await usage.history(organization)).toMatchObject({
        error: { hint: "USAGE_FORBIDDEN" },
      });
    } finally {
      await s.close();
    }
  });

  it("records several meters at once, all or none", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "usage"]);
      const owner = await s.user("owner");
      const organization = await s.organization(owner);
      const usage = createUsage({ transport: sqlTransport(s.sql) });
      await s.service();
      await s.rows(
        `insert into better_supabase.usage_quotas (plan, meter, "limit", period)
         values ('*', 'output_tokens', 10, 'month')`,
      );
      await s.asRole(owner);
      const entries = [
        { meter: "input_tokens", quantity: 40 },
        { meter: "output_tokens", quantity: 6 },
      ];
      expect(
        await usage
          .consumeMany(organization, entries, { idempotencyKey: "call-1" })
          .orThrow(),
      ).toEqual({
        recorded: true,
        today: { input_tokens: 40, output_tokens: 6 },
        used: { input_tokens: 40, output_tokens: 6 },
      });
      expect(
        await usage
          .consumeMany(organization, entries, { idempotencyKey: "call-1" })
          .orThrow(),
      ).toMatchObject({ recorded: false });
      await s.rows("savepoint batch");
      expect(
        await usage.consumeMany(organization, entries, {
          idempotencyKey: "call-2",
        }),
      ).toMatchObject({ error: { kind: "quota_exceeded" } });
      await s.rows("rollback to savepoint batch");
      expect(
        (await usage.current(organization, "input_tokens").orThrow()).used,
      ).toBe(40);
      expect(
        await usage
          .recordMany(organization, [{ meter: "output_tokens", quantity: 50 }])
          .orThrow(),
      ).toEqual({
        recorded: true,
        today: { output_tokens: 56 },
        used: { output_tokens: 56 },
      });
      await s.rows("savepoint empty");
      expect(await usage.recordMany(organization, [])).toMatchObject({
        error: { hint: "USAGE_ENTRIES" },
      });
      await s.rows("rollback to savepoint empty");
    } finally {
      await s.close();
    }
  });

  it("reads the meter catalog from the app's table", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.rows(
        `create table public.bs_test_meters (
           slug text primary key, unit_name text, live boolean not null default true
         );
         insert into public.bs_test_meters values
           ('tokens', 'tokens', true), ('legacy', 'calls', false);`,
      );
      await s.install(["organizations", "usage"], {
        modules: {
          usage: {
            options: {
              meters: {
                table: "bs_test_meters",
                key: "slug",
                unit: "unit_name",
                active: "live",
              },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const organization = await s.organization(owner);
      const usage = createUsage({ transport: sqlTransport(s.sql) });
      await s.asRole(owner);
      expect(await usage.meters().orThrow()).toEqual({
        tokens: { unit: "tokens" },
      });
      expect(
        (await usage.record(organization, "tokens").orThrow()).recorded,
      ).toBe(true);
      await s.rows("savepoint meters");
      expect(await usage.record(organization, "legacy")).toMatchObject({
        error: { hint: "USAGE_METER_UNKNOWN" },
      });
      await s.rows("rollback to savepoint meters");
      await s.service();
      await s.rows(
        "insert into public.bs_test_meters values ('storage', 'GB', true)",
      );
      await s.asRole(owner);
      expect(
        (await usage.record(organization, "storage").orThrow()).recorded,
      ).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("counts fractional quantities against fractional quotas", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "usage"]);
      const owner = await s.user("owner");
      const organization = await s.organization(owner);
      const usage = createUsage({ transport: sqlTransport(s.sql) });
      await s.service();
      await s.rows(
        `insert into better_supabase.usage_quotas (plan, meter, "limit", period)
         values ('*', 'gb_hours', 2.5, 'month')`,
      );
      await s.asRole(owner);
      expect(
        await usage
          .record(organization, "gb_hours", { quantity: 1.25 })
          .orThrow(),
      ).toEqual({ recorded: true, today: 1.25, used: 1.25 });
      expect(
        await usage
          .consume(organization, "gb_hours", { quantity: 1.2 })
          .orThrow(),
      ).toEqual({ recorded: true, today: 2.45, used: 2.45 });
      expect(
        await usage.consume(organization, "gb_hours", { quantity: 0.1 }),
      ).toMatchObject({ error: { kind: "quota_exceeded", limit: 2.5 } });
      expect(
        await usage.current(organization, "gb_hours").orThrow(),
      ).toMatchObject({ used: 2.45, limit: 2.5, remaining: 0.05 });
      await s.service();
      await s.rows(
        `insert into better_supabase.usage_counters (organization_id, meter, day, value)
         values ($1, 'gb_hours', (now() at time zone 'utc')::date - 1, 0.5)
         on conflict do nothing`,
        [organization],
      );
      const rows = await s.value<Record<string, unknown>[]>(
        "better_supabase.unreported_usage(1000)",
      );
      const today = rows.filter(
        (row) =>
          row["organization_id"] === organization &&
          row["meter"] === "gb_hours",
      );
      expect(today.at(-1)).toMatchObject({ included: 2.5, value: 2.45 });
      const earlier = new Date().getUTCDate() === 1 ? 0 : 0.5;
      expect(today.at(-1)!["window_before"]).toBe(earlier);
    } finally {
      await s.close();
    }
  });

  it("counts a day of the previous billing period within that period's window", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.rows(
        `create or replace function public.usage_billing_period(tenant uuid)
         returns table (starts_at timestamptz, ends_at timestamptz)
         language sql stable as $$
           select (((now() at time zone 'utc')::date - 2)::timestamp at time zone 'utc'),
             (((now() at time zone 'utc')::date - 2)::timestamp at time zone 'utc') + interval '1 month'
         $$;`,
      );
      await s.install(["organizations", "usage"]);
      const owner = await s.user("owner");
      const organization = await s.organization(owner);
      await s.service();
      await s.rows(
        `insert into better_supabase.usage_quotas (plan, meter, "limit", period)
         values ('*', 'seats.hours', 1000, 'billing')`,
      );
      await s.rows(
        `insert into better_supabase.usage_counters (organization_id, meter, day, value)
         values ($1, 'seats.hours', (now() at time zone 'utc')::date - 40, 900),
                ($1, 'seats.hours', (now() at time zone 'utc')::date - 10, 700),
                ($1, 'seats.hours', (now() at time zone 'utc')::date - 3, 400),
                ($1, 'seats.hours', (now() at time zone 'utc')::date - 2, 100),
                ($1, 'seats.hours', (now() at time zone 'utc')::date - 1, 50)`,
        [organization],
      );
      const rows = await s.value<Record<string, unknown>[]>(
        "better_supabase.unreported_usage(1000)",
      );
      const before = Object.fromEntries(
        rows
          .filter(
            (row) =>
              row["organization_id"] === organization &&
              row["meter"] === "seats.hours",
          )
          .map((row) => [Number(row["value"]), Number(row["window_before"])]),
      );
      expect(before).toEqual({
        // The previous period started a month before the current one.
        400: 700,
        700: 0,
        // The current period started two days ago.
        100: 0,
        50: 100,
        // The period before the previous one.
        900: 0,
      });
    } finally {
      await s.close();
    }
  });

  it("resets billing quotas with the app's period and refuses meters outside the catalog", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.rows(
        `create or replace function public.usage_billing_period(tenant uuid)
         returns table (starts_at timestamptz, ends_at timestamptz)
         language sql stable as $$
           select now() - interval '3 days', now() + interval '4 days'
         $$;`,
      );
      await s.install(["organizations", "usage"], {
        modules: {
          usage: {
            options: {
              meters: {
                "ai.tokens": {
                  unit: "tokens",
                  category: "ai",
                  label: "AI tokens",
                },
              },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const organization = await s.organization(owner);
      const usage = createUsage({ transport: sqlTransport(s.sql) });
      await s.service();
      await s.rows(
        `insert into better_supabase.usage_quotas (plan, meter, "limit", period)
         values ('*', 'ai.tokens', 1000, 'billing')`,
      );
      await s.rows(
        `insert into better_supabase.usage_counters (organization_id, meter, day, value)
         values ($1, 'ai.tokens', (now() at time zone 'utc')::date - 2, 300),
                ($1, 'ai.tokens', (now() at time zone 'utc')::date - 5, 500)`,
        [organization],
      );
      await s.asRole(owner);
      await usage
        .consume(organization, "ai.tokens", { quantity: 250 })
        .orThrow();
      const status = await usage.current(organization, "ai.tokens").orThrow();
      expect(status).toMatchObject({
        used: 550,
        limit: 1000,
        remaining: 450,
        period: "billing",
        unit: "tokens",
        category: "ai",
        label: "AI tokens",
      });
      const days =
        (status.resetsAt.epochMilliseconds - Date.now()) / 86_400_000;
      expect(days).toBeGreaterThan(3.9);
      expect(days).toBeLessThan(4.1);
      expect(status.startsAt).toBeDefined();
      const over = await usage.consume(organization, "ai.tokens", {
        quantity: 500,
      });
      expect(over.ok ? undefined : over.error).toMatchObject({
        kind: "quota_exceeded",
      });
      const unknown = await usage.record(organization, "api.calls");
      expect(unknown.ok ? undefined : unknown.error.hint).toBe(
        "USAGE_METER_UNKNOWN",
      );
      expect(await usage.meters().orThrow()).toEqual({
        "ai.tokens": { unit: "tokens", category: "ai", label: "AI tokens" },
      });
    } finally {
      await s.close();
    }
  });
});
