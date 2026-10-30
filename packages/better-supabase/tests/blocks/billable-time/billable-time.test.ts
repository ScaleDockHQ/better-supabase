import { describe, expect, it } from "vitest";

import {
  billableTimeBlock,
  billableTimeBinding,
  createBillableTime,
  timeInvoiceSectionInputSchema,
  timeRateInputSchema,
  timeRateSectionInputSchema,
} from "../../../src/blocks/billable-time/index.ts";
import { money } from "../../../src/commerce/money.ts";

const AT = "2026-10-22T10:00:00Z";
const CUSTOMER = { type: "customer", id: "c1" };

const RATE = {
  id: "r1",
  organizationId: "org-1",
  userId: "u1",
  subjectType: "customer",
  subjectId: "c1",
  rate: "12000",
  currency: "EUR",
  effectiveFrom: "2026-09-01",
  createdBy: "u0",
  createdAt: AT,
};

const ORG_RATE = {
  ...RATE,
  id: "r2",
  userId: null,
  subjectType: null,
  subjectId: null,
  createdBy: null,
};

const PREVIEW = {
  lines: [
    {
      description: "Time on customer c1",
      quantity: 2,
      unitAmount: "12000",
      currency: "EUR",
      amount: "24000",
      entryIds: ["e1"],
      subjectType: "customer",
      subjectId: "c1",
      userId: null,
    },
    {
      description: "Time",
      quantity: 1.5,
      unitAmount: "15000",
      currency: "EUR",
      amount: "22500",
      entryIds: ["e2"],
      subjectType: null,
      subjectId: null,
      userId: "u2",
    },
  ],
  totals: [{ amount: "46500", currency: "EUR" }],
  unrated: ["e9"],
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createBillableTime", () => {
  it("sets a member's rate on a record in minor units", async () => {
    const fake = fakeTransport({ set_time_rate: RATE });

    const time = createBillableTime({
      transport: fake.transport,
      tenant: "org-1",
    });

    const rate = await time
      .setRate({
        rate: money(12_000n, "EUR"),
        userId: "u1",
        subject: CUSTOMER,
        effectiveFrom: Temporal.PlainDate.from("2026-09-01"),
      })
      .orThrow();

    expect(fake.calls).toEqual([
      [
        "set_time_rate",
        {
          tenant: "org-1",
          rate: "12000",
          currency: "EUR",
          user_id: "u1",
          subject_type: "customer",
          subject_id: "c1",
          effective_from: "2026-09-01",
          cost_amount: null,
        },
      ],
    ]);
    expect(rate).toMatchObject({
      id: "r1",
      userId: "u1",
      subject: CUSTOMER,
      rate: money(12_000n, "EUR"),
      createdBy: "u0",
    });
    expect(rate.effectiveFrom.toString()).toBe("2026-09-01");
  });

  it("leaves out what an organization rate doesn't have", async () => {
    const fake = fakeTransport({
      delete_time_rate: ORG_RATE,
      list_time_rates: [ORG_RATE],
    });

    const time = createBillableTime({
      transport: fake.transport,
      tenant: "org-1",
    });

    const rate = await time.deleteRate("r2").orThrow();
    const listed = await time.listRates({ pageSize: 10 }).orThrow();

    expect(Object.keys(rate).toSorted()).toEqual([
      "createdAt",
      "effectiveFrom",
      "id",
      "organizationId",
      "rate",
    ]);
    expect(listed).toHaveLength(1);
    expect(fake.calls).toEqual([
      ["delete_time_rate", { rate_id: "r2" }],
      [
        "list_time_rates",
        {
          tenant: "org-1",
          user_id: null,
          subject_type: null,
          subject_id: null,
          page_size: 10,
        },
      ],
    ]);
  });

  it("looks up the rate that applies, or null", async () => {
    const fake = fakeTransport({ time_rate: null });

    const time = createBillableTime({
      transport: fake.transport,
      tenant: "org-1",
    });

    expect(
      await time
        .rateFor({
          userId: "u1",
          subject: CUSTOMER,
          on: Temporal.PlainDate.from("2026-10-05"),
        })
        .orThrow(),
    ).toBeNull();
    expect(await time.rateFor().orThrow()).toBeNull();
    expect(fake.calls).toEqual([
      [
        "time_rate",
        {
          tenant: "org-1",
          user_id: "u1",
          subject_type: "customer",
          subject_id: "c1",
          on_day: "2026-10-05",
        },
      ],
      [
        "time_rate",
        {
          tenant: "org-1",
          user_id: null,
          subject_type: null,
          subject_id: null,
          on_day: null,
        },
      ],
    ]);
  });

  it("previews unbilled time with a scope that leaves out absent fields", async () => {
    const fake = fakeTransport({ unbilled_time: PREVIEW });

    const time = createBillableTime({
      transport: fake.transport,
      tenant: "org-1",
    });

    const preview = await time
      .unbilled({
        subject: CUSTOMER,
        starts: Temporal.Instant.from("2026-10-01T00:00:00Z"),
        groupBy: "member",
      })
      .orThrow();

    expect(fake.calls).toEqual([
      [
        "unbilled_time",
        {
          tenant: "org-1",
          scope: { subject: CUSTOMER, starts: "2026-10-01T00:00:00Z" },
          group_by: "member",
        },
      ],
    ]);
    expect(preview.totals).toEqual([money(46_500n, "EUR")]);
    expect(preview.unrated).toEqual(["e9"]);
    expect(preview.lines[0]).toEqual({
      description: "Time on customer c1",
      quantity: "2",
      unitAmount: money(12_000n, "EUR"),
      amount: money(24_000n, "EUR"),
      entryIds: ["e1"],
      subject: CUSTOMER,
    });
    expect(preview.lines[1]).toMatchObject({ userId: "u2", quantity: "1.5" });
    expect(preview.lines[1]).not.toHaveProperty("subject");
  });

  it("bills time on a draft invoice", async () => {
    const fake = fakeTransport({
      invoice_from_time: {
        invoiceId: "i1",
        currency: "EUR",
        total: "46500",
        entryIds: ["e1", "e2"],
      },
    });

    const time = createBillableTime({
      transport: fake.transport,
      tenant: "org-1",
    });

    const invoice = await time
      .invoice({
        title: "October",
        company: { type: "companies", id: "co1" },
        termsDays: 14,
        entryIds: ["e1", "e2"],
        ends: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      })
      .orThrow();

    expect(fake.calls).toEqual([
      [
        "invoice_from_time",
        {
          tenant: "org-1",
          attrs: {
            title: "October",
            company: { type: "companies", id: "co1" },
            termsDays: 14,
          },
          scope: { entryIds: ["e1", "e2"], ends: "2026-11-01T00:00:00Z" },
          group_by: "subject",
        },
      ],
    ]);
    expect(invoice).toEqual({
      invoiceId: "i1",
      total: money(46_500n, "EUR"),
      entryIds: ["e1", "e2"],
    });
  });

  it("lists the entries an invoice billed", async () => {
    const fake = fakeTransport({
      list_invoiced_time: [
        {
          entryId: "e1",
          invoiceId: "i1",
          userId: "u1",
          subjectType: "customer",
          subjectId: "c1",
          startedAt: AT,
          seconds: 7200,
          rate: "12000",
          currency: "EUR",
          createdAt: AT,
        },
      ],
    });

    const time = createBillableTime({ transport: fake.transport });

    const [entry] = await time.invoicedEntries("i1").orThrow();

    expect(entry).toMatchObject({
      entryId: "e1",
      seconds: 7200,
      subject: CUSTOMER,
      rate: money(12_000n, "EUR"),
    });
    expect(fake.calls).toEqual([
      ["list_invoiced_time", { invoice: "i1", page_size: null }],
    ]);
  });

  it("rejects malformed rows", async () => {
    const time = createBillableTime({
      transport: fakeTransport({
        list_invoiced_time: [{ entryId: "e1", seconds: 1.5 }],
        invoice_from_time: { invoiceId: "i1", total: "1", currency: "EUR" },
      }).transport,
      tenant: "org-1",
    });

    expect((await time.invoicedEntries("i1")).ok).toBe(false);
    expect((await time.invoice()).ok).toBe(false);
  });

  it("fails without a tenant", async () => {
    const time = createBillableTime({ transport: fakeTransport({}).transport });

    expect((await time.unbilled()).ok).toBe(false);
  });
});

