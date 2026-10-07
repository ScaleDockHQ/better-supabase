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

describe("batches", () => {
  it("sends the entries as JSON with the check flag and maps today's usage", async () => {
    const { transport, calls } = fakeTransport(() => ({
      recorded: true,
      used: { a: "1.5", b: 2 },
    }));
    const usage = createUsage({ transport });
    expect(
      await usage
        .consumeMany("org", [{ meter: "a", quantity: 1.5 }, { meter: "b" }], {
          idempotencyKey: "k",
          source: "s",
        })
        .orThrow(),
    ).toEqual({ recorded: true, today: { a: 1.5, b: 2 } });
    expect(calls[0]![2]).toMatchObject({
      tenant: "org",
      entries: '[{"meter":"a","quantity":1.5},{"meter":"b","quantity":1}]',
      idempotency_key: "k",
      check: true,
      source: "s",
    });
    await usage.recordMany("org", [{ meter: "a" }]).orThrow();
    expect(calls[1]![2]).toMatchObject({ check: false });
    expect(
      await createUsage(fakeTransport(() => ({ recorded: false })))
        .recordMany("org", [{ meter: "a" }])
        .orThrow(),
    ).toEqual({ recorded: false, today: {} });
  });
});

describe("usage history", () => {
  it("passes who and what used it, and reads the history and breakdown", async () => {
    const { transport, calls } = fakeTransport((fn) => {
      if (fn === "usage_history")
        return [
          {
            id: "7",
            meter: "tokens",
            quantity: "1.5",
            actor: "u1",
            source: "feature:summary",
            metadata: { doc: "d1" },
            recorded_at: "2026-01-01T00:00:00Z",
          },
          {
            id: 6,
            meter: "tokens",
            quantity: 2,
            actor: null,
            source: null,
            metadata: null,
            recorded_at: "2026-01-01T00:00:00Z",
          },
        ];
      if (fn === "usage_breakdown")
        return [{ actor: "u1", source: null, quantity: "3.5" }];
      return { recorded: true, used: 1 };
    });
    const usage = createUsage({ transport });
    await usage
      .record("org", "tokens", {
        quantity: 1.5,
        source: "feature:summary",
        metadata: { doc: "d1" },
        actor: "u1",
      })
      .orThrow();
    expect(calls[0]![2]).toEqual({
      tenant: "org",
      meter: "tokens",
      quantity: 1.5,
      idempotency_key: undefined,
      source: "feature:summary",
      metadata: { doc: "d1" },
      actor: "u1",
    });
    const [first, second] = await usage
      .history("org", { meter: "tokens", limit: 2, before: 9 })
      .orThrow();
    expect(calls[1]![2]).toEqual({
      tenant: "org",
      meter: "tokens",
      max_rows: 2,
      before_id: 9,
    });
    expect(first).toMatchObject({
      id: 7,
      quantity: 1.5,
      actor: "u1",
      source: "feature:summary",
      metadata: { doc: "d1" },
    });
    expect(first!.recordedAt.toString()).toBe("2026-01-01T00:00:00Z");
    expect(second).toMatchObject({
      actor: undefined,
      source: undefined,
      metadata: {},
    });
    await usage.history("org").orThrow();
    expect(calls[2]![2]).toMatchObject({ max_rows: 100 });
    expect(await usage.breakdown("org", "tokens").orThrow()).toEqual([
      { actor: "u1", source: undefined, quantity: 3.5 },
    ]);
    const empty = createUsage(fakeTransport(() => null));
    expect(await empty.history("org").orThrow()).toEqual([]);
    expect(await empty.breakdown("org", "x").orThrow()).toEqual([]);
  });
});

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
      unlimited: limit === null,
      period: "week",
      resets_at: "2026-10-12T00:00:00+00:00",
    }));
    const usage = createUsage({ transport });
    const status = await usage.current("org", "api_calls").orThrow();
    expect(status).toMatchObject({
      used: 4,
      limit: 10,
      remaining: 6,
      unlimited: false,
      period: "week",
    });
    expect(status.resetsAt.toString()).toBe("2026-10-12T00:00:00Z");
    limit = null;
    expect(await usage.remaining("org", "api_calls").orThrow()).toBe(undefined);
    expect(await usage.current("org", "api_calls").orThrow()).toMatchObject({
      limit: undefined,
      unlimited: true,
    });
  });

  it("reads every meter's status in one call", async () => {
    const { transport, calls } = fakeTransport(() => [
      {
        meter: "api_calls",
        used: 4,
        limit: 10,
        remaining: 6,
        unlimited: false,
        period: "month",
        resets_at: "2026-11-01T00:00:00+00:00",
      },
      {
        meter: "seats",
        used: 2,
        limit: null,
        remaining: null,
        unlimited: true,
        period: "year",
        resets_at: "2027-01-01T00:00:00+00:00",
        unit: "seats",
      },
    ]);
    const overview = await createUsage({ transport }).overview("org").orThrow();
    expect(calls).toEqual([
      ["better_supabase", "usage_overview", { tenant: "org" }],
    ]);
    expect(
      overview.map((status) => [
        status.meter,
        status.remaining,
        status.unlimited,
      ]),
    ).toEqual([
      ["api_calls", 6, false],
      ["seats", undefined, true],
    ]);
    expect(overview[1]).toMatchObject({ unit: "seats", period: "year" });
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

  it("sends only the overage above the quota with overage", async () => {
    const counter = (
      day: string,
      value: number,
      reported: number,
      before: number,
      included: number | null = 100,
    ) => ({
      organization_id: "org-1",
      meter: "api_calls",
      day,
      value,
      reported_value: reported,
      included,
      window_before: before,
    });
    const { transport, calls } = fakeTransport((fn) => {
      if (fn === "unreported_usage")
        return [
          counter("2026-10-01", 60, 0, 0),
          counter("2026-10-02", 70, 0, 60),
          counter("2026-10-03", 20, 10, 130),
          counter("2026-10-04", 5, 0, 0, null),
          { ...counter("2026-10-05", 7, 0, 0, null), unlimited: true },
        ];
      if (fn === "tenant_stripe_customer") return "cus_1";
      return true;
    });
    const sent: string[] = [];
    const stripe = {
      billing: {
        meterEvents: {
          create: async (params: { payload: { value: string } }) => {
            sent.push(params.payload.value);
            return {};
          },
        },
      },
    } as unknown as StripeClient;
    expect(
      await reportUsageToStripe({ transport, stripe, overage: true }),
    ).toEqual({ reported: 3, skipped: 0 });
    expect(sent).toEqual(["30", "10", "5"]);
    expect(calls.filter(([, fn]) => fn === "mark_usage_reported")).toHaveLength(
      5,
    );
  });

  function counterStore(counters: readonly Record<string, unknown>[]) {
    const marked = new Set<string>();
    const keyOf = (row: Record<string, unknown>) =>
      `${String(row["organization_id"] ?? row["tenant"])}:${String(row["meter"])}:${String(row["day"])}`;
    return (fn: string, args: Record<string, unknown>) => {
      if (fn === "unreported_usage") {
        const meters = (args["skip_meters"] ?? []) as string[];
        const tenants = (args["skip_tenants"] ?? []) as string[];
        return counters
          .filter(
            (row) =>
              !marked.has(keyOf(row)) &&
              !meters.includes(String(row["meter"])) &&
              !tenants.includes(String(row["organization_id"])),
          )
          .slice(0, Number(args["max_rows"]));
      }
      if (fn === "mark_usage_reported") marked.add(keyOf(args));
      return true;
    };
  }

  const recordingStripe = (sent: unknown[]) =>
    ({
      billing: {
        meterEvents: {
          create: async (params: unknown, options: unknown) => {
            sent.push([params, options]);
            return {};
          },
        },
      },
    }) as unknown as StripeClient;

  it("sends each delta once per total and marks it reported", async () => {
    const counters = counterStore(rows);
    const { transport, calls } = fakeTransport((fn, args) => {
      if (fn === "tenant_stripe_customer")
        return args["tenant"] === "org-1" ? "cus_1" : null;
      return counters(fn, args);
    });
    const sent: unknown[] = [];
    const result = await reportUsageToStripe({
      transport,
      stripe: recordingStripe(sent),
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
      "unreported_usage",
    ]);
    expect(calls[0]?.[2]).toEqual({
      max_rows: 10,
      skip_meters: [],
      skip_tenants: [],
    });
    expect(calls[2]?.[2]).toEqual({
      tenant: "org-1",
      meter: "api_calls",
      day: "2026-10-05",
      value: 10,
    });
    expect(calls[4]?.[2]).toEqual({
      max_rows: 9,
      skip_meters: ["internal"],
      skip_tenants: ["org-2"],
    });
  });

  it("passes over meters without an event name and tenants without a customer", async () => {
    const counter = (organizationId: string, meter: string, day: string) => ({
      organization_id: organizationId,
      meter,
      day,
      value: 2,
      reported_value: 0,
    });
    const counters = counterStore([
      counter("org-1", "internal", "2026-10-01"),
      counter("org-2", "api_calls", "2026-10-01"),
      counter("org-1", "internal", "2026-10-02"),
      counter("org-2", "api_calls", "2026-10-02"),
      counter("org-1", "api_calls", "2026-10-03"),
      counter("org-3", "api_calls", "2026-10-03"),
    ]);
    const { transport, calls } = fakeTransport((fn, args) => {
      if (fn === "tenant_stripe_customer")
        return args["tenant"] === "org-2"
          ? null
          : `cus_${String(args["tenant"])}`;
      return counters(fn, args);
    });
    const sent: unknown[] = [];
    expect(
      await reportUsageToStripe({
        transport,
        stripe: recordingStripe(sent),
        batch: 2,
        eventName: (meter) => (meter === "internal" ? undefined : meter),
      }),
    ).toEqual({ reported: 2, skipped: 2 });
    expect(
      sent.map((entry) => (entry as [{ identifier: string }])[0].identifier),
    ).toEqual(["org-1:api_calls:2026-10-03:2", "org-3:api_calls:2026-10-03:2"]);
    expect(
      calls
        .filter(([, fn]) => fn === "unreported_usage")
        .map(([, , args]) => args),
    ).toEqual([
      { max_rows: 2, skip_meters: [], skip_tenants: [] },
      { max_rows: 2, skip_meters: ["internal"], skip_tenants: ["org-2"] },
    ]);
  });
});
