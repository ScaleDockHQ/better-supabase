import { describe, expect, it } from "vitest";

import { createDeals, dealsSubjects } from "../../../src/blocks/deals/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];
  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];
      if (!result) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(result(args));
    },
  };
}

const ROW = {
  id: "d1",
  tenant_id: "o",
  number: 1,
  identifier: "DEAL-1",
  name: "Growth",
  company_type: "company",
  company_id: "c1",
  motion: "new_logo",
  priority: "hot",
  owner_user_id: "u1",
  product: "pro",
  seats: 60,
  amount: 4800000,
  existing_amount: 0,
  currency: "EUR",
  value_period: "annual",
  amount_source: "manual",
  pipeline_id: "p1",
  stage_id: "s1",
  stage_entered_at: "2026-10-14T09:00:00Z",
  outcome: "won",
  probability: 60,
  forecast_category: "commit",
  opened_on: "2026-10-01",
  expected_close_on: "2026-11-30",
  slipped_from: "2026-11-15",
  push_count: 1,
  closed_at: "2026-10-14T10:00:00Z",
  next_step: "Send order form",
  next_at: "2026-10-15T09:00:00Z",
  next_kind: "email",
  flags: ["legal_review"],
  source: "inbound",
  note: "Signed",
  lost_reason: null,
  locked: false,
  rank: "V",
  archived_at: null,
  created_by: "u1",
  created_at: "2026-10-01T09:00:00Z",
  updated_at: "2026-10-14T09:00:00Z",
  list_total: 10,
  discount_total: 1,
  subtotal: 9,
  tax_total: 2,
  total: 11,
  contacts: [{ type: "person", id: "p1", role: null, primary: true }],
  members: [{ userId: "u2", role: "SE" }],
  region: "emea",
};

