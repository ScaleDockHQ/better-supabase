import { describe, expect, it } from "vitest";

import { createCommissions } from "../../../src/blocks/commissions/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const ENTRY = {
  id: "c1",
  organizationId: "org-1",
  planId: "p1",
  sellerId: "u1",
  sourceType: "invoices",
  sourceId: "inv-1",
  basis: "80000",
  amount: "8000",
  currency: "EUR",
  occurredOn: "2026-03-05",
  status: "accrued",
  createdAt: "2026-03-05T00:00:00Z",
};

const STATEMENT = {
  id: "s1",
  organizationId: "org-1",
  sellerId: "u1",
  startsOn: "2026-03-01",
  endsOn: "2026-03-31",
  currency: "EUR",
  status: "open",
  total: "8000",
  createdAt: "2026-03-31T00:00:00Z",
};

describe("createCommissions", () => {
  it("saves a tiered plan and accrues a commission as money", async () => {
    const t = fieldsTransport({
      save_commission_plan: () => ({
        id: "p1",
        organizationId: "org-1",
        name: "Tiered",
        kind: "tiered",
        tiers: [
          { upTo: 100_000, bps: 1000 },
          { upTo: null, bps: 500 },
        ],
        createdAt: "2026-01-01T00:00:00Z",
        updatedAt: "2026-01-01T00:00:00Z",
      }),
      accrue_commission: () => ENTRY,
    });

    const commissions = createCommissions({ transport: t, tenant: "org-1" });

    const plan = await commissions
      .savePlan({
        name: "Tiered",
        kind: "tiered",
        tiers: [{ upTo: 100_000, bps: 1000 }, { bps: 500 }],
      })
      .orThrow();

    const entry = await commissions
      .accrue({
        sellerId: "u1",
        source: { type: "invoices", id: "inv-1" },
        basis: money(80_000n, "EUR"),
      })
      .orThrow();

    expect(plan.tiers).toEqual([{ upTo: 100_000, bps: 1000 }, { bps: 500 }]);
    expect(entry?.amount).toEqual(money(8000n, "EUR"));
    expect(t.calls[1]).toEqual([
      "accrue_commission",
      {
        tenant: "org-1",
        seller_id: "u1",
        source_type: "invoices",
        source_id: "inv-1",
        basis: "80000",
        currency: "EUR",
      },
    ]);
  });

  it("returns undefined when the seller has no plan", async () => {
    const t = fieldsTransport({ accrue_commission: () => null });
    const commissions = createCommissions({ transport: t, tenant: "org-1" });

    await expect(
      commissions
        .accrue({
          sellerId: "u1",
          source: { type: "orders", id: "o1" },
          basis: money(100n, "EUR"),
        })
        .orThrow(),
    ).resolves.toBeUndefined();
  });

  it("builds, finalizes and pays a statement", async () => {
    const t = fieldsTransport({
      build_commission_statement: () => STATEMENT,
      finalize_commission_statement: () => ({
        ...STATEMENT,
        status: "finalized",
        finalizedAt: "2026-04-01T00:00:00Z",
      }),
      pay_commission_statement: () => ({ ...STATEMENT, status: "paid" }),
    });

    const commissions = createCommissions({ transport: t, tenant: "org-1" });
    const { PlainDate } = temporal();

    const built = await commissions
      .buildStatement({
        sellerId: "u1",
        currency: "EUR",
        startsOn: PlainDate.from("2026-03-01"),
        endsOn: PlainDate.from("2026-03-31"),
      })
      .orThrow();

    const finalized = await commissions.finalizeStatement("s1").orThrow();
    const paid = await commissions.payStatement("s1").orThrow();

    expect(built.total).toEqual(money(8000n, "EUR"));
    expect(finalized.status).toBe("finalized");
    expect(paid.status).toBe("paid");
    expect(t.calls[0]?.[1]).toMatchObject({
      starts_on: "2026-03-01",
      ends_on: "2026-03-31",
    });
  });

  it("reverses a commission and lists them by seller", async () => {
    const t = fieldsTransport({
      reverse_commission: () => ({ ...ENTRY, status: "reversed" }),
      list_commissions: () => [ENTRY],
    });

    const commissions = createCommissions({ transport: t, tenant: "org-1" });

    const reversed = await commissions
      .reverse({ commissionId: "c1", reason: "refund" })
      .orThrow();

    const listed = await commissions
      .listCommissions({ sellerId: "u1" })
      .orThrow();

    expect(reversed.status).toBe("reversed");
    expect(listed).toHaveLength(1);
    expect(t.calls[1]).toEqual([
      "list_commissions",
      { tenant: "org-1", filters: { seller: "u1" } },
    ]);
  });

  it("reads a keyset page, its facets and its count of accrued commissions", async () => {
    const t = fieldsTransport({
      list_commissions: (args) => {
        const filters = args["filters"] as Record<string, unknown>;

        if (filters["facet"] !== undefined) {
          return {
            facet: filters["facet"],
            values: [{ value: "accrued", count: { value: 2, exact: true } }],
          };
        }

        if (filters["count"] === true) {
          return { value: 7, exact: false };
        }

        return { items: [ENTRY], hasMore: true, nextCursor: ["a", "b"] };
      },
    });

    const block = createCommissions({ transport: t, tenant: "org-1" });

    const page = await block
      .commissionPage({
        limit: 1,
        sort: { by: "occurredOn", direction: "asc" },
        filters: { status: ["accrued"] },
      })
      .orThrow();

    const facets = await block
      .commissionFacets({ facets: ["status"] })
      .orThrow();

    const count = await block.commissionCount().orThrow();

    expect(page.items).toHaveLength(1);
    expect(page).toMatchObject({ hasMore: true, nextCursor: ["a", "b"] });
    expect(t.calls[0]?.[1]).toMatchObject({
      tenant: "org-1",
      filters: { limit: 1, sort: "occurredOn", direction: "asc", paged: true },
    });
    expect(facets[0]?.facet).toBe("status");
    expect(facets[0]?.values[0]?.count).toEqual({ value: 2, exact: true });
    expect(count).toEqual({ value: 7, exact: false });
  });

  it("rejects a sort of accrued commissions that is not declared", async () => {
    const t = fieldsTransport({});
    const block = createCommissions({ transport: t, tenant: "org-1" });

    const result = await block.commissionPage({ sort: { by: "nope" } });

    expect(result.ok).toBe(false);
    expect(t.calls).toHaveLength(0);
  });

  it("reads a keyset page, its facets and its count of commission statements", async () => {
    const t = fieldsTransport({
      list_commission_statements: (args) => {
        const filters = args["filters"] as Record<string, unknown>;

        if (filters["facet"] !== undefined) {
          return {
            facet: filters["facet"],
            values: [{ value: "open", count: { value: 2, exact: true } }],
          };
        }

        if (filters["count"] === true) {
          return { value: 7, exact: false };
        }

        return { items: [STATEMENT], hasMore: true, nextCursor: ["a", "b"] };
      },
    });

    const block = createCommissions({ transport: t, tenant: "org-1" });

    const page = await block
      .statementPage({
        limit: 1,
        sort: { by: "endsOn", direction: "asc" },
        filters: { status: ["open"] },
      })
      .orThrow();

    const facets = await block
      .statementFacets({ facets: ["status"] })
      .orThrow();

    const count = await block.statementCount().orThrow();

    expect(page.items).toHaveLength(1);
    expect(page).toMatchObject({ hasMore: true, nextCursor: ["a", "b"] });
    expect(t.calls[0]?.[1]).toMatchObject({
      tenant: "org-1",
      filters: { limit: 1, sort: "endsOn", direction: "asc", paged: true },
    });
    expect(facets[0]?.facet).toBe("status");
    expect(facets[0]?.values[0]?.count).toEqual({ value: 2, exact: true });
    expect(count).toEqual({ value: 7, exact: false });
  });

  it("rejects a sort of commission statements that is not declared", async () => {
    const t = fieldsTransport({});
    const block = createCommissions({ transport: t, tenant: "org-1" });

    const result = await block.statementPage({ sort: { by: "nope" } });

    expect(result.ok).toBe(false);
    expect(t.calls).toHaveLength(0);
  });
});

