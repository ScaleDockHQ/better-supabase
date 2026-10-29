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
  it("changes and splits requests, saves auto-approved types and reads team feeds", async () => {
    const fake = transport({
      save_leave_type: () => ({ ...TYPE, autoApprove: true }),
      update_leave_request: () => ({ ...REQUEST, endsOn: "2026-10-21" }),
      split_leave_request: () => ({
        request: { ...REQUEST, status: "approved" },
        split: { ...REQUEST, id: "q2", status: "approved" },
      }),
      leave_feed: () => ({
        organizationId: "o",
        teamId: "team-1",
        requests: [
          {
            id: "q1",
            userId: "u1",
            name: "Alice",
            typeId: "t1",
            type: null,
            unit: "days",
            startsOn: "2026-10-19",
            endsOn: "2026-10-19",
            partial: "afternoon",
            startPart: "afternoon",
            endPart: "full",
            amount: "0.5",
            approvedAt: AT,
            updatedAt: AT,
          },
        ],
      }),
    });

    const leave = createLeave({ transport: fake });

    expect(
      (
        await leave
          .saveType("o", { key: "sick", name: "Sick", autoApprove: true })
          .orThrow()
      ).autoApprove,
    ).toBe(true);
    await leave
      .update("q1", { endsOn: Temporal.PlainDate.from("2026-10-21"), note: "" })
      .orThrow();

    const split = await leave
      .split("q1", {
        gapStarts: Temporal.PlainDate.from("2026-10-20"),
        gapEnds: Temporal.PlainDate.from("2026-10-21"),
      })
      .orThrow();

    expect(split.split.id).toBe("q2");
    const feed = await leave.feed("t".repeat(40)).orThrow();
    expect(feed).toMatchObject({
      teamId: "team-1",
      requests: [{ name: "Alice", startPart: "afternoon" }],
    });
    expect(feed?.requests[0]?.type).toBeUndefined();
    expect(fake.calls.slice(0, 3)).toEqual([
      ["save_leave_type", expect.objectContaining({ auto_approve: true })],
      [
        "update_leave_request",
        {
          request_id: "q1",
          starts_on: null,
          ends_on: "2026-10-21",
          partial: null,
          hours: null,
          note: "",
        },
      ],
      [
        "split_leave_request",
        { request_id: "q1", gap_starts: "2026-10-20", gap_ends: "2026-10-21" },
      ],
    ]);
  });

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

  it("requests and adjusts leave for an employee with parts of the day", async () => {
    const employeeRequest = {
      ...REQUEST,
      userId: null,
      employeeId: "e1",
      startPart: "afternoon",
      endPart: "morning",
      amount: "20.00",
    };

    const fake = transport({
      request_leave: () => employeeRequest,
      adjust_leave_balance: () => ({
        ...ENTRY,
        userId: null,
        employeeId: "e1",
        expiresOn: "2026-12-31",
      }),
      accrue_leave: () => 1,
    });

    const leave = createLeave({ transport: fake });
    const day = Temporal.PlainDate.from("2026-10-19");

    const request = await leave
      .request("o", {
        typeId: "t1",
        startsOn: day,
        endsOn: day.add({ days: 2 }),
        startPart: "afternoon",
        endPart: "morning",
        hours: 20,
        employeeId: "e1",
      })
      .orThrow();

    expect(request).toMatchObject({
      employeeId: "e1",
      startPart: "afternoon",
      endPart: "morning",
      amount: 20,
    });
    expect(request.userId).toBeUndefined();

    const entry = await leave
      .adjust("o", {
        employeeId: "e1",
        typeId: "t1",
        amount: 8,
        expiresOn: Temporal.PlainDate.from("2026-12-31"),
      })
      .orThrow();

    expect(entry.employeeId).toBe("e1");
    expect(entry.expiresOn?.toString()).toBe("2026-12-31");
    await leave.accrue("o", { typeId: "t1", employeeIds: ["e1"] }).orThrow();
    expect(fake.calls).toEqual([
      [
        "request_leave",
        {
          tenant: "o",
          type_id: "t1",
          starts_on: "2026-10-19",
          ends_on: "2026-10-21",
          partial: "full",
          hours: 20,
          note: null,
          start_part: "afternoon",
          end_part: "morning",
          employee_id: "e1",
        },
      ],
      [
        "adjust_leave_balance",
        {
          tenant: "o",
          user_id: null,
          type_id: "t1",
          amount: 8,
          period: null,
          kind: "adjustment",
          note: null,
          employee_id: "e1",
          expires_on: "2026-12-31",
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
          idempotency_key: null,
          note: null,
          employee_ids: ["e1"],
        },
      ],
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

  it("dates adjustments and accruals and reads busy entries and names in a feed", async () => {
    const fake = transport({
      adjust_leave_balance: () => ENTRY,
      accrue_leave: () => 2,
      leave_feed: () => ({
        organizationId: "o",
        organizationName: "Acme",
        teamId: "team-1",
        teamName: "Support",
        requests: [],
        busy: [
          {
            id: "q9",
            employeeId: "e1",
            name: "Dana",
            startsOn: "2026-10-19",
            endsOn: "2026-10-20",
            partial: "full",
            startPart: "full",
            endPart: "full",
            updatedAt: AT,
          },
        ],
      }),
    });

    const leave = createLeave({ transport: fake });

    await leave
      .adjust("o", {
        userId: "u1",
        typeId: "t1",
        amount: 2,
        effectiveOn: Temporal.PlainDate.from("2026-01-15"),
      })
      .orThrow();
    await leave
      .accrue("o", {
        typeId: "t1",
        effectiveOn: Temporal.PlainDate.from("2026-11-01"),
      })
      .orThrow();

    const feed = await leave.feed("t".repeat(40)).orThrow();

    expect(fake.calls[0]?.[1]).toMatchObject({ effective_on: "2026-01-15" });
    expect(fake.calls[1]?.[1]).toMatchObject({ effective_on: "2026-11-01" });
    expect(feed).toMatchObject({
      organizationName: "Acme",
      teamName: "Support",
      busy: [{ id: "q9", employeeId: "e1", name: "Dana", partial: "full" }],
    });
    expect(feed?.busy?.[0]?.endsOn.toString()).toBe("2026-10-20");
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
