import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createLeave, sqlTransport } from "../../src/blocks/leave/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "outbox", "approvals", "leave"];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

describe.skipIf(!live)("leave", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("books approved leave against a balance and gives it back on cancel", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      const stranger = await s.user("stranger");
      await s.install(MODULES, {});
      const tenant = await s.organization(owner, { member: ada });
      const leave = createLeave({ transport: sqlTransport(s.sql) });

      await s.as(ada);
      expect(
        await leave
          .saveType(tenant, { key: "vacation", name: "Vacation" })
          .then(hint),
      ).toBe("LEAVE_FORBIDDEN");

      await s.as(owner);

      const vacation = await leave
        .saveType(tenant, {
          key: "vacation",
          name: "Vacation",
          allowance: 25,
          carryoverMax: 5,
        })
        .orThrow();

      expect(vacation).toMatchObject({
        unit: "days",
        tracked: true,
        allowance: 25,
      });
      expect(
        await leave
          .accrue(tenant, {
            typeId: vacation.id,
            period: 2027,
            idempotencyKey: "2027",
          })
          .orThrow(),
      ).toBe(2);
      expect(
        await leave
          .accrue(tenant, {
            typeId: vacation.id,
            period: 2027,
            idempotencyKey: "2027",
          })
          .orThrow(),
      ).toBe(0);

      await s.as(stranger);
      expect(
        await leave
          .request(tenant, { typeId: vacation.id, startsOn: day("2027-03-01") })
          .then(hint),
      ).toBe("LEAVE_FORBIDDEN");

      await s.as(ada);

      // Monday to Sunday counts the five working days.
      const week = await leave
        .request(tenant, {
          typeId: vacation.id,
          startsOn: day("2027-03-01"),
          endsOn: day("2027-03-07"),
          note: "Ski trip",
        })
        .orThrow();

      expect(week).toMatchObject({ amount: 5, status: "pending" });
      expect(
        await leave
          .request(tenant, { typeId: vacation.id, startsOn: day("2027-03-03") })
          .then(hint),
      ).toBe("LEAVE_OVERLAP");
      expect(
        await leave
          .request(tenant, {
            typeId: vacation.id,
            startsOn: day("2027-04-01"),
            endsOn: day("2027-05-31"),
          })
          .then(hint),
      ).toBe("LEAVE_BALANCE_EXCEEDED");

      const half = await leave
        .request(tenant, {
          typeId: vacation.id,
          startsOn: day("2027-03-10"),
          partial: "morning",
        })
        .orThrow();

      expect(half.amount).toBe(0.5);

      const [pending] = await leave
        .balances(tenant, { period: 2027 })
        .orThrow();

      expect(pending).toMatchObject({
        granted: 25,
        taken: 0,
        pending: 5.5,
        available: 19.5,
      });

      await s.as(owner);
      await s.value("better_supabase.decide_approval($1, 'approved')", [
        week.approvalId,
      ]);
      await s.value("better_supabase.decide_approval($1, 'rejected', 'Busy')", [
        half.approvalId,
      ]);

      const requests = await leave.list(tenant, { everyone: true }).orThrow();

      expect(requests.map((request) => [request.id, request.status])).toEqual([
        [week.id, "approved"],
        [half.id, "rejected"],
      ]);

      await s.as(ada);
      expect(
        (await leave.balances(tenant, { period: 2027 }).orThrow())[0],
      ).toMatchObject({ taken: 5, pending: 0, available: 20 });
      expect(await leave.list(tenant, { everyone: true }).then(hint)).toBe(
        "LEAVE_FORBIDDEN",
      );

      expect((await leave.cancel(week.id).orThrow()).status).toBe("cancelled");
      expect(
        (await leave.balances(tenant, { period: 2027 }).orThrow())[0],
      ).toMatchObject({ taken: 0, available: 25 });

      const kinds = await leave.ledger(tenant, { period: 2027 }).orThrow();

      // One transaction gives every entry the same created_at, so compare unordered.
      expect(
        kinds
          .map((entry) => `${entry.kind} ${String(entry.amount)}`)
          .toSorted(),
      ).toEqual(["accrual 25", "taken -5", "taken 5"]);

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'leave_request.%' order by position",
        [tenant],
      );

      expect(events.map((event) => event.type)).toEqual([
        "leave_request.requested",
        "leave_request.requested",
        "leave_request.approved",
        "leave_request.cancelled",
      ]);
    } finally {
      await s.close();
    }
  });

  it("carries a capped balance into the next year and expires the rest once", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, {});
      const tenant = await s.organization(owner, { member: ada });
      const leave = createLeave({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const vacation = await leave
        .saveType(tenant, {
          key: "vacation",
          name: "Vacation",
          carryoverMax: 5,
        })
        .orThrow();

      await leave
        .adjust(tenant, {
          userId: ada.id,
          typeId: vacation.id,
          amount: 12,
          period: 2026,
          kind: "grant",
        })
        .orThrow();
      expect(await leave.closePeriod(tenant, 2026).orThrow()).toBe(3);
      expect(await leave.closePeriod(tenant, 2026).orThrow()).toBe(0);

      const balance = async (period: number) =>
        (await leave.balances(tenant, { userId: ada.id, period }).orThrow())[0];

      expect((await balance(2026))?.available).toBe(0);
      expect((await balance(2027))?.available).toBe(5);
    } finally {
      await s.close();
    }
  });

  it("books an hours type in hours", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install(MODULES, {
        modules: { leave: { options: { allowNegative: true } } },
      });
      const tenant = await s.organization(owner);
      const leave = createLeave({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const appointments = await leave
        .saveType(tenant, { key: "doctor", name: "Doctor", unit: "hours" })
        .orThrow();

      expect(
        await leave
          .request(tenant, {
            typeId: appointments.id,
            startsOn: day("2027-02-02"),
          })
          .then(hint),
      ).toBe("LEAVE_INVALID");

      const visit = await leave
        .request(tenant, {
          typeId: appointments.id,
          startsOn: day("2027-02-02"),
          hours: 2.5,
        })
        .orThrow();

      expect(visit).toMatchObject({ partial: "hours", amount: 2.5 });
    } finally {
      await s.close();
    }
  });
});
