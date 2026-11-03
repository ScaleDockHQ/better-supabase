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
});