describe("deals block", () => {
  it("creates with dates, bigints and contacts as the database reads them", async () => {
    const t = transport({ create_deal: () => ROW });
    const deal = await createDeals({ transport: t })
      .create(
        "o",
        {
          name: "Growth",
          closeOn: Temporal.PlainDate.from("2026-11-30"),
          amount: 4_800_000n,
          nextAt: Temporal.Instant.from("2026-10-15T09:00:00Z"),
        },
        [{ type: "person", id: "p1", primary: true }],
      )
      .orThrow();
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      attrs: {
        name: "Growth",
        closeOn: "2026-11-30",
        amount: "4800000",
        nextAt: "2026-10-15T09:00:00Z",
      },
      contacts: [{ type: "person", id: "p1", primary: true }],
    });
    expect(deal).toMatchObject({
      number: 1n,
      amount: 4_800_000n,
      company: { type: "company", id: "c1" },
      outcome: "won",
      forecast: "commit",
      pushCount: 1,
      flags: ["legal_review"],
      totals: {
        listTotal: 10n,
        discountTotal: 1n,
        subtotal: 9n,
        taxTotal: 2n,
        total: 11n,
      },
      contacts: [{ type: "person", id: "p1", primary: true }],
      members: [{ userId: "u2", role: "SE" }],
      fields: { region: "emea" },
    });
    expect(deal.closeOn.toString()).toBe("2026-11-30");
    expect(deal.slippedFrom?.toString()).toBe("2026-11-15");
  });

  it("reads a sparse deal", async () => {
    const sparse = {
      ...ROW,
      company_type: null,
      company_id: null,
      forecast_category: null,
      slipped_from: null,
      closed_at: null,
      flags: null,
      contacts: null,
      members: null,
      region: undefined,
    };
    const deal = await createDeals({
      transport: transport({ reopen_deal: () => sparse }),
    })
      .reopen("d1")
      .orThrow();
    expect(deal.company).toBeUndefined();
    expect(deal.forecast).toBeUndefined();
    expect(deal.flags).toEqual([]);
    expect(deal.contacts).toEqual([]);
  });

  it("sends a batch of changes and reads per-change results", async () => {
    const t = transport({
      update_deals: () => ({
        accepted: [{ dealId: "d1", field: "closeOn" }],
        rejected: [
          {
            dealId: "d1",
            field: "amount",
            hint: "DEAL_LOCKED",
            reason: "locked",
          },
          { dealId: "d1", field: "x", hint: null, reason: "bad" },
        ],
      }),
    });
    const result = await createDeals({ transport: t })
      .update([
        {
          dealId: "d1",
          field: "closeOn",
          value: Temporal.PlainDate.from("2026-12-01"),
        },
        { dealId: "d1", field: "amount", value: 5n },
      ])
      .orThrow();
    expect(t.calls[0]?.[1]).toEqual({
      changes: [
        { dealId: "d1", field: "closeOn", value: "2026-12-01" },
        { dealId: "d1", field: "amount", value: "5" },
      ],
    });
    expect(result.rejected).toEqual([
      { dealId: "d1", field: "amount", hint: "DEAL_LOCKED", reason: "locked" },
      { dealId: "d1", field: "x", reason: "bad" },
    ]);
  });

  it("closes, sets contacts, members and lines, archives and removes", async () => {
    const t = transport({
      close_deal: () => ROW,
      set_deal_contacts: () => 1,
      set_deal_members: () => 2,
      set_deal_lines: () => ({
        listTotal: "100",
        discountTotal: "0",
        subtotal: "100",
        taxTotal: "21",
        total: "121",
      }),
      archive_deal: () => true,
      delete_deal: () => true,
    });
    const deals = createDeals({ transport: t });
    await deals.win("d1").orThrow();
    await deals.lose("d1", "Budget").orThrow();
    expect(await deals.setContacts("d1", []).orThrow()).toBe(1);
    expect(await deals.setMembers("d1", [{ userId: "u2" }]).orThrow()).toBe(2);
    expect(
      (
        await deals
          .setLines("d1", [{ description: "x", unitAmount: 100n }])
          .orThrow()
      ).total,
    ).toBe(121n);
    expect(await deals.archive("d1").orThrow()).toBe(true);
    expect(await deals.remove("d1").orThrow()).toBe(true);
    expect(t.calls.slice(0, 2).map(([, args]) => args)).toEqual([
      { deal: "d1", outcome: "won", reason: null },
      { deal: "d1", outcome: "lost", reason: "Budget" },
    ]);
    expect(t.calls[4]?.[1]).toEqual({
      parent: "d1",
      lines: [{ description: "x", unitAmount: "100" }],
    });
  });

  it("reads the forecast and health", async () => {
    const sums = {
      won: "1",
      commit: "2",
      bestCase: "3",
      pipeline: "4",
      notCalled: "5",
      omit: "6",
      later: "7",
    };
    const t = transport({
      deal_forecast: () => ({
        ...sums,
        currency: "EUR",
        target: "10",
        attainment: 0.3,
        gap: "7",
        owners: [
          { ownerId: "u1", ...sums },
          { ownerId: null, ...sums },
        ],
      }),
      deal_health: () => [
        {
          dealId: "d1",
          identifier: "DEAL-1",
          name: "Growth",
          daysInStage: 3,
          rotting: true,
          slipped: false,
          noNextStep: true,
          overdue: false,
        },
      ],
    });
    const deals = createDeals({ transport: t });
    const forecast = await deals
      .forecast("o", {
        since: Temporal.PlainDate.from("2026-10-01"),
        until: Temporal.PlainDate.from("2026-12-31"),
        currency: "EUR",
        target: 10n,
      })
      .orThrow();
    expect(forecast).toMatchObject({
      won: 1n,
      later: 7n,
      target: 10n,
      attainment: 0.3,
      gap: 7n,
    });
    expect(forecast.owners[1]?.ownerId).toBeUndefined();
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      pipeline: null,
      since: "2026-10-01",
      until: "2026-12-31",
      currency: "EUR",
      target: "10",
      owner: null,
    });
    const empty = createDeals({
      transport: transport({
        deal_forecast: () => ({
          ...sums,
          currency: "EUR",
          target: null,
          attainment: null,
          gap: null,
          owners: [],
        }),
      }),
    });
    expect(
      (
        await empty
          .forecast("o", {
            since: Temporal.PlainDate.from("2026-10-01"),
            until: Temporal.PlainDate.from("2026-12-31"),
            currency: "EUR",
          })
          .orThrow()
      ).target,
    ).toBeUndefined();
    expect((await deals.health("p1").orThrow())[0]).toMatchObject({
      rotting: true,
      noNextStep: true,
    });
  });

  it("registers deals as a ranked subject grouped by stage", () => {
    expect(dealsSubjects({ url: "/deals/{id}" }).deal).toMatchObject({
      table: "better_supabase.deals",
      rank: { column: "rank", group: "stage_id" },
      url: "/deals/{id}",
    });
    expect(dealsSubjects({ schema: "crm" }).deal.url).toBeUndefined();
  });
});
