import { describe, expect, it } from "vitest";

import { createApprovals } from "../../src/blocks/approvals/approvals.ts";
import { createAssets } from "../../src/blocks/assets/assets.ts";
import { createCases } from "../../src/blocks/cases/cases.ts";
import { createDeadlines } from "../../src/blocks/deadlines/deadlines.ts";
import { createDispatch } from "../../src/blocks/dispatch/dispatch.ts";
import { createGuests } from "../../src/blocks/guests/guests.ts";
import { createIncidents } from "../../src/blocks/incidents/incidents.ts";
import { fieldsTransport } from "./fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const FACET = {
  facet: "status",
  values: [{ value: "open", count: { value: 2, exact: true } }],
};

const GUEST = {
  id: "g1",
  organizationId: "org-1",
  email: "ada@example.com",
  status: "invited",
  createdAt: AT,
  updatedAt: AT,
};

const WORK_ORDER = {
  id: "w1",
  organizationId: "org-1",
  title: "Fix pump",
  priority: "normal",
  status: "scheduled",
  createdAt: AT,
  updatedAt: AT,
};

const INCIDENT = {
  id: "n1",
  organizationId: "org-1",
  title: "API down",
  severity: "sev2",
  status: "investigating",
  public: false,
  startedAt: AT,
  createdAt: AT,
  updatedAt: AT,
  impacts: [],
};

const REQUEST = {
  id: "r1",
  organizationId: "org-1",
  subjectType: "invoice",
  subjectId: "inv-1",
  action: "pay",
  status: "pending",
  mode: "authorize",
  step: 0,
  steps: [],
  createdAt: AT,
};

const ASSET = {
  id: "a1",
  organizationId: "org-1",
  kind: "vehicle",
  name: "Van 1",
  status: "active",
  metadata: {},
  createdAt: AT,
  updatedAt: AT,
};

const CASE = {
  id: "c1",
  organizationId: "org-1",
  kindId: "k1",
  number: "CASE-1",
  title: "Complaint",
  source: "email",
  status: "open",
  createdAt: AT,
  updatedAt: AT,
};

const DEADLINE = {
  id: "d1",
  organizationId: "org-1",
  subjectType: "matter",
  subjectId: "m1",
  jurisdiction: "NL",
  kind: "appeal",
  groupKey: "appeal",
  ruleVersionId: "v1",
  facts: {},
  result: "due",
  state: "pending",
  dueOn: "2026-12-01",
  provisional: false,
  missing: [],
  review: [],
  asOf: "2026-11-01",
  citation: { reference: "Art. 6" },
  computedAt: AT,
  createdAt: AT,
};

/** The reply of a list function: a page, a facet or a count by its filters. */
const reply =
  (item: unknown) =>
  (args: Record<string, unknown>): unknown => {
    const filters = args["filters"] as Record<string, unknown>;

    if (filters["paged"] === true) {
      return { items: [item], hasMore: true, nextCursor: ["c", "1"] };
    }

    return filters["count"] === true ? { value: 2, exact: true } : FACET;
  };

describe("guests get, page, facets and count", () => {
  it("reads one guest by id", async () => {
    const t = fieldsTransport({ get_guest: () => GUEST });

    const guest = await createGuests({ transport: t, tenant: "org-1" })
      .get("g1")
      .orThrow();

    expect(guest.email).toBe("ada@example.com");
    expect(t.calls).toEqual([["get_guest", { guest_id: "g1" }]]);
  });

  it("pages, counts facets and counts rows", async () => {
    const t = fieldsTransport({ page_guests: reply(GUEST) });
    const guests = createGuests({ transport: t, tenant: "org-1" });

    const page = await guests
      .page({ sort: { by: "email" }, filters: { status: ["invited"] } })
      .orThrow();

    expect(page.items.map((row) => row.id)).toEqual(["g1"]);
    expect(page.nextCursor).toEqual(["c", "1"]);
    await expect(
      guests.facets({ facets: ["status"] }).orThrow(),
    ).resolves.toEqual([FACET]);
    await expect(guests.count().orThrow()).resolves.toEqual({
      value: 2,
      exact: true,
    });
    expect(t.calls[0]).toEqual([
      "page_guests",
      {
        tenant: "org-1",
        filters: { sort: "email", status: ["invited"], paged: true },
      },
    ]);
  });

  it("rejects a search, since guests declare none", async () => {
    const guests = createGuests({
      transport: fieldsTransport({}),
      tenant: "org-1",
    });

    expect((await guests.page({ q: "ada" })).error?.kind).toBe("invalid_input");
  });
});