describe("commission plans, assignments and payroll", () => {
  const PLAN = {
    id: "p2",
    organizationId: "org-1",
    name: "Flat",
    kind: "flat",
    rateBps: 750,
    createdAt: "2026-01-01T00:00:00Z",
    updatedAt: "2026-01-02T00:00:00Z",
    archivedAt: "2026-02-01T00:00:00Z",
  };

  const ASSIGNMENT = {
    id: "a1",
    organizationId: "org-1",
    planId: "p2",
    sellerId: "u1",
    startsOn: "2026-01-01",
    endsOn: "2026-06-30",
    subjectType: "customers",
    subjectId: "cu-1",
    createdAt: "2026-01-01T00:00:00Z",
  };

  it("assigns a plan to a subject and ends the assignment", async () => {
    const t = fieldsTransport({
      assign_commission_plan: () => ASSIGNMENT,
      end_commission_assignment: () => ({
        ...ASSIGNMENT,
        endsOn: null,
        subjectType: null,
        subjectId: null,
      }),
    });

    const commissions = createCommissions({ transport: t, tenant: "org-1" });
    const { PlainDate } = temporal();

    const assigned = await commissions
      .assignPlan({
        planId: "p2",
        sellerId: "u1",
        subject: { type: "customers", id: "cu-1" },
        startsOn: PlainDate.from("2026-01-01"),
        endsOn: PlainDate.from("2026-06-30"),
      })
      .orThrow();

    await commissions.assignPlan({ planId: "p2", sellerId: "u1" }).orThrow();
    const ended = await commissions.endAssignment("a1").orThrow();

    expect(assigned).toMatchObject({
      subjectType: "customers",
      subjectId: "cu-1",
    });
    expect(assigned.endsOn?.toString()).toBe("2026-06-30");
    expect(ended.endsOn).toBeUndefined();
    expect(ended.subjectType).toBeUndefined();
    expect(t.calls.map((call) => call[1])).toEqual([
      {
        tenant: "org-1",
        plan_id: "p2",
        seller_id: "u1",
        subject_type: "customers",
        subject_id: "cu-1",
        starts_on: "2026-01-01",
        ends_on: "2026-06-30",
      },
      { tenant: "org-1", plan_id: "p2", seller_id: "u1" },
      { assignment_id: "a1" },
    ]);
  });

  it("lists plans with and without assignments, and pages them", async () => {
    const t = fieldsTransport({
      list_commission_plans: (args) => {
        const filters = args["filters"] as Record<string, unknown>;

        return filters["paged"] === true
          ? { items: [{ ...PLAN, assignments: [ASSIGNMENT] }], hasMore: false }
          : [
              { ...PLAN, assignments: [ASSIGNMENT] },
              { ...PLAN, id: "p3" },
            ];
      },
    });

    const commissions = createCommissions({ transport: t, tenant: "org-1" });
    const plans = await commissions.listPlans({ archived: true }).orThrow();
    const page = await commissions.planPage({ limit: 5 }).orThrow();

    expect(plans[0]).toMatchObject({ rateBps: 750, kind: "flat" });
    expect(plans[0]?.archivedAt?.toString()).toBe("2026-02-01T00:00:00Z");
    expect(plans[0]?.assignments).toHaveLength(1);
    expect(plans[1]?.assignments).toEqual([]);
    expect(page.items[0]?.assignments[0]?.sellerId).toBe("u1");
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      filters: { archived: true },
    });
  });

  it("reads a statement with its entries and lists statements", async () => {
    const t = fieldsTransport({
      get_commission_statement: () => ({
        ...STATEMENT,
        status: "paid",
        paidAt: "2026-04-02T00:00:00Z",
        paidBy: "u9",
        ledgerTransactionId: "lt-1",
        entries: [
          {
            ...ENTRY,
            statementId: "s1",
            ledgerTransactionId: "lt-0",
            reversedAt: "2026-04-03T00:00:00Z",
          },
        ],
      }),
      list_commission_statements: () => [STATEMENT],
    });

    const commissions = createCommissions({ transport: t, tenant: "org-1" });
    const statement = await commissions.getStatement("s1").orThrow();

    const listed = await commissions
      .listStatements({ sellerId: "u1", status: "open", limit: 10 })
      .orThrow();

    expect(statement).toMatchObject({
      paidBy: "u9",
      ledgerTransactionId: "lt-1",
    });
    expect(statement.entries[0]).toMatchObject({
      statementId: "s1",
      ledgerTransactionId: "lt-0",
    });
    expect(listed).toHaveLength(1);
    expect(t.calls[1]?.[1]).toEqual({
      tenant: "org-1",
      filters: { seller: "u1", status: "open", limit: 10 },
    });
  });

  it("reads a statement without entries", async () => {
    const t = fieldsTransport({ get_commission_statement: () => STATEMENT });

    const statement = await createCommissions({ transport: t, tenant: "org-1" })
      .getStatement("s1")
      .orThrow();

    expect(statement.entries).toEqual([]);
  });

  it("sums payroll lines per seller", async () => {
    const t = fieldsTransport({
      commission_payroll_lines: () => [
        { userId: "u1", amount: "8000", currency: "EUR", statementIds: ["s1"] },
        { userId: "u2", amount: "10", currency: "EUR", statementIds: [1] },
      ],
    });

    const { PlainDate } = temporal();

    const lines = await createCommissions({ transport: t, tenant: "org-1" })
      .payrollLines({
        from: PlainDate.from("2026-03-01"),
        to: PlainDate.from("2026-03-31"),
      })
      .orThrow();

    expect(lines).toEqual([
      { userId: "u1", amount: money(8000n, "EUR"), statementIds: ["s1"] },
      { userId: "u2", amount: money(10n, "EUR"), statementIds: [] },
    ]);
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      from_date: "2026-03-01",
      to_date: "2026-03-31",
    });
  });

  it("refuses a row with a date that is not text", async () => {
    const t = fieldsTransport({
      end_commission_assignment: () => ({ ...ASSIGNMENT, startsOn: 5 }),
    });

    const result = await createCommissions({
      transport: t,
      tenant: "org-1",
    }).endAssignment("a1");

    expect(result.ok).toBe(false);
  });
});
