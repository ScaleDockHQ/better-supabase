import { describe, expect, it, vi } from "vitest";

import { createCommerce } from "../../src/blocks/commerce/index.ts";
import { createCrm } from "../../src/blocks/crm/index.ts";
import { createProjects } from "../../src/blocks/projects/index.ts";
import { createSaas } from "../../src/blocks/saas/index.ts";
import { createSupport } from "../../src/blocks/support/index.ts";
import { money } from "../../src/commerce/money.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";

const done = <T>(data: T): AsyncResult<T> =>
  new AsyncResult(Promise.resolve(ok(data)));

const failure = (): AsyncResult<never> =>
  new AsyncResult<never>(Promise.resolve(err(dbError("not_found", "no"))));

const step = <T>(order: string[], name: string, value: T): AsyncResult<T> => {
  order.push(name);

  return done(value);
};

// SAFETY: the helpers read only the methods the fakes define.
const parts = <T>(value: object): T => value as T;

const day = (text: string) => Temporal.PlainDate.from(text);

describe("crm.route", () => {
  const subject = { type: "contact", id: "c1" };

  it("matches the queues on the segment names and the extra fields", async () => {
    const assign = vi.fn(() =>
      done({ queueId: "q", userId: "u", strategy: "round_robin" }),
    );

    const crm = createCrm(
      parts({
        parts: {
          segments: {
            of: () => done([{ segmentId: "s", name: "Enterprise" }]),
          },
          assignment: { assign },
        },
      }),
    );

    const result = await crm.route({
      organizationId: "o",
      subject,
      fields: { country: "NL" },
    });

    expect(result.data?.assignment?.userId).toBe("u");
    expect(assign).toHaveBeenCalledWith({
      organizationId: "o",
      subject: {
        ...subject,
        fields: { segments: ["Enterprise"], country: "NL" },
      },
    });
  });

  it("does not assign when the segments cannot be read", async () => {
    const assign = vi.fn(() => done(undefined));

    const crm = createCrm(
      parts({ parts: { segments: { of: failure }, assignment: { assign } } }),
    );

    const result = await crm.route({ organizationId: "o", subject });

    expect(result.ok).toBe(false);
    expect(assign).not.toHaveBeenCalled();
  });
});

describe("crm.attainment", () => {
  const target = (metric: string, goal: bigint, progress: bigint) => ({
    id: metric,
    name: metric,
    metric,
    periodStart: day("2026-01-01"),
    periodEnd: day("2026-01-10"),
    goal,
    progress,
    attainment: Number(progress) / Number(goal),
  });

  it("sums per metric and lists the targets behind the pace", async () => {
    const crm = createCrm(
      parts({
        parts: {
          goals: {
            progress: () =>
              done([
                target("deals.won_amount", 1000n, 700n),
                target("deals.won_amount", 1000n, 100n),
                target("deals.won_count", 10n, 2n),
              ]),
          },
        },
      }),
    );

    const result = await crm.attainment({
      organizationId: "o",
      on: day("2026-01-05"),
    });

    expect(result.data?.pace).toBe(0.5);
    expect(result.data?.byMetric).toEqual([
      {
        metric: "deals.won_amount",
        progress: 800n,
        goal: 2000n,
        attainment: 0.4,
      },
      { metric: "deals.won_count", progress: 2n, goal: 10n, attainment: 0.2 },
    ]);
    expect(result.data?.behind.map((t) => t.progress)).toEqual([100n, 2n]);
  });

  it("has no pace without targets", async () => {
    const crm = createCrm(
      parts({ parts: { goals: { progress: () => done([]) } } }),
    );

    const result = await crm.attainment({
      organizationId: "o",
      on: day("2026-01-05"),
    });

    expect(result.data).toMatchObject({ pace: 0, byMetric: [], behind: [] });
  });
});

describe("saas.rotateApiKey", () => {
  it("passes the grace period as a duration", async () => {
    const rotate = vi.fn(() => done({ id: "k2" }));
    const saas = createSaas(parts({ parts: { "api-keys": { rotate } } }));

    await saas.rotateApiKey({ id: "k1", graceHours: 6 });

    expect(rotate).toHaveBeenCalledWith({
      id: "k1",
      grace: Temporal.Duration.from({ hours: 6 }),
    });
  });

  it("refuses a grace period outside 0 to 720 hours", async () => {
    const rotate = vi.fn(() => done({ id: "k2" }));
    const saas = createSaas(parts({ parts: { "api-keys": { rotate } } }));

    const result = await saas.rotateApiKey({ id: "k1", graceHours: 721 });

    expect(result.ok).toBe(false);
    expect(rotate).not.toHaveBeenCalled();
  });
});

describe("support.escalate", () => {
  it("assigns first, then restarts the clocks at the new priority", async () => {
    const order: string[] = [];

    const support = createSupport(
      parts({
        parts: {
          tasks: { assign: () => step(order, "assign", 2) },
          sla: { start: () => step(order, "sla", [{ id: "c" }]) },
        },
      }),
    );

    const result = await support.escalate({
      ticketId: "t1",
      assigneeIds: ["a", "b"],
      priority: "urgent",
    });

    expect(order).toEqual(["assign", "sla"]);
    expect(result.data).toEqual({ assignees: 2, clocks: [{ id: "c" }] });
  });

  it("leaves the clocks alone when the assignment fails", async () => {
    const start = vi.fn(() => done([]));

    const support = createSupport(
      parts({ parts: { tasks: { assign: failure }, sla: { start } } }),
    );

    const result = await support.escalate({
      ticketId: "t",
      assigneeIds: [],
      priority: "p",
    });

    expect(result.ok).toBe(false);
    expect(start).not.toHaveBeenCalled();
  });
});

