import { describe, expect, it } from "vitest";

import {
  createForecasts,
  forecastsBlock,
} from "../../../src/blocks/forecasts/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";
const eur = (amount: bigint) => money(amount, "EUR");

const zero = {
  won: "0",
  commit: "0",
  bestCase: "0",
  pipeline: "0",
  notCalled: "0",
  omit: "0",
  later: "0",
};

const totals = {
  ...zero,
  won: "500",
  commit: "1000",
  currency: "EUR",
  target: "2000",
  attainment: 0.75,
  gap: "500",
  owners: [{ ...zero, ownerId: "u1", won: "500" }, { ...zero }],
};

const snapshotRow = (id: string, extra: Record<string, unknown> = {}) => ({
  id,
  organizationId: "org",
  pipelineId: null,
  since: "2026-01-01",
  until: "2026-03-31",
  currency: "EUR",
  target: "2000",
  totals,
  dealCount: 2,
  takenBy: "u1",
  takenAt: AT,
  ...extra,
});

const dealRow = (extra: Record<string, unknown> = {}) => ({
  dealId: "d1",
  name: "Acme",
  ownerId: "u1",
  stageId: "s1",
  forecast: "commit",
  outcome: "open",
  amount: "1000",
  closeOn: "2026-02-01",
  closedAt: null,
  ...extra,
});

