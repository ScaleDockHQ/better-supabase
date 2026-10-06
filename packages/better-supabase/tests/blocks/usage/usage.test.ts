import { describe, expect, it } from "vitest";

import type {
  BlockTransport,
  StripeClient,
} from "../../../src/blocks/usage/index.ts";

import {
  createUsage,
  reportUsageToStripe,
} from "../../../src/blocks/usage/index.ts";
import { rawError } from "../../../src/core/block-transport.ts";

function fakeTransport(
  answer: (fn: string, args: Record<string, unknown>) => unknown,
) {
  const calls: [string, string, Record<string, unknown>][] = [];
  const transport: BlockTransport = {
    async call(schemaName, fn, args) {
      calls.push([schemaName, fn, { ...args }]);
      return answer(fn, { ...args });
    },
  };
  return { transport, calls };
}

describe("createUsage", () => {
  it("records and consumes with defaults and idempotency keys", async () => {
    const { transport, calls } = fakeTransport(() => ({
      recorded: true,
      used: "4",
    }));
    const usage = createUsage({ transport, schema: "app" });
    expect(await usage.record("org", "api_calls").orThrow()).toEqual({
      recorded: true,
      today: 4,
    });
    await usage
      .consume("org", "seats", { quantity: 2, idempotencyKey: "k" })
      .orThrow();
    expect(calls).toEqual([
      [
        "app",
        "record_usage",
        { tenant: "org", meter: "api_calls", quantity: 1 },
      ],
      [
        "app",
        "consume_quota",
        { tenant: "org", meter: "seats", quantity: 2, idempotency_key: "k" },
      ],
    ]);
  });

  it("reads the status with and without a quota", async () => {
    let limit: number | null = 10;
    const { transport } = fakeTransport(() => ({
      meter: "api_calls",
      used: 4,
      limit,
      remaining: limit === null ? null : limit - 4,
      period: "week",
      resets_at: "2026-10-12T00:00:00+00:00",
    }));
    const usage = createUsage({ transport });
    const status = await usage.current("org", "api_calls").orThrow();
    expect(status).toMatchObject({
      used: 4,
      limit: 10,
      remaining: 6,
      period: "week",
    });
    expect(status.resetsAt.toString()).toBe("2026-10-12T00:00:00Z");
    limit = null;
    expect(await usage.remaining("org", "api_calls").orThrow()).toBe(undefined);
  });

  it("reads billing periods, catalog fields and the meter catalog", async () => {
    const { transport } = fakeTransport((fn) =>
      fn === "usage_meters"
        ? { "ai.tokens": { unit: "tokens", category: "ai" }, bare: null }
        : {
            meter: "ai.tokens",
            used: 1,
            limit: null,
            remaining: null,
            period: "billing",
            starts_at: "2026-10-01T09:30:00+00:00",
            resets_at: "2026-11-01T09:30:00+00:00",
            unit: "tokens",
            label: "AI tokens",
          },
    );
    const usage = createUsage({ transport });
    const status = await usage.current("org", "ai.tokens").orThrow();
    expect(status).toMatchObject({
      period: "billing",
      unit: "tokens",
      label: "AI tokens",
    });
    expect(status.startsAt?.toString()).toBe("2026-10-01T09:30:00Z");
    expect(status).not.toHaveProperty("category");
    expect(await usage.meters().orThrow()).toEqual({
      "ai.tokens": { unit: "tokens", category: "ai" },
      bare: {},
    });
  });

  it("falls back to month for an unknown period", async () => {
    const { transport } = fakeTransport(() => ({
      meter: "m",
      used: 0,
      period: "decade",
      resets_at: "2026-11-01T00:00:00Z",
    }));
    const status = await createUsage({ transport }).current("o", "m").orThrow();
    expect(status.period).toBe("month");
  });

  it("maps a quota error from pg, whose field is detail", async () => {
    const transport: BlockTransport = {
      call: () =>
        Promise.reject(
          Object.assign(new Error("Quota for m exceeded"), {
            code: "BSQ29",
            detail: '{"meter":"m","limit":1,"retry_after":5}',
          }),
        ),
    };
    expect(await createUsage({ transport }).consume("o", "m")).toMatchObject({
      ok: false,
      error: { kind: "quota_exceeded", meter: "m", limit: 1, retryAfter: 5 },
    });
    expect(rawError({ code: "X", details: "a", detail: "b" })).toEqual({
      code: "X",
      details: "a",
    });
  });
});

describe("reportUsageToStripe", () => {
  const rows = [
    {
      organization_id: "org-1",
      meter: "api_calls",
      day: "2026-10-05",
      value: 10,
      reported_value: 4,
    },
    {
      organization_id: "org-2",
      meter: "api_calls",
      day: "2026-10-05",
      value: 1,
      reported_value: 0,
    },
    {
      organization_id: "org-1",
      meter: "internal",
      day: "2026-10-05",
      value: 3,
      reported_value: 0,
    },
  ];

  it("sends each delta once per total and marks it reported", async () => {
    const { transport, calls } = fakeTransport((fn, args) => {
      if (fn === "unreported_usage") return rows;
      if (fn === "tenant_stripe_customer")
        return args["tenant"] === "org-1" ? "cus_1" : null;
      return true;
    });
    const sent: unknown[] = [];
    const stripe = {
      billing: {
        meterEvents: {
          create: async (params: unknown, options: unknown) => {
            sent.push([params, options]);
            return {};
          },
        },
      },
    } as unknown as StripeClient;
    const result = await reportUsageToStripe({
      transport,
      stripe,
      batch: 10,
      eventName: (meter) => (meter === "internal" ? undefined : `bs_${meter}`),
    });
    expect(result).toEqual({ reported: 1, skipped: 2 });
    expect(sent).toEqual([
      [
        {
          event_name: "bs_api_calls",
          payload: { stripe_customer_id: "cus_1", value: "6" },
          identifier: "org-1:api_calls:2026-10-05:10",
          timestamp: Date.parse("2026-10-05T23:59:59Z") / 1000,
        },
        { idempotencyKey: "org-1:api_calls:2026-10-05:10" },
      ],
    ]);
    expect(calls.map(([, fn]) => fn)).toEqual([
      "unreported_usage",
      "tenant_stripe_customer",
      "mark_usage_reported",
      "tenant_stripe_customer",
    ]);
    expect(calls[0]?.[2]).toEqual({ max_rows: 10 });
    expect(calls[2]?.[2]).toEqual({
      tenant: "org-1",
      meter: "api_calls",
      day: "2026-10-05",
      value: 10,
    });
  });
});