describe("dispatch page, facets and count", () => {
  it("pages work orders with a sort, filters and text", async () => {
    const t = fieldsTransport({ page_work_orders: reply(WORK_ORDER) });

    const page = await createDispatch({ transport: t, tenant: "org-1" })
      .page({
        sort: { by: "startsAt" },
        filters: { status: ["scheduled"], from: ["2026-11-01T00:00:00Z"] },
        q: "pump",
      })
      .orThrow();

    expect(page.items.map((row) => row.title)).toEqual(["Fix pump"]);
    expect(t.calls[0]).toEqual([
      "page_work_orders",
      {
        tenant: "org-1",
        filters: {
          sort: "startsAt",
          status: ["scheduled"],
          from: ["2026-11-01T00:00:00Z"],
          search: "pump",
          paged: true,
        },
      },
    ]);
  });

  it("counts facets and rows, and rejects an undeclared filter", async () => {
    const dispatch = createDispatch({
      transport: fieldsTransport({ page_work_orders: reply(WORK_ORDER) }),
      tenant: "org-1",
    });

    await expect(
      dispatch.facets({ facets: ["status"] }).orThrow(),
    ).resolves.toEqual([FACET]);
    await expect(dispatch.count().orThrow()).resolves.toEqual({
      value: 2,
      exact: true,
    });
    expect(
      (await dispatch.page({ filters: { colour: ["red"] } })).error?.kind,
    ).toBe("invalid_input");
  });
});

describe("incidents page, facets and count", () => {
  it("pages with the organization of the call", async () => {
    const t = fieldsTransport({ page_incidents: reply(INCIDENT) });
    const incidents = createIncidents({ transport: t });

    const page = await incidents
      .page({
        organizationId: "org-1",
        sort: { by: "severity" },
        filters: { severity: ["sev1", "sev2"], componentId: ["comp-1"] },
        q: "api",
      })
      .orThrow();

    expect(page.items.map((row) => row.title)).toEqual(["API down"]);
    expect(t.calls[0]).toEqual([
      "page_incidents",
      {
        tenant: "org-1",
        filters: {
          sort: "severity",
          severity: ["sev1", "sev2"],
          componentId: ["comp-1"],
          search: "api",
          paged: true,
        },
      },
    ]);
    await expect(
      incidents.count({ organizationId: "org-1" }).orThrow(),
    ).resolves.toEqual({ value: 2, exact: true });
    await expect(
      incidents.facets({ organizationId: "org-1" }).orThrow(),
    ).resolves.toEqual([FACET, FACET]);
  });

  it("rejects an undeclared sort before any request", async () => {
    const t = fieldsTransport({});

    const result = await createIncidents({ transport: t }).page({
      organizationId: "org-1",
      sort: { by: "title" },
    });

    expect(result.error?.kind).toBe("invalid_input");
    expect(t.calls).toEqual([]);
  });
});

describe("approvals page, facets and count", () => {
  it("pages the requests the caller can see", async () => {
    const t = fieldsTransport({ page_approvals: reply(REQUEST) });
    const approvals = createApprovals({ transport: t, tenant: "org-1" });

    const page = await approvals
      .page({ filters: { status: ["pending"], assigned: ["true"] } })
      .orThrow();

    expect(page.items.map((row) => row.id)).toEqual(["r1"]);
    expect(page.hasMore).toBe(true);
    expect(t.calls[0]).toEqual([
      "page_approvals",
      {
        tenant: "org-1",
        filters: { status: ["pending"], assigned: ["true"], paged: true },
      },
    ]);
    await expect(approvals.count().orThrow()).resolves.toEqual({
      value: 2,
      exact: true,
    });
    await expect(
      approvals.facets({ facets: ["status"] }).orThrow(),
    ).resolves.toEqual([FACET]);
  });

  it("rejects a search, since requests declare none", async () => {
    const approvals = createApprovals({
      transport: fieldsTransport({}),
      tenant: "org-1",
    });

    expect((await approvals.page({ q: "pay" })).error?.kind).toBe(
      "invalid_input",
    );
  });
});