describe("createForecasts", () => {
  it("takes a snapshot and decodes its totals as money", async () => {
    const { transport, call } = fakeTransport({
      take_forecast_snapshot: snapshotRow("f1"),
    });

    const snapshot = await createForecasts({ transport })
      .snapshot("org", {
        since: Temporal.PlainDate.from("2026-01-01"),
        until: Temporal.PlainDate.from("2026-03-31"),
        currency: "EUR",
        target: eur(2000n),
        pipelineId: "p1",
      })
      .orThrow();

    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "take_forecast_snapshot",
      {
        tenant: "org",
        pipeline: "p1",
        since: "2026-01-01",
        until: "2026-03-31",
        currency: "EUR",
        target: "2000",
      },
    );
    expect(snapshot).toMatchObject({
      id: "f1",
      pipelineId: undefined,
      target: eur(2000n),
      dealCount: 2,
      takenBy: "u1",
    });
    expect(snapshot.since.toString()).toBe("2026-01-01");
    expect(snapshot.totals).toMatchObject({
      won: eur(500n),
      commit: eur(1000n),
      attainment: 0.75,
      gap: eur(500n),
    });
    expect(snapshot.totals.owners[0]?.ownerId).toBe("u1");
    expect(snapshot.totals.owners[1]).not.toHaveProperty("ownerId");
  });

  it("refuses a target in another currency before calling", async () => {
    const { transport, call } = fakeTransport({});

    const result = await createForecasts({ transport }).snapshot("org", {
      since: Temporal.PlainDate.from("2026-01-01"),
      until: Temporal.PlainDate.from("2026-03-31"),
      currency: "EUR",
      target: money(1n, "USD"),
    });

    expect(result.ok).toBe(false);
    expect(call).not.toHaveBeenCalled();
  });

  it("takes a snapshot of every pipeline without a target", async () => {
    const { transport, call } = fakeTransport({
      take_forecast_snapshot: snapshotRow("f1", {
        target: null,
        dealCount: null,
        takenBy: null,
        pipelineId: "p1",
        totals: { ...totals, target: null, gap: null, attainment: null },
      }),
    });

    const snapshot = await createForecasts({ transport })
      .snapshot("org", {
        since: Temporal.PlainDate.from("2026-01-01"),
        until: Temporal.PlainDate.from("2026-03-31"),
        currency: "EUR",
      })
      .orThrow();

    expect(call.mock.lastCall?.[2]).toMatchObject({
      pipeline: null,
      target: null,
    });
    expect(snapshot).toMatchObject({
      pipelineId: "p1",
      target: undefined,
      dealCount: 0,
      takenBy: undefined,
    });
    expect(snapshot.totals).not.toHaveProperty("target");
    expect(snapshot.totals).not.toHaveProperty("attainment");
  });

  it("lists snapshots with and without a filter", async () => {
    const { transport, call } = fakeTransport({
      forecast_snapshots: [snapshotRow("f2"), snapshotRow("f1")],
    });

    const forecasts = createForecasts({ transport });

    const all = await forecasts.list("org").orThrow();

    expect(all.map((snapshot) => snapshot.id)).toEqual(["f2", "f1"]);
    expect(call.mock.lastCall?.[2]).toEqual({
      tenant: "org",
      pipeline: null,
      since: null,
      until: null,
      max_count: null,
    });

    await forecasts
      .list("org", {
        pipelineId: "p1",
        since: Temporal.PlainDate.from("2026-01-01"),
        until: Temporal.PlainDate.from("2026-03-31"),
        limit: 5,
      })
      .orThrow();
    expect(call.mock.lastCall?.[2]).toEqual({
      tenant: "org",
      pipeline: "p1",
      since: "2026-01-01",
      until: "2026-03-31",
      max_count: 5,
    });
  });

  it("reads a snapshot with its deals", async () => {
    const { transport } = fakeTransport({
      forecast_snapshot: {
        ...snapshotRow("f1"),
        deals: [
          dealRow(),
          dealRow({
            dealId: "d2",
            ownerId: null,
            stageId: null,
            forecast: null,
            outcome: "won",
            closeOn: null,
            closedAt: AT,
          }),
        ],
      },
    });

    const snapshot = await createForecasts({ transport }).get("f1").orThrow();

    expect(snapshot.deals[0]).toMatchObject({
      dealId: "d1",
      amount: eur(1000n),
      forecast: "commit",
    });
    expect(snapshot.deals[0]?.closeOn?.toString()).toBe("2026-02-01");
    expect(snapshot.deals[1]).toMatchObject({
      ownerId: undefined,
      forecast: undefined,
      closeOn: undefined,
    });
    expect(snapshot.deals[1]?.closedAt?.toString()).toBe(AT);
  });

  it("compares two snapshots", async () => {
    const { transport, call } = fakeTransport({
      forecast_changes: {
        from: snapshotRow("f1"),
        to: snapshotRow("f2"),
        deals: [
          {
            dealId: "d1",
            name: "Acme",
            change: "won",
            before: dealRow(),
            after: dealRow({ outcome: "won" }),
          },
          {
            dealId: "d2",
            name: "New",
            change: "added",
            before: null,
            after: dealRow({ dealId: "d2" }),
          },
          {
            dealId: "d3",
            name: "Gone",
            change: "removed",
            before: dealRow({ dealId: "d3" }),
          },
          {
            dealId: "d4",
            name: "Moved",
            change: "something",
            before: dealRow(),
            after: dealRow(),
          },
        ],
      },
    });

    const changes = await createForecasts({ transport })
      .changes("f1", "f2")
      .orThrow();

    expect(call).toHaveBeenCalledWith("better_supabase", "forecast_changes", {
      from_snapshot: "f1",
      to_snapshot: "f2",
    });
    expect(changes.from.id).toBe("f1");
    expect(changes.to.id).toBe("f2");
    expect(changes.deals.map((deal) => deal.change)).toEqual([
      "won",
      "added",
      "removed",
      "changed",
    ]);
    expect(changes.deals[1]?.before).toBeUndefined();
    expect(changes.deals[2]?.after).toBeUndefined();
    expect(changes.deals[0]?.after?.outcome).toBe("won");
  });

  it("fails a snapshot without a period", async () => {
    const { transport } = fakeTransport({
      forecast_snapshot: { ...snapshotRow("f1"), since: null, deals: [] },
    });

    await expect(
      createForecasts({ transport }).get("f1").orThrow(),
    ).rejects.toThrow("since is missing");
  });

  it("logs through the block's hooks with a logger", async () => {
    const { transport } = fakeTransport({ forecast_snapshots: [] });
    const logger = { debug() {}, info() {}, warn() {}, error() {} };

    expect(
      await createForecasts({ transport, logger }).list("org").orThrow(),
    ).toEqual([]);
  });

  it("is the forecasts block", () => {
    expect(forecastsBlock.name).toBe("forecasts");
    expect(forecastsBlock.events.types).toEqual(["forecast.snapshotted"]);
  });
});