describe("billable-time block", () => {
  it("loads a record's unbilled time and bills it through the section", async () => {
    const fake = fakeTransport({
      unbilled_time: PREVIEW,
      set_time_rate: RATE,
      invoice_from_time: {
        invoiceId: "i1",
        currency: "EUR",
        total: "1",
        entryIds: [],
      },
    });

    const time = createBillableTime({
      transport: fake.transport,
      tenant: "org-1",
    });

    await billableTimeBinding.load(time, CUSTOMER, undefined);
    await billableTimeBinding.writes.setRate.run(time, CUSTOMER, {
      rate: money(1n, "EUR"),
    });
    await billableTimeBinding.writes.invoice.run(time, CUSTOMER, {
      title: "October",
    });

    expect(
      fake.calls.map(([fn, args]) => [
        fn,
        args["subject_id"] ??
          (args["scope"] as { subject?: { id: string } }).subject?.id,
      ]),
    ).toEqual([
      ["unbilled_time", "c1"],
      ["set_time_rate", "c1"],
      ["invoice_from_time", "c1"],
    ]);
    expect(billableTimeBlock.name).toBe("billable-time");
  });

  it("validates the inputs", () => {
    expect(
      validate(timeRateInputSchema, { rate: { amount: 100n, currency: "EUR" } })
        .issues,
    ).toBeUndefined();
    expect(validate(timeRateInputSchema, {}).issues).toBeDefined();
    expect(
      validate(timeRateSectionInputSchema, { rate: "100" }).issues,
    ).toBeDefined();
    expect(
      validate(timeInvoiceSectionInputSchema, { groupBy: "week" }).issues,
    ).toBeDefined();
  });
});

