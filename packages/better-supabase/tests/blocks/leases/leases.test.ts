import { describe, expect, it } from "vitest";

import {
  createLeases,
  leaseInputSchema,
  leasesBlock,
  leasesEvents,
  leasesSection,
  maintenanceRequestInputSchema,
} from "../../../src/blocks/leases/index.ts";
import { money } from "../../../src/commerce/money.ts";

const AT = "2026-10-22T10:00:00Z";
const CONTACT = { type: "contact", id: "c1" };
const UNIT = "00000000-0000-4000-8000-000000000001";

const LEASE = {
  id: "l1",
  organizationId: "org-1",
  unitId: UNIT,
  partyType: "contact",
  partyId: "c1",
  title: "Flat 2 lease",
  status: "active",
  startsOn: "2026-10-01",
  endsOn: "2027-09-30",
  rent: "120000",
  currency: "EUR",
  frequency: "monthly",
  deposit: "240000",
  depositHeld: "240000",
  depositHoldId: "h1",
  balanceDue: "120000",
  renewedAt: AT,
  terminatedOn: null,
  terminationReason: null,
  metadata: { floor: 2 },
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const DRAFT = {
  ...LEASE,
  id: "l2",
  status: "draft",
  endsOn: null,
  depositHeld: "0",
  depositHoldId: null,
  balanceDue: "0",
  renewedAt: null,
  metadata: null,
  createdBy: null,
};

const CHARGE = {
  id: "ch1",
  organizationId: "org-1",
  leaseId: "l1",
  periodStart: "2026-10-01",
  periodEnd: "2026-10-31",
  amount: "120000",
  currency: "EUR",
  transactionId: "t1",
  createdAt: AT,
};

const REQUEST = {
  id: "m1",
  organizationId: "org-1",
  unitId: UNIT,
  leaseId: "l1",
  title: "Leaking tap",
  description: "Kitchen",
  priority: "high",
  status: "resolved",
  reportedBy: "u2",
  assigneeId: "u3",
  resolvedAt: AT,
  createdAt: AT,
  updatedAt: AT,
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

describe("createLeases", () => {
  it("creates a lease with its rent and deposit in minor units", async () => {
    const fake = fakeTransport({ create_lease: LEASE });
    const leases = createLeases({ transport: fake.transport, tenant: "org-1" });

    const lease = await leases
      .create({
        unitId: UNIT,
        party: CONTACT,
        startsOn: Temporal.PlainDate.from("2026-10-01"),
        endsOn: Temporal.PlainDate.from("2027-09-30"),
        rent: money(120_000n, "EUR"),
        deposit: money(240_000n, "EUR"),
        frequency: "monthly",
        title: "Flat 2 lease",
        metadata: { floor: 2 },
      })
      .orThrow();

    expect(fake.calls).toEqual([
      [
        "create_lease",
        {
          tenant: "org-1",
          unit_id: UNIT,
          party_type: "contact",
          party_id: "c1",
          starts_on: "2026-10-01",
          rent: "120000",
          currency: "EUR",
          frequency: "monthly",
          ends_on: "2027-09-30",
          deposit: "240000",
          title: "Flat 2 lease",
          metadata: { floor: 2 },
        },
      ],
    ]);
    expect(lease).toMatchObject({
      id: "l1",
      party: CONTACT,
      status: "active",
      rent: money(120_000n, "EUR"),
      deposit: money(240_000n, "EUR"),
      depositHeld: money(240_000n, "EUR"),
      depositHoldId: "h1",
      balanceDue: money(120_000n, "EUR"),
      metadata: { floor: 2 },
      createdBy: "u1",
    });
    expect(lease.endsOn?.toString()).toBe("2027-09-30");
    expect(lease.renewedAt?.toString()).toBe(AT);
    expect(lease).not.toHaveProperty("terminatedOn");
  });

  it("defaults the frequency and deposit, and leaves out what a draft lacks", async () => {
    const fake = fakeTransport({ create_lease: DRAFT });
    const leases = createLeases({ transport: fake.transport, tenant: "org-1" });

    const lease = await leases
      .create({
        unitId: UNIT,
        party: CONTACT,
        startsOn: Temporal.PlainDate.from("2026-10-01"),
        rent: money(120_000n, "EUR"),
      })
      .orThrow();

    expect(fake.calls[0]?.[1]).toMatchObject({
      frequency: "monthly",
      ends_on: null,
      deposit: "0",
      title: null,
      metadata: null,
    });
    expect(lease.metadata).toEqual({});
    expect(lease).not.toHaveProperty("endsOn");
    expect(lease).not.toHaveProperty("depositHoldId");
    expect(lease).not.toHaveProperty("createdBy");
  });

  it("rejects a deposit in another currency before calling the database", async () => {
    const fake = fakeTransport({});
    const leases = createLeases({ transport: fake.transport, tenant: "org-1" });

    const result = await leases.create({
      unitId: UNIT,
      party: CONTACT,
      startsOn: Temporal.PlainDate.from("2026-10-01"),
      rent: money(120_000n, "EUR"),
      deposit: money(1n, "USD"),
    });

    expect(result.ok).toBe(false);
    expect(result.ok ? undefined : result.error.hint).toBe(
      "LEASE_TERMS_INVALID",
    );
    expect(fake.calls).toEqual([]);
  });

  it("activates, renews, terminates and reads leases", async () => {
    const terminated = {
      ...LEASE,
      status: "terminated",
      terminatedOn: "2027-03-31",
      terminationReason: "moved out",
    };

    const fake = fakeTransport({
      activate_lease: LEASE,
      renew_lease: LEASE,
      terminate_lease: terminated,
      get_lease: LEASE,
      list_leases: [LEASE, DRAFT],
    });

    const leases = createLeases({ transport: fake.transport, tenant: "org-1" });

    await leases.activate("l1").orThrow();
    await leases
      .renew("l1", { endsOn: Temporal.PlainDate.from("2028-09-30") })
      .orThrow();
    await leases
      .renew("l1", {
        endsOn: Temporal.PlainDate.from("2029-09-30"),
        rent: money(125_000n, "EUR"),
      })
      .orThrow();

    const ended = await leases
      .terminate("l1", {
        on: Temporal.PlainDate.from("2027-03-31"),
        reason: "moved out",
        depositDeduction: money(10_000n, "EUR"),
      })
      .orThrow();

    await leases.terminate("l1").orThrow();
    await leases.get("l1").orThrow();

    const list = await leases
      .list({ status: "active", unitId: UNIT, party: CONTACT, pageSize: 10 })
      .orThrow();

    await leases.list().orThrow();

    expect(ended.terminatedOn?.toString()).toBe("2027-03-31");
    expect(ended.terminationReason).toBe("moved out");
    expect(list.map((lease) => lease.id)).toEqual(["l1", "l2"]);
    expect(fake.calls).toEqual([
      ["activate_lease", { lease_id: "l1" }],
      ["renew_lease", { lease_id: "l1", ends_on: "2028-09-30", rent: null }],
      [
        "renew_lease",
        { lease_id: "l1", ends_on: "2029-09-30", rent: "125000" },
      ],
      [
        "terminate_lease",
        {
          lease_id: "l1",
          terminates_on: "2027-03-31",
          reason: "moved out",
          deposit_deduction: "10000",
        },
      ],
      [
        "terminate_lease",
        {
          lease_id: "l1",
          terminates_on: null,
          reason: null,
          deposit_deduction: "0",
        },
      ],
      ["get_lease", { lease_id: "l1" }],
      [
        "list_leases",
        {
          tenant: "org-1",
          status: "active",
          unit_id: UNIT,
          party_type: "contact",
          party_id: "c1",
          page_size: 10,
        },
      ],
      [
        "list_leases",
        {
          tenant: "org-1",
          status: null,
          unit_id: null,
          party_type: null,
          party_id: null,
          page_size: null,
        },
      ],
    ]);
  });

  it("posts due rent, records payments and lists charges", async () => {
    const fake = fakeTransport({
      post_due_rent: 3,
      record_rent_payment: {
        transactionId: "t2",
        leaseId: "l1",
        amount: "120000",
        currency: "EUR",
        balanceDue: "0",
      },
      list_lease_charges: [CHARGE],
    });

    const leases = createLeases({ transport: fake.transport, tenant: "org-1" });

    const posted = await leases
      .postDueRent({
        through: Temporal.PlainDate.from("2026-10-31"),
        maxRows: 50,
      })
      .orThrow();

    await leases.postDueRent().orThrow();

    const payment = await leases
      .recordPayment("l1", {
        amount: money(120_000n, "EUR"),
        paidAt: Temporal.Instant.from(AT),
        reference: "bank-1",
      })
      .orThrow();

    await leases.recordPayment("l1", { amount: money(1n, "EUR") }).orThrow();

    const [charge] = await leases.charges("l1", { pageSize: 5 }).orThrow();
    await leases.charges("l1").orThrow();

    expect(posted).toBe(3);
    expect(payment).toEqual({
      transactionId: "t2",
      leaseId: "l1",
      amount: money(120_000n, "EUR"),
      balanceDue: money(0n, "EUR"),
    });
    expect(charge).toMatchObject({
      id: "ch1",
      amount: money(120_000n, "EUR"),
      transactionId: "t1",
    });
    expect(charge?.periodEnd.toString()).toBe("2026-10-31");
    expect(fake.calls).toEqual([
      [
        "post_due_rent",
        { tenant: "org-1", through: "2026-10-31", max_rows: 50 },
      ],
      ["post_due_rent", { tenant: "org-1", through: null, max_rows: null }],
      [
        "record_rent_payment",
        { lease_id: "l1", amount: "120000", paid_at: AT, reference: "bank-1" },
      ],
      [
        "record_rent_payment",
        { lease_id: "l1", amount: "1", paid_at: null, reference: null },
      ],
      ["list_lease_charges", { lease_id: "l1", page_size: 5 }],
      ["list_lease_charges", { lease_id: "l1", page_size: null }],
    ]);
  });

  it("files, updates and lists maintenance requests", async () => {
    const open = {
      ...REQUEST,
      leaseId: null,
      description: null,
      priority: "normal",
      status: "open",
      reportedBy: null,
      assigneeId: null,
      resolvedAt: null,
    };

    const fake = fakeTransport({
      file_maintenance_request: open,
      update_maintenance_request: REQUEST,
      list_maintenance_requests: [REQUEST],
    });

    const leases = createLeases({ transport: fake.transport, tenant: "org-1" });

    const filed = await leases
      .fileMaintenance({ unitId: UNIT, title: "Leaking tap" })
      .orThrow();

    await leases
      .fileMaintenance({
        unitId: UNIT,
        title: "Leaking tap",
        description: "Kitchen",
        priority: "high",
        leaseId: "l1",
      })
      .orThrow();

    const resolved = await leases
      .updateMaintenance("m1", {
        status: "resolved",
        priority: "high",
        assigneeId: "u3",
      })
      .orThrow();

    await leases.updateMaintenance("m1", {}).orThrow();
    await leases
      .listMaintenance({
        unitId: UNIT,
        leaseId: "l1",
        status: "open",
        pageSize: 5,
      })
      .orThrow();
    await leases.listMaintenance().orThrow();

    expect(filed).not.toHaveProperty("leaseId");
    expect(filed).not.toHaveProperty("resolvedAt");
    expect(resolved).toMatchObject({
      leaseId: "l1",
      description: "Kitchen",
      reportedBy: "u2",
      assigneeId: "u3",
    });
    expect(resolved.resolvedAt?.toString()).toBe(AT);
    expect(fake.calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "file_maintenance_request",
        {
          tenant: "org-1",
          unit_id: UNIT,
          title: "Leaking tap",
          description: null,
          priority: "normal",
          lease_id: null,
        },
      ],
      [
        "file_maintenance_request",
        {
          tenant: "org-1",
          unit_id: UNIT,
          title: "Leaking tap",
          description: "Kitchen",
          priority: "high",
          lease_id: "l1",
        },
      ],
      [
        "update_maintenance_request",
        {
          request_id: "m1",
          status: "resolved",
          priority: "high",
          assignee_id: "u3",
        },
      ],
      [
        "update_maintenance_request",
        { request_id: "m1", status: null, priority: null, assignee_id: null },
      ],
      [
        "list_maintenance_requests",
        {
          tenant: "org-1",
          unit_id: UNIT,
          lease_id: "l1",
          status: "open",
          page_size: 5,
        },
      ],
      [
        "list_maintenance_requests",
        {
          tenant: "org-1",
          unit_id: null,
          lease_id: null,
          status: null,
          page_size: null,
        },
      ],
    ]);
  });

  it("rejects malformed rows and a missing count", async () => {
    const leases = createLeases({
      transport: fakeTransport({
        post_due_rent: "many",
        get_lease: { ...LEASE, currency: null },
      }).transport,
      tenant: "org-1",
    });

    expect((await leases.postDueRent()).ok).toBe(false);
    expect((await leases.get("l1")).ok).toBe(false);
  });

  it("fails without a tenant", async () => {
    const leases = createLeases({ transport: fakeTransport({}).transport });

    expect((await leases.list()).ok).toBe(false);
  });

  it("runs hooks and logs to the logger it gets", async () => {
    const seen: string[] = [];

    const leases = createLeases({
      transport: fakeTransport({ get_lease: LEASE }).transport,
      hooks: {
        get: {
          before: (_args, info) => {
            seen.push(info.method);
          },
        },
      },
      logger: console,
    });

    await leases.get("l1").orThrow();

    expect(seen).toEqual(["get"]);
  });
});

