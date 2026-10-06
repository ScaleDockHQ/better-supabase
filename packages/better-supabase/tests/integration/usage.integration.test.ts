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
      ).toEqual({ recorded: true, today: 1 });
      expect(
        await usage
          .record(organization, "api_calls", { idempotencyKey: "a" })
          .orThrow(),
      ).toEqual({ recorded: false, today: 1 });
      expect(
        await usage
          .consume(organization, "api_calls", { quantity: 2 })
          .orThrow(),
      ).toEqual({ recorded: true, today: 3 });

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

      await s.asRole(outsider);
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
      expect(await report()).toEqual({ reported: 1, skipped: 0 });
      expect(sent).toMatchObject([
        {
          params: {
            event_name: "api_calls",
            payload: { stripe_customer_id: "cus_1", value: "3" },
          },
        },
      ]);
      expect(await report()).toEqual({ reported: 0, skipped: 0 });
    } finally {
      await s.close();
    }
  });
});