describe("assets page, facets and count", () => {
  it("pages with location filters and text", async () => {
    const t = fieldsTransport({ page_assets: reply(ASSET) });
    const assets = createAssets({ transport: t, tenant: "org-1" });

    const page = await assets
      .page({
        sort: { by: "name" },
        filters: { locationId: ["l1"], includeSublocations: ["true"] },
        q: "van",
      })
      .orThrow();

    expect(page.items.map((row) => row.name)).toEqual(["Van 1"]);
    expect(t.calls[0]).toEqual([
      "page_assets",
      {
        tenant: "org-1",
        filters: {
          sort: "name",
          locationId: ["l1"],
          includeSublocations: ["true"],
          search: "van",
          paged: true,
        },
      },
    ]);
    await expect(assets.count().orThrow()).resolves.toEqual({
      value: 2,
      exact: true,
    });
    await expect(
      assets.facets({ facets: ["kind"] }).orThrow(),
    ).resolves.toEqual([FACET]);
  });
});

describe("cases page, facets and count", () => {
  it("pages with filters, a flag and text", async () => {
    const t = fieldsTransport({ page_cases: reply(CASE) });
    const cases = createCases({ transport: t, tenant: "org-1" });

    const page = await cases
      .page({
        sort: { by: "dueOn" },
        filters: { status: ["open"], overdue: ["true"], kind: ["complaint"] },
        q: "refund",
      })
      .orThrow();

    expect(page.items.map((row) => row.number)).toEqual(["CASE-1"]);
    expect(t.calls[0]).toEqual([
      "page_cases",
      {
        tenant: "org-1",
        filters: {
          sort: "dueOn",
          status: ["open"],
          overdue: ["true"],
          kind: ["complaint"],
          search: "refund",
          paged: true,
        },
      },
    ]);
    await expect(cases.count().orThrow()).resolves.toEqual({
      value: 2,
      exact: true,
    });
    await expect(
      cases.facets({ facets: ["severity"] }).orThrow(),
    ).resolves.toEqual([FACET]);
  });

  it("rejects an undeclared facet", async () => {
    const cases = createCases({
      transport: fieldsTransport({}),
      tenant: "org-1",
    });

    expect((await cases.facets({ facets: ["colour"] })).error?.kind).toBe(
      "invalid_input",
    );
  });
});

describe("deadlines get, page, facets and count", () => {
  it("reads one deadline by id", async () => {
    const t = fieldsTransport({ get_deadline: () => DEADLINE });

    const deadline = await createDeadlines({ transport: t, tenant: "org-1" })
      .get("d1")
      .orThrow();

    expect(deadline.id).toBe("d1");
    expect(t.calls).toEqual([["get_deadline", { deadline_id: "d1" }]]);
  });

  it("pages with filters and a date", async () => {
    const t = fieldsTransport({ page_deadlines: reply(DEADLINE) });
    const deadlines = createDeadlines({ transport: t, tenant: "org-1" });

    const page = await deadlines
      .page({
        filters: { state: ["pending"], dueBefore: ["2027-01-01"] },
        sort: { by: "createdAt", direction: "desc" },
      })
      .orThrow();

    expect(page.items.map((row) => row.id)).toEqual(["d1"]);
    expect(t.calls[0]).toEqual([
      "page_deadlines",
      {
        tenant: "org-1",
        filters: {
          sort: "createdAt",
          direction: "desc",
          state: ["pending"],
          dueBefore: ["2027-01-01"],
          paged: true,
        },
      },
    ]);
    await expect(deadlines.count().orThrow()).resolves.toEqual({
      value: 2,
      exact: true,
    });
    await expect(
      deadlines.facets({ facets: ["state"] }).orThrow(),
    ).resolves.toEqual([FACET]);
  });
});
