import { describe, expect, it } from "vitest";

import { createPeriods } from "../../../src/blocks/periods/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const PERIOD = {
  id: "p1",
  organizationId: "org-1",
  kind: "leave_year",
  startsOn: "2026-01-01",
  endsOn: "2026-12-31",
  status: "open",
  createdAt: "2026-01-01T00:00:00Z",
};

describe("createPeriods", () => {
  it("creates a period and finds it by date", async () => {
    const t = fieldsTransport({
      create_period: () => PERIOD,
      period_for: () => PERIOD,
    });

    const periods = createPeriods({ transport: t, tenant: "org-1" });
    const { PlainDate } = temporal();

    const created = await periods
      .createPeriod({
        kind: "leave_year",
        startsOn: PlainDate.from("2026-01-01"),
        endsOn: PlainDate.from("2026-12-31"),
      })
      .orThrow();

    const found = await periods
      .periodFor({ kind: "leave_year", date: PlainDate.from("2026-06-01") })
      .orThrow();

    expect(created.status).toBe("open");
    expect(found?.endsOn.toString()).toBe("2026-12-31");
    expect(t.calls).toEqual([
      [
        "create_period",
        {
          tenant: "org-1",
          kind: "leave_year",
          starts_on: "2026-01-01",
          ends_on: "2026-12-31",
        },
      ],
      [
        "period_for",
        { tenant: "org-1", kind: "leave_year", on_date: "2026-06-01" },
      ],
    ]);
  });

  it("returns undefined when no period holds the date", async () => {
    const t = fieldsTransport({ period_for: () => null });
    const periods = createPeriods({ transport: t, tenant: "org-1" });

    await expect(
      periods
        .periodFor({
          kind: "other",
          date: temporal().PlainDate.from("2026-06-01"),
        })
        .orThrow(),
    ).resolves.toBeUndefined();
  });

  it("locks, closes and reopens a period and lists blockers", async () => {
    const t = fieldsTransport({
      lock_period: () => ({ ...PERIOD, status: "locked" }),
      close_period: () => ({
        ...PERIOD,
        status: "closed",
        closedAt: "2027-01-02T00:00:00Z",
      }),
      reopen_period: () => PERIOD,
      period_close_blockers: () => ["pending_requests"],
      period_is_open: () => false,
      list_periods: () => [PERIOD],
    });

    const periods = createPeriods({ transport: t, tenant: "org-1" });

    expect((await periods.lock("p1").orThrow()).status).toBe("locked");
    expect((await periods.close("p1").orThrow()).closedAt).toBeDefined();
    expect(
      (await periods.reopen({ periodId: "p1", reason: "late" }).orThrow())
        .status,
    ).toBe("open");
    expect(await periods.closeBlockers("p1").orThrow()).toEqual([
      "pending_requests",
    ]);
    expect(
      await periods
        .isOpen({
          kind: "leave_year",
          date: temporal().PlainDate.from("2026-02-01"),
        })
        .orThrow(),
    ).toBe(false);
    expect(
      await periods.listPeriods({ kind: "leave_year" }).orThrow(),
    ).toHaveLength(1);
    expect(t.calls.find(([fn]) => fn === "reopen_period")?.[1]).toEqual({
      period_id: "p1",
      reason: "late",
    });
    expect(t.calls.find(([fn]) => fn === "list_periods")?.[1]).toEqual({
      tenant: "org-1",
      filters: { kind: "leave_year" },
    });
  });

  it("reads a keyset page, its facets and its count of periods", async () => {
    const t = fieldsTransport({
      list_periods: (args) => {
        const filters = args["filters"] as Record<string, unknown>;

        if (filters["facet"] !== undefined) {
          return {
            facet: filters["facet"],
            values: [{ value: "leave_year", count: { value: 2, exact: true } }],
          };
        }

        if (filters["count"] === true) {
          return { value: 7, exact: false };
        }

        return { items: [PERIOD], hasMore: true, nextCursor: ["a", "b"] };
      },
    });

    const block = createPeriods({ transport: t, tenant: "org-1" });

    const page = await block
      .periodPage({
        limit: 1,
        sort: { by: "startsOn", direction: "asc" },
        filters: { kind: ["leave_year"] },
      })
      .orThrow();

    const facets = await block.periodFacets({ facets: ["kind"] }).orThrow();
    const count = await block.periodCount().orThrow();

    expect(page.items).toHaveLength(1);
    expect(page).toMatchObject({ hasMore: true, nextCursor: ["a", "b"] });
    expect(t.calls[0]?.[1]).toMatchObject({
      tenant: "org-1",
      filters: { limit: 1, sort: "startsOn", direction: "asc", paged: true },
    });
    expect(facets[0]?.facet).toBe("kind");
    expect(facets[0]?.values[0]?.count).toEqual({ value: 2, exact: true });
    expect(count).toEqual({ value: 7, exact: false });
  });

  it("rejects a sort of periods that is not declared", async () => {
    const t = fieldsTransport({});
    const block = createPeriods({ transport: t, tenant: "org-1" });

    const result = await block.periodPage({ sort: { by: "nope" } });

    expect(result.ok).toBe(false);
    expect(t.calls).toHaveLength(0);
  });
});
