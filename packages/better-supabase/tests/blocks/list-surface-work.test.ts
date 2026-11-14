import { describe, expect, it } from "vitest";

import { createInspections } from "../../src/blocks/inspections/inspections.ts";
import { createMeetings } from "../../src/blocks/meetings/meetings.ts";
import { createWarranty } from "../../src/blocks/warranty/warranty.ts";
import { fieldsTransport } from "./fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const INSPECTION = {
  id: "i1",
  organizationId: "org-1",
  number: "AUD-2026-001",
  kind: "internal_audit",
  title: "Warehouse audit",
  status: "planned",
  createdAt: AT,
  updatedAt: AT,
};

const MEETING = {
  id: "m1",
  organizationId: "org-1",
  title: "Board",
  kind: "board",
  status: "planned",
  startsAt: AT,
  createdAt: AT,
  updatedAt: AT,
};

const CLAIM = {
  id: "c1",
  organizationId: "org-1",
  title: "Broken seal",
  assetId: "a1",
  amount: "1000",
  currency: "EUR",
  status: "submitted",
  manufacturer: "Acme",
};

const FACET = {
  facet: "status",
  values: [{ value: "planned", count: { value: 2, exact: true } }],
};

describe("inspections page, facets and count", () => {
  it("pages with a sort, list filters, dates and text", async () => {
    const t = fieldsTransport({
      list_inspections: () => ({
        items: [INSPECTION],
        hasMore: true,
        nextCursor: ["2026-11-02", "1", "i1"],
      }),
    });

    const page = await createInspections({ transport: t, tenant: "org-1" })
      .page({
        limit: 1,
        sort: { by: "number", direction: "asc" },
        filters: { status: ["planned", "in_progress"], from: ["2026-11-01"] },
        q: "warehouse",
      })
      .orThrow();

    expect(page.items.map((row) => row.number)).toEqual(["AUD-2026-001"]);
    expect(page.hasMore).toBe(true);
    expect(t.calls).toEqual([
      [
        "list_inspections",
        {
          tenant: "org-1",
          filters: {
            sort: "number",
            direction: "asc",
            status: ["planned", "in_progress"],
            from: ["2026-11-01"],
            search: "warehouse",
            limit: 1,
            paged: true,
          },
        },
      ],
    ]);
  });

  it("counts facets and rows under the same filters", async () => {
    const t = fieldsTransport({
      list_inspections: (args) =>
        (args["filters"] as Record<string, unknown>)["count"] === true
          ? { value: 2, exact: true }
          : FACET,
    });

    const inspections = createInspections({ transport: t, tenant: "org-1" });
    const filters = { kind: ["internal_audit"] };

    await expect(
      inspections.facets({ facets: ["status"], filters }).orThrow(),
    ).resolves.toEqual([FACET]);
    await expect(inspections.count({ filters }).orThrow()).resolves.toEqual({
      value: 2,
      exact: true,
    });
  });

  it("rejects what the entity does not declare", async () => {
    const t = fieldsTransport({});
    const inspections = createInspections({ transport: t, tenant: "org-1" });

    for (const result of [
      await inspections.page({ sort: { by: "title" } }),
      await inspections.page({ filters: { colour: ["red"] } }),
      await inspections.facets({ facets: ["colour"] }),
    ]) {
      expect(result.ok).toBe(false);
      expect(result.error?.kind).toBe("invalid_input");
    }

    expect(t.calls).toEqual([]);
  });
});

describe("meetings page, facets and count", () => {
  it("pages with a sort, list filters and text", async () => {
    const t = fieldsTransport({
      list_meetings: () => ({ items: [MEETING], hasMore: false }),
    });

    const page = await createMeetings({ transport: t, tenant: "org-1" })
      .page({
        sort: { by: "title" },
        filters: { kind: ["board", "team"], attendeeId: ["u1"] },
        q: "budget",
      })
      .orThrow();

    expect(page.items.map((row) => row.title)).toEqual(["Board"]);
    expect(t.calls).toEqual([
      [
        "list_meetings",
        {
          tenant: "org-1",
          filters: {
            sort: "title",
            kind: ["board", "team"],
            attendeeId: ["u1"],
            search: "budget",
            paged: true,
          },
        },
      ],
    ]);
  });

  it("counts facets and rows", async () => {
    const t = fieldsTransport({
      list_meetings: (args) =>
        (args["filters"] as Record<string, unknown>)["count"] === true
          ? { value: 4, exact: false }
          : FACET,
    });

    const meetings = createMeetings({ transport: t, tenant: "org-1" });

    await expect(
      meetings.facets({ facets: ["status"] }).orThrow(),
    ).resolves.toEqual([FACET]);
    await expect(meetings.count().orThrow()).resolves.toEqual({
      value: 4,
      exact: false,
    });
  });

  it("rejects an undeclared filter", async () => {
    const meetings = createMeetings({
      transport: fieldsTransport({}),
      tenant: "org-1",
    });

    const result = await meetings.page({ filters: { colour: ["red"] } });

    expect(result.error?.kind).toBe("invalid_input");
  });
});

describe("warranty get, page, facets and count", () => {
  it("reads one claim by id", async () => {
    const t = fieldsTransport({ get_warranty_claim: () => CLAIM });

    const claim = await createWarranty({ transport: t, tenant: "org-1" })
      .get("c1")
      .orThrow();

    expect(claim).toMatchObject({ id: "c1", amount: 1000n });
    expect(t.calls).toEqual([["get_warranty_claim", { claim_id: "c1" }]]);
  });

  it("pages, counts facets and counts rows", async () => {
    const t = fieldsTransport({
      list_warranty_claims: (args) => {
        const filters = args["filters"] as Record<string, unknown>;

        if (filters["paged"] === true) {
          return { items: [CLAIM], hasMore: false };
        }

        return filters["count"] === true ? { value: 1, exact: true } : FACET;
      },
    });

    const warranty = createWarranty({ transport: t, tenant: "org-1" });

    const page = await warranty
      .page({ sort: { by: "amount" }, filters: { status: ["submitted"] } })
      .orThrow();

    expect(page.items).toHaveLength(1);
    await expect(
      warranty.facets({ facets: ["status"] }).orThrow(),
    ).resolves.toEqual([FACET]);
    await expect(warranty.count().orThrow()).resolves.toEqual({
      value: 1,
      exact: true,
    });
    expect(t.calls[0]).toEqual([
      "list_warranty_claims",
      {
        tenant: "org-1",
        filters: { sort: "amount", status: ["submitted"], paged: true },
      },
    ]);
  });

  it("rejects a search, since claims declare none", async () => {
    const warranty = createWarranty({
      transport: fieldsTransport({}),
      tenant: "org-1",
    });

    const result = await warranty.page({ q: "seal" });

    expect(result.error?.kind).toBe("invalid_input");
  });
});