describe("project costing", () => {
  const COSTS = {
    projectId: "p1",
    organizationId: "org-1",
    hours: 5,
    uncostedHours: 0.5,
    budgetAmount: "50000",
    budgetCurrency: "EUR",
    budgetHours: 10,
    totals: [
      {
        currency: "EUR",
        timeCost: "30000",
        billed: "50000",
        expenses: "4000",
        income: "0",
        margin: "16000",
      },
      {
        currency: "USD",
        timeCost: "0",
        billed: "1000",
        expenses: "0",
        income: "0",
        margin: "1000",
      },
    ],
  };

  it("reads a project with no time, no totals and no budget", async () => {
    const fake = fakeTransport({
      project_costs: { projectId: "p1", organizationId: "org-1" },
    });

    const time = createBillableTime({
      transport: fake.transport,
      tenant: "org-1",
    });

    const costs = await time.projectCosts("p1").orThrow();

    expect(costs).toEqual({
      projectId: "p1",
      organizationId: "org-1",
      hours: 0,
      uncostedHours: 0,
      totals: [],
      budgetUsed: {},
    });
  });

  it("counts no spend when the budget's currency has no totals", async () => {
    const fake = fakeTransport({
      project_costs: { ...COSTS, totals: [COSTS.totals[1]] },
    });

    const time = createBillableTime({
      transport: fake.transport,
      tenant: "org-1",
    });

    const costs = await time.projectCosts("p1").orThrow();

    expect(costs.budgetUsed).toEqual({ hours: 0.5, amount: 0 });
  });

  it("sends a rate's cost and reads it back", async () => {
    const fake = fakeTransport({
      set_time_rate: { ...ORG_RATE, cost: "6000" },
    });

    const time = createBillableTime({
      transport: fake.transport,
      tenant: "org-1",
    });

    const rate = await time
      .setRate({ rate: money(10_000n, "EUR"), cost: money(6000n, "EUR") })
      .orThrow();

    expect(fake.calls[0]?.[1]).toMatchObject({ cost_amount: "6000" });
    expect(rate.cost).toEqual(money(6000n, "EUR"));
  });

  it("refuses a cost in another currency than the rate", async () => {
    const fake = fakeTransport({});
    const time = createBillableTime({ transport: fake.transport });

    const result = await time.setRate({
      rate: money(10_000n, "EUR"),
      cost: money(6000n, "USD"),
    });

    expect(result.ok ? undefined : result.error.hint).toBe("CURRENCY_MISMATCH");
    expect(fake.calls).toEqual([]);
  });

  it("reads a project's totals per currency and works out the budget use", async () => {
    const fake = fakeTransport({ project_costs: COSTS });
    const time = createBillableTime({ transport: fake.transport });

    const costs = await time.projectCosts("p1").orThrow();

    expect(fake.calls).toEqual([["project_costs", { project_id: "p1" }]]);
    expect(costs).toMatchObject({
      projectId: "p1",
      hours: 5,
      uncostedHours: 0.5,
      budget: money(50_000n, "EUR"),
      budgetHours: 10,
      budgetUsed: { hours: 0.5, amount: 0.68 },
    });
    expect(costs.totals[0]?.margin).toEqual(money(16_000n, "EUR"));
    expect(costs.totals[1]?.billed).toEqual(money(1000n, "USD"));
  });

  it("leaves the budget use out without a budget", async () => {
    const fake = fakeTransport({
      project_costs: {
        projectId: "p1",
        organizationId: "org-1",
        hours: 0,
        uncostedHours: 0,
        budgetAmount: null,
        budgetCurrency: null,
        budgetHours: null,
        totals: [],
      },
    });

    const time = createBillableTime({ transport: fake.transport });

    const costs = await time.projectCosts("p1").orThrow();

    expect(costs).toEqual({
      projectId: "p1",
      organizationId: "org-1",
      hours: 0,
      uncostedHours: 0,
      totals: [],
      budgetUsed: {},
    });
  });

  it("counts no spend when no total is in the budget's currency", async () => {
    const fake = fakeTransport({
      project_costs: { ...COSTS, budgetHours: 0, totals: [COSTS.totals[1]] },
    });

    const time = createBillableTime({ transport: fake.transport });

    expect((await time.projectCosts("p1").orThrow()).budgetUsed).toEqual({
      amount: 0,
    });
  });
});