describe("commerce.processReturn", () => {
  const build = () => {
    const receiveReturn = vi.fn(() => done(true));
    const rejectReturn = vi.fn(() => done(true));
    const refund = vi.fn(() => done({ id: "r" }));

    return {
      receiveReturn,
      rejectReturn,
      refund,
      commerce: createCommerce(
        parts({ parts: { orders: { receiveReturn, rejectReturn, refund } } }),
      ),
    };
  };

  it("restocks the units and refunds against the return", async () => {
    const { commerce, receiveReturn, refund } = build();

    const result = await commerce.processReturn({
      orderId: "o",
      returnId: "ret",
      disposition: "restock",
      refund: true,
    });

    expect(receiveReturn).toHaveBeenCalledWith({
      returnId: "ret",
      restock: true,
    });
    expect(refund).toHaveBeenCalledWith({
      orderId: "o",
      input: { returnId: "ret" },
    });
    expect(result.data).toEqual({
      disposition: "restock",
      refund: { id: "r" },
    });
  });

  it("receives quarantined units without restocking", async () => {
    const { commerce, receiveReturn, refund } = build();

    const result = await commerce.processReturn({
      orderId: "o",
      returnId: "ret",
      disposition: "quarantine",
      locationId: "bin",
    });

    expect(receiveReturn).toHaveBeenCalledWith({
      returnId: "ret",
      restock: false,
      locationId: "bin",
    });
    expect(refund).not.toHaveBeenCalled();
    expect(result.data?.refund).toBeNull();
  });

  it("rejects without receiving or refunding", async () => {
    const { commerce, receiveReturn, rejectReturn, refund } = build();

    await commerce.processReturn({
      orderId: "o",
      returnId: "ret",
      disposition: "reject",
      refund: true,
    });

    expect(rejectReturn).toHaveBeenCalledWith("ret");
    expect(receiveReturn).not.toHaveBeenCalled();
    expect(refund).not.toHaveBeenCalled();
  });
});

describe("projects time helpers", () => {
  const at = (text: string) => Temporal.Instant.from(text);

  const entry = (
    userId: string,
    from: string,
    to: string | undefined,
    extra: object = {},
  ) => ({
    userId,
    startedAt: at(from),
    ...(to === undefined ? {} : { endedAt: at(to) }),
    billable: true,
    ...extra,
  });

  it("clips entries to the week and divides by the capacity", async () => {
    const list = vi.fn(() =>
      done([
        entry("a", "2026-11-01T22:00:00Z", "2026-11-02T02:00:00Z", {
          billable: false,
        }),
        entry("a", "2026-11-03T08:00:00Z", "2026-11-03T16:00:00Z"),
        entry("b", "2026-11-04T08:00:00Z", undefined),
      ]),
    );

    const projects = createProjects(
      parts({ parts: { "time-tracking": { list } } }),
    );

    const result = await projects.utilization({
      weekOf: day("2026-11-04"),
      capacityHours: 40,
    });

    expect(result.data?.weekStart.toString()).toBe("2026-11-02");
    expect(result.data?.members).toEqual([
      {
        userId: "a",
        seconds: 10 * 3600,
        billableSeconds: 8 * 3600,
        utilization: 0.25,
        billableUtilization: 0.2,
      },
    ]);
  });

  it("values billable time at each entry's rate", async () => {
    const list = vi.fn(() =>
      done([
        { seconds: 5400, billable: true, rate: money(10_000n, "EUR") },
        { seconds: 3600, billable: false, rate: money(10_000n, "EUR") },
        { billable: true, rate: money(10_000n, "EUR") },
      ]),
    );

    const projects = createProjects(
      parts({ parts: { "time-tracking": { list } } }),
    );

    const result = await projects.financials({ projectId: "p" });

    expect(list).toHaveBeenCalledWith({
      everyone: true,
      subject: { type: "project", id: "p" },
    });
    expect(result.data).toEqual({
      entries: 2,
      seconds: 9000,
      billableSeconds: 5400,
      billable: [money(15_000n, "EUR")],
    });
  });

  it("draws the retainer down and never reports less than zero left", async () => {
    const list = vi.fn(() =>
      done([{ seconds: 7200, billable: true, rate: money(10_000n, "EUR") }]),
    );

    const projects = createProjects(
      parts({ parts: { "time-tracking": { list } } }),
    );

    const open = await projects.retainerDrawdown({
      projectId: "p",
      retainer: money(50_000n, "EUR"),
    });

    expect(open.data).toMatchObject({
      drawn: money(20_000n, "EUR"),
      remaining: money(30_000n, "EUR"),
      exhausted: false,
    });

    const spent = await projects.retainerDrawdown({
      projectId: "p",
      retainer: money(15_000n, "EUR"),
    });

    expect(spent.data).toMatchObject({
      remaining: money(0n, "EUR"),
      exhausted: true,
    });
  });
});