describe("leases block", () => {
  it("loads a party's leases through the section", async () => {
    const fake = fakeTransport({ list_leases: [LEASE] });
    const leases = createLeases({ transport: fake.transport, tenant: "org-1" });

    const loaded = await leasesSection.load(leases, CONTACT, undefined);

    expect(loaded.ok).toBe(true);
    expect(fake.calls[0]?.[1]).toMatchObject({
      party_type: "contact",
      party_id: "c1",
    });
    expect(leasesBlock.name).toBe("leases");
    expect(leasesBlock.sql).toEqual(["leases"]);
    expect(leasesEvents.types).toContain("lease.charged");
  });

  it("validates the inputs", () => {
    expect(
      validate(leaseInputSchema, {
        unitId: UNIT,
        party: CONTACT,
        startsOn: Temporal.PlainDate.from("2026-10-01"),
        rent: { amount: 120_000n, currency: "EUR" },
      }).issues,
    ).toBeUndefined();
    expect(validate(leaseInputSchema, { unitId: UNIT }).issues).toBeDefined();
    expect(
      validate(maintenanceRequestInputSchema, { unitId: UNIT, title: "Tap" })
        .issues,
    ).toBeUndefined();
    expect(
      validate(maintenanceRequestInputSchema, {
        unitId: UNIT,
        title: "Tap",
        priority: "whenever",
      }).issues,
    ).toBeDefined();
  });
});
