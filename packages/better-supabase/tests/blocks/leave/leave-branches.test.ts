import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createLeave } from "../../../src/blocks/leave/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
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

const REQUEST = {
  id: "q1",
  organizationId: "o",
  userId: "u1",
  typeId: "t1",
  startsOn: "2026-10-19",
  endsOn: "2026-10-23",
  partial: "full",
  amount: "5.00",
  status: "approved",
  createdAt: AT,
  updatedAt: AT,
};

const TYPE = {
  id: "t1",
  organizationId: "o",
  key: "vacation",
  name: "Vacation",
  unit: "hours",
  paid: false,
  tracked: false,
  allowance: "8.00",
  carryoverMax: "2.50",
  color: "#fff",
  autoApprove: false,
  createdAt: AT,
  updatedAt: AT,
};

const DAY = Temporal.PlainDate.from("2026-10-19");

describe("leave branches", () => {
  it("counts working days and rejects a non-number answer", async () => {
    const ok = createLeave({
      transport: transport({ leave_working_days: () => 3 }),
    });

    expect(
      await ok.workingDays({ from: DAY, to: DAY.add({ days: 4 }) }).orThrow(),
    ).toBe(3);

    const bad = createLeave({
      transport: transport({ leave_working_days: () => "3" }),
    });

    const result = await bad.workingDays({ from: DAY, to: DAY });

    expect(result.ok).toBe(false);
  });

  it("approves, rejects and lists pending requests through decide and list", async () => {
    const fake = transport({
      decide_leave_request: () => REQUEST,
      list_leave_requests: () => [REQUEST],
    });

    const leave = createLeave({ transport: fake });

    await leave.approve({ requestId: "q1" }).orThrow();
    await leave
      .approve({ requestId: "q1", note: "ok", decidedBy: "u9" })
      .orThrow();
    await leave.reject({ requestId: "q1" }).orThrow();
    await leave
      .reject({ requestId: "q1", note: "no", decidedBy: "u8" })
      .orThrow();
    await leave.pending({ organizationId: "o" }).orThrow();

    expect(fake.calls.map(([fn]) => fn)).toEqual([
      "decide_leave_request",
      "decide_leave_request",
      "decide_leave_request",
      "decide_leave_request",
      "list_leave_requests",
    ]);
    expect(fake.calls[0]?.[1]).toEqual({
      request_id: "q1",
      approved: true,
      note: null,
    });
    expect(fake.calls[1]?.[1]).toEqual({
      request_id: "q1",
      approved: true,
      note: "ok",
      decided_by: "u9",
    });
    expect(fake.calls[2]?.[1]).toEqual({
      request_id: "q1",
      approved: false,
      note: null,
    });
    expect(fake.calls[3]?.[1]).toMatchObject({
      approved: false,
      note: "no",
      decided_by: "u8",
    });
    expect(fake.calls[4]?.[1]).toMatchObject({ status: "pending" });
  });

  it("closes a period and returns the count", async () => {
    const fake = transport({ close_leave_year: () => "4" });
    const leave = createLeave({ transport: fake });

    expect(
      await leave.closePeriod({ organizationId: "o", period: 2026 }).orThrow(),
    ).toBe(4);
    expect(fake.calls[0]).toEqual([
      "close_leave_year",
      { tenant: "o", period: 2026 },
    ]);
  });

  it("parses a full type row and sends optional type arguments", async () => {
    const fake = transport({
      save_leave_type: () => TYPE,
      list_leave_types: () => [TYPE],
    });

    const leave = createLeave({ transport: fake });

    const type = await leave
      .saveType({
        organizationId: "o",
        input: {
          key: "vacation",
          name: "Vacation",
          unit: "hours",
          paid: false,
          tracked: false,
          allowance: 8,
          carryoverMax: 2.5,
          color: "#fff",
          autoApprove: false,
        },
      })
      .orThrow();

    expect(type).toMatchObject({
      unit: "hours",
      allowance: 8,
      carryoverMax: 2.5,
      color: "#fff",
      autoApprove: false,
      paid: false,
      tracked: false,
    });
    expect(fake.calls[0]?.[1]).toMatchObject({
      unit: "hours",
      paid: false,
      tracked: false,
      carryover_max: 2.5,
      color: "#fff",
      auto_approve: false,
    });

    await leave.types({ organizationId: "o", archived: true }).orThrow();
    expect(fake.calls[1]?.[1]).toEqual({ tenant: "o", archived: true });
  });

  it("sends the optional request, update and list arguments", async () => {
    const fake = transport({
      request_leave: () => REQUEST,
      update_leave_request: () => REQUEST,
      list_leave_requests: () => [REQUEST],
      leave_balances: () => [],
      leave_ledger_entries: () => [],
      adjust_leave_balance: () => ({
        id: "l1",
        organizationId: "o",
        userId: "u1",
        typeId: "t1",
        kind: "adjustment",
        amount: 1,
        period: "2026",
        createdAt: AT,
      }),
      accrue_leave: () => 2,
    });

    const leave = createLeave({ transport: fake });

    await leave
      .update({
        requestId: "q1",
        update: {
          startsOn: DAY,
          endsOn: DAY,
          partial: "morning",
          hours: 4,
          note: "n",
          startPart: "morning",
          endPart: "full",
        },
      })
      .orThrow();
    await leave
      .list({
        organizationId: "o",
        userId: "u1",
        to: DAY,
        pageSize: 10,
        employeeId: "e1",
      })
      .orThrow();
    await leave
      .balances({
        organizationId: "o",
        userId: "u1",
        period: 2026,
        employeeId: "e1",
      })
      .orThrow();
    await leave
      .ledger({
        organizationId: "o",
        userId: "u1",
        typeId: "t1",
        employeeId: "e1",
      })
      .orThrow();

    const entry = await leave
      .adjust({
        organizationId: "o",
        adjustment: {
          userId: "u1",
          typeId: "t1",
          amount: 1,
          period: 2026,
          kind: "grant",
          note: "n",
          effectiveOn: DAY,
        },
      })
      .orThrow();

    expect(entry.period).toBe(2026);

    await leave
      .accrue({
        organizationId: "o",
        accrual: {
          typeId: "t1",
          amount: 2,
          period: 2026,
          userIds: ["u1"],
          idempotencyKey: "k",
          note: "n",
          effectiveOn: DAY,
        },
      })
      .orThrow();

    const byFn = Object.fromEntries(fake.calls);

    expect(byFn["update_leave_request"]).toMatchObject({
      starts_on: "2026-10-19",
      partial: "morning",
      hours: 4,
      start_part: "morning",
      end_part: "full",
    });
    expect(byFn["list_leave_requests"]).toMatchObject({
      user_id: "u1",
      ends: "2026-10-19",
      page_size: 10,
      employee_id: "e1",
    });
    expect(byFn["leave_balances"]).toMatchObject({
      period: 2026,
      employee_id: "e1",
    });
    expect(byFn["leave_ledger_entries"]).toMatchObject({
      type_id: "t1",
      employee_id: "e1",
    });
    expect(byFn["adjust_leave_balance"]).toMatchObject({
      kind: "grant",
      effective_on: "2026-10-19",
    });
    expect(byFn["accrue_leave"]).toMatchObject({
      amount: 2,
      user_ids: ["u1"],
      idempotency_key: "k",
      effective_on: "2026-10-19",
    });
  });

  it("reads a missing feed as null and a feed with busy entries and requests", async () => {
    const entry = {
      id: "q1",
      employeeId: "e1",
      name: "Al",
      typeId: "t1",
      type: "Vacation",
      startsOn: "2026-10-19",
      endsOn: "2026-10-20",
      partial: "full",
      startPart: "morning",
      endPart: "full",
      amount: "2",
      updatedAt: AT,
      fields: { team: "x" },
    };

    const fake = transport({
      leave_feed: (args) =>
        // SAFETY: the test always passes a token argument.
        (args as { token: string }).token === "gone"
          ? null
          : {
              organizationId: "o",
              organizationName: "Org",
              teamId: "tm",
              teamName: "Team",
              busy: [entry],
              requests: [entry],
            },
    });

    const leave = createLeave({ transport: fake });

    expect(await leave.feed("gone").orThrow()).toBeNull();

    const feed = await leave.feed("here").orThrow();

    expect(feed).toMatchObject({
      organizationName: "Org",
      teamName: "Team",
      busy: [{ employeeId: "e1", name: "Al", startPart: "morning" }],
      requests: [{ type: "Vacation", amount: 2, fields: { team: "x" } }],
    });
  });

  it("parses request rows with every optional column", async () => {
    const fake = transport({
      cancel_leave_request: () => ({
        ...REQUEST,
        note: "n",
        startPart: "morning",
        endPart: "afternoon",
        approvalId: "a1",
        approvedAt: AT,
        cancelledAt: AT,
        fields: { k: 1 },
      }),
    });

    const leave = createLeave({ transport: fake });

    const request = await leave.cancel("q1").orThrow();

    expect(request).toMatchObject({
      note: "n",
      startPart: "morning",
      endPart: "afternoon",
      approvalId: "a1",
      fields: { k: 1 },
    });
    expect(request.approvedAt).toBeDefined();
    expect(request.cancelledAt).toBeDefined();
  });

  it("validates custom fields on request and update, and logs through a logger", async () => {
    const fake = transport({
      request_leave: () => ({ ...REQUEST, fields: { level: "a" } }),
      update_leave_request: () => ({ ...REQUEST, fields: { level: "b" } }),
    });

    const leave = createLeave({
      transport: fake,
      fields: v.object({ level: v.string() }),
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
    });

    const created = await leave
      .request({
        organizationId: "o",
        input: { typeId: "t1", startsOn: DAY, fields: { level: "a" } },
      })
      .orThrow();

    expect(created.fields).toEqual({ level: "a" });
    expect(fake.calls[0]?.[1]).toMatchObject({ fields: { level: "a" } });

    await leave
      .update({ requestId: "q1", update: { fields: { level: "b" } } })
      .orThrow();
    expect(fake.calls[1]?.[1]).toMatchObject({ fields: { level: "b" } });
  });

  it("reads a decimal that is missing as zero", async () => {
    const fake = transport({
      cancel_leave_request: () => ({ ...REQUEST, amount: undefined }),
    });

    const leave = createLeave({ transport: fake });

    expect((await leave.cancel("q1").orThrow()).amount).toBe(0);
  });
});
