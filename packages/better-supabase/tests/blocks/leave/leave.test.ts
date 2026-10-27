import { describe, expect, it } from "vitest";

import { createLeave } from "../../../src/blocks/leave/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("better_supabase");
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const AT = "2026-10-06T09:00:00Z";

const TYPE = {
  id: "t1",
  organizationId: "o",
  key: "vacation",
  name: "Vacation",
  unit: "days",
  paid: true,
  tracked: true,
  allowance: "25.00",
  carryoverMax: null,
  color: null,
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const REQUEST = {
  id: "q1",
  organizationId: "o",
  userId: "u1",
  typeId: "t1",
  startsOn: "2026-10-19",
  endsOn: "2026-10-23",
  partial: "full",
  amount: "5.00",
  note: null,
  status: "pending",
  approvalId: "a1",
  approvedAt: null,
  cancelledAt: null,
  createdAt: AT,
  updatedAt: AT,
  fields: {},
};

const ENTRY = {
  id: "l1",
  organizationId: "o",
  userId: "u1",
  typeId: "t1",
  kind: "grant",
  amount: "-1.50",
  period: 2026,
  requestId: null,
  note: "Correction",
  createdAt: AT,
};

describe("leave client", () => {
  it("saves and lists types with decimal allowances", async () => {
    const fake = transport({
      save_leave_type: () => TYPE,
      list_leave_types: () => [TYPE],
      archive_leave_type: () => ({ ...TYPE, archivedAt: AT }),
    });

    const leave = createLeave({ transport: fake });

    const type = await leave
      .saveType("o", { key: "vacation", name: "Vacation", allowance: 25 })
      .orThrow();

    expect(type).toMatchObject({ unit: "days", allowance: 25, tracked: true });
    expect(type.carryoverMax).toBeUndefined();
    expect(await leave.types("o").orThrow()).toHaveLength(1);
    expect(
      (await leave.archiveType("t1").orThrow()).archivedAt?.toString(),
    ).toBe(AT);
    expect(fake.calls.slice(0, 2)).toEqual([
      [
        "save_leave_type",
        {
          tenant: "o",
          key: "vacation",
          name: "Vacation",
          unit: "days",
          paid: true,
          tracked: true,
          allowance: 25,
          carryover_max: null,
          color: null,
        },
      ],
      ["list_leave_types", { tenant: "o", archived: false }],
    ]);
  });

  it("requests leave with plain dates and reads it back", async () => {
    const fake = transport({
      request_leave: () => REQUEST,
      list_leave_requests: () => [REQUEST],
      cancel_leave_request: () => ({
        ...REQUEST,
        status: "cancelled",
        cancelledAt: AT,
      }),
    });

    const leave = createLeave({ transport: fake });
    const day = Temporal.PlainDate.from("2026-10-19");

    const request = await leave
      .request("o", { typeId: "t1", startsOn: day })
      .orThrow();

    expect(request.amount).toBe(5);
    expect(request.endsOn.toString()).toBe("2026-10-23");
    expect(request.approvalId).toBe("a1");
    expect(request.note).toBeUndefined();
    await leave
      .list("o", { everyone: true, status: "approved", from: day })
      .orThrow();
    expect((await leave.cancel("q1").orThrow()).status).toBe("cancelled");
    expect(fake.calls).toEqual([
      [
        "request_leave",
        {
          tenant: "o",
          type_id: "t1",
          starts_on: "2026-10-19",
          ends_on: "2026-10-19",
          partial: "full",
          hours: null,
          note: null,
        },
      ],
      [
        "list_leave_requests",
        {
          tenant: "o",
          user_id: null,
          status: "approved",
          starts: "2026-10-19",
          ends: null,
          everyone: true,
          page_size: null,
        },
      ],
      ["cancel_leave_request", { request_id: "q1" }],
    ]);
  });

  it("reads balances and the ledger as numbers", async () => {
    const fake = transport({
      leave_balances: () => [
        {
          typeId: "t1",
          key: "vacation",
          name: "Vacation",
          unit: "days",
          userId: "u1",
          period: 2026,
          granted: "25.00",
          taken: "3.50",
          pending: "5.00",
          available: "16.50",
        },
      ],
      leave_ledger_entries: () => [ENTRY],
    });

    const leave = createLeave({ transport: fake });

    expect(await leave.balances("o").orThrow()).toEqual([
      {
        typeId: "t1",
        key: "vacation",
        name: "Vacation",
        unit: "days",
        userId: "u1",
        period: 2026,
        granted: 25,
        taken: 3.5,
        pending: 5,
        available: 16.5,
      },
    ]);
    const [entry] = await leave.ledger("o", { period: 2026 }).orThrow();
    expect(entry).toMatchObject({
      kind: "grant",
      amount: -1.5,
      note: "Correction",
    });
    expect(entry?.requestId).toBeUndefined();
  });

  it("adjusts, accrues and closes a year", async () => {
    const fake = transport({
      adjust_leave_balance: () => ENTRY,
      accrue_leave: () => 4,
      close_leave_year: () => 0,
    });

    const leave = createLeave({ transport: fake });

    await leave
      .adjust("o", {
        userId: "u1",
        typeId: "t1",
        amount: -1.5,
        note: "Correction",
      })
      .orThrow();
    expect(
      await leave
        .accrue("o", { typeId: "t1", idempotencyKey: "2026-10" })
        .orThrow(),
    ).toBe(4);
    expect(await leave.closePeriod("o", 2026).orThrow()).toBe(0);
    expect(fake.calls).toEqual([
      [
        "adjust_leave_balance",
        {
          tenant: "o",
          user_id: "u1",
          type_id: "t1",
          amount: -1.5,
          period: null,
          kind: "adjustment",
          note: "Correction",
        },
      ],
      [
        "accrue_leave",
        {
          tenant: "o",
          type_id: "t1",
          amount: null,
          period: null,
          user_ids: null,
          idempotency_key: "2026-10",
          note: null,
        },
      ],
      ["close_leave_year", { tenant: "o", period: 2026 }],
    ]);
  });

  it("decides a request and reads a leave feed", async () => {
    const fake = transport({
      decide_leave_request: () => ({
        ...REQUEST,
        status: "approved",
        approvalId: null,
        approvedAt: AT,
      }),
      leave_feed: (args) =>
        (args as { token: string }).token === "known"
          ? {
              organizationId: "o",
              requests: [
                {
                  id: "q1",
                  userId: "u1",
                  typeId: "t1",
                  type: "Vacation",
                  unit: "days",
                  startsOn: "2026-10-19",
                  endsOn: "2026-10-23",
                  partial: "full",
                  amount: "5.00",
                  approvedAt: AT,
                  updatedAt: AT,
                },
              ],
            }
          : null,
    });

    const leave = createLeave({ transport: fake });
    const decided = await leave.decide("q1", { approved: true }).orThrow();
    const feed = await leave.feed("known").orThrow();

    expect(fake.calls[0]).toEqual([
      "decide_leave_request",
      { request_id: "q1", approved: true, note: null },
    ]);
    expect(decided.status).toBe("approved");
    expect(decided.approvalId).toBeUndefined();
    expect(feed?.requests[0]).toMatchObject({ type: "Vacation", amount: 5 });
    expect(feed?.requests[0]?.startsOn.toString()).toBe("2026-10-19");
    expect(await leave.feed("unknown").orThrow()).toBeNull();
  });
});
