import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createShifts } from "../../src/blocks/shifts/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "leave",
  "time-tracking",
  "shifts",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const today = (): Temporal.PlainDate => Temporal.Now.plainDateISO("UTC");

const at = (date: Temporal.PlainDate, time: string): Temporal.Instant =>
  Temporal.Instant.from(`${date.toString()}T${time}:00Z`);

describe.skipIf(!live)("shifts", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("plans, checks, swaps and books shifts", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const driver = await s.user("driver");
      const colleague = await s.user("colleague");
      const outsider = await s.user("outsider");
      await s.install(MODULES);

      const org = await s.organization(owner, {
        member: driver,
        member2: colleague,
      });

      const shifts = createShifts({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const template = await shifts
        .saveTemplate(org, {
          name: "Early",
          startsTime: "06:00",
          endsTime: "14:00",
          weekdays: [1, 2, 3, 4, 5, 6, 7],
          breakMinutes: 30,
        })
        .orThrow();

      const [first, second] = await shifts
        .generate(
          org,
          template.id,
          today().add({ days: 3 }),
          today().add({ days: 4 }),
        )
        .orThrow();

      expect(first?.startsAt.toString()).toBe(
        at(today().add({ days: 3 }), "06:00").toString(),
      );
      expect(first?.status).toBe("draft");

      const assigned = await shifts
        .assign(first?.id ?? "", driver.id)
        .orThrow();

      expect(assigned).toMatchObject({ status: "assigned", userId: driver.id });
      expect(
        await shifts
          .publish(org, today().add({ days: 3 }), today().add({ days: 4 }))
          .orThrow(),
      ).toBe(2);

      await s.as(colleague);
      expect(
        await shifts
          .upsert(org, {
            startsAt: at(today().add({ days: 5 }), "06:00"),
            endsAt: at(today().add({ days: 5 }), "14:00"),
          })
          .then(hint),
      ).toBe("SHIFT_FORBIDDEN");

      const requested = await shifts
        .requestOpenShift(second?.id ?? "")
        .orThrow();

      expect(requested.status).toBe("requested");

      await s.as(owner);
      expect(
        (await shifts.decideRequest(requested.id, true).orThrow()).status,
      ).toBe("assigned");

      const onLeaveDay = today().add({ days: 6 });

      const leaveShift = await shifts
        .upsert(org, {
          startsAt: at(onLeaveDay, "08:00"),
          endsAt: at(onLeaveDay, "16:00"),
        })
        .orThrow();

      await s.service();
      await s.rows(
        `with t as (
           insert into better_supabase.leave_types (tenant_id, key, name)
           values ($1, 'holiday', 'Holiday') returning id
         )
         insert into better_supabase.leave_requests
           (tenant_id, user_id, type_id, starts_on, ends_on, amount, approved_at)
         select $1, $2, t.id, $3::date, $3::date, 1, now() from t`,
        [org, driver.id, onLeaveDay.toString()],
      );

      await s.as(owner);
      expect(await shifts.assign(leaveShift.id, driver.id).then(hint)).toBe(
        "SHIFT_ASSIGNMENT_ON_LEAVE",
      );

      const yesterday = today().subtract({ days: 1 });

      const worked = await shifts
        .upsert(org, {
          startsAt: at(yesterday, "08:00"),
          endsAt: at(yesterday, "12:00"),
        })
        .orThrow();

      await shifts.assign(worked.id, driver.id).orThrow();

      const hours = await shifts.hours(org, yesterday).orThrow();

      expect(hours.find((row) => row.userId === driver.id)).toMatchObject({
        shifts: 2,
        plannedHours: 11.5,
      });

      await s.as(driver);

      const swap = await shifts
        .requestSwap(assigned.id, colleague.id, "Doctor's appointment")
        .orThrow();

      expect(swap.status).toBe("pending");

      await s.as(owner);
      expect((await shifts.decideSwap(swap.id, true).orThrow()).status).toBe(
        "approved",
      );

      await s.as(colleague);
      expect(await shifts.myShifts().orThrow()).toHaveLength(2);

      await s.service();
      expect(await shifts.toTimeEntries(org).orThrow()).toBe(1);
      expect(await shifts.toTimeEntries(org).orThrow()).toBe(0);

      await s.asRole(outsider);
      expect(
        await shifts.roster(org, today(), today().add({ days: 7 })).orThrow(),
      ).toEqual([]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'shift%'",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "shift.created",
          "shift.published",
          "shift_assignment.created",
          "shift_assignment.released",
          "shift_swap.requested",
          "shift_swap.decided",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
