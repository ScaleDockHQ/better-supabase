import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createCases } from "../../src/blocks/cases/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "pipelines",
  "numbering",
  "relations",
  "tasks",
  "cases",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("cases", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("guards closing on the root cause, the actions and the effectiveness check", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const analyst = await s.user("analyst");
      await s.install(MODULES);
      const org = await s.organization(owner, { member: analyst });

      const cases = createCases({
        transport: sqlTransport(s.sql),
        tenant: org,
      });

      await s.as(owner);

      expect(await cases.kinds().orThrow()).toHaveLength(8);

      const spillKind = await cases
        .saveKind({
          key: "spill",
          name: "Spill",
          prefix: "SPL",
          effectivenessAfterDays: 30,
          requiresEffectiveness: true,
        })
        .orThrow();

      expect(spillKind).toMatchObject({
        prefix: "SPL",
        requiresRootCause: true,
        requiresActions: true,
        requiresEffectiveness: true,
      });
      expect(
        await cases
          .saveKind({ key: "Spill!", name: "Bad", prefix: "SP" })
          .then(hint),
      ).toBe("CASE_KIND_INVALID");
      expect(
        await cases
          .open({ kind: "spill", title: "Odd", severity: "huge" })
          .then(hint),
      ).toBe("CASE_SEVERITY_UNKNOWN");

      const spill = await cases
        .open({ kind: "spill", title: "Solvent on bay 3", ownerId: owner.id })
        .orThrow();

      expect(spill).toMatchObject({ status: "open", source: "internal" });
      expect(spill.number).toMatch(/^SPL-/);
      expect(await cases.blockers(spill.id).orThrow()).toEqual([
        "CASE_ROOT_CAUSE_REQUIRED",
        "CASE_ACTIONS_REQUIRED",
        "CASE_EFFECTIVENESS_REQUIRED",
      ]);
      expect(await cases.close({ caseId: spill.id }).then(hint)).toBe(
        "CASE_ROOT_CAUSE_REQUIRED",
      );

      await cases
        .recordRootCause({ caseId: spill.id, rootCause: "Loose drum bung" })
        .orThrow();

      const action = await cases
        .createAction({
          caseId: spill.id,
          input: { type: "corrective", title: "Fit bung locks" },
        })
        .orThrow();

      expect(await cases.blockers(spill.id).orThrow()).toEqual([
        "CASE_ACTIONS_OPEN",
        "CASE_EFFECTIVENESS_REQUIRED",
      ]);

      await s.as(analyst);

      const page = await cases.list().orThrow();

      expect(page.items.map((row) => row.id)).toEqual([spill.id]);
      expect(await cases.close({ caseId: spill.id }).then(hint)).toBe(
        "CASE_FORBIDDEN",
      );
      expect(
        await cases
          .createAction({
            caseId: spill.id,
            input: { type: "containment", title: "Sneaky" },
          })
          .then(hint),
      ).toBe("CASE_FORBIDDEN");

      const door = await cases
        .open({ kind: "observation", title: "Fire door propped open" })
        .orThrow();

      expect(door.reporterId).toBe(analyst.id);
      expect(await cases.close({ caseId: door.id }).then(hint)).toBe(
        "CASE_FORBIDDEN",
      );

      await s.service();
      await s.rows(
        "update better_supabase.tasks set state = 'completed' where id = $1",
        [action.taskId],
      );
      expect(await cases.notifyDueEffectiveness().orThrow()).toBe(0);

      const scheduled = await cases.get(spill.id).orThrow();

      expect(scheduled.effectivenessDueOn?.toString()).toBe(
        Temporal.Now.plainDateISO("UTC").add({ days: 30 }).toString(),
      );
      expect(scheduled.actions).toEqual([
        expect.objectContaining({ taskId: action.taskId, done: true }),
      ]);

      await s.rows(
        "update better_supabase.cases set effectiveness_due_on = current_date - 1 where id = $1",
        [spill.id],
      );
      expect(await cases.notifyDueEffectiveness().orThrow()).toBe(1);
      expect(await cases.notifyDueEffectiveness().orThrow()).toBe(0);

      const notices = await s.rows<{ user_id: string }>(
        `select r.user_id::text as user_id from better_supabase.notification_recipients r
         join better_supabase.notification_events e on e.id = r.event_id
         where e.type = 'case.effectiveness_date_reached'`,
      );

      expect(notices.map((row) => row.user_id)).toEqual([owner.id]);

      await s.as(owner);
      await cases
        .recordEffectiveness({
          caseId: spill.id,
          effective: true,
          note: "No spills since",
        })
        .orThrow();

      const closed = await cases
        .close({ caseId: spill.id, note: "Locks fitted" })
        .orThrow();

      expect(closed).toMatchObject({
        status: "closed",
        closeNote: "Locks fitted",
      });
      expect(
        await cases
          .recordRootCause({ caseId: spill.id, rootCause: "Other" })
          .then(hint),
      ).toBe("CASE_CLOSED");
      expect(
        (
          await cases
            .reopen({ caseId: spill.id, reason: "Came back" })
            .orThrow()
        ).status,
      ).toBe("open");
      expect(
        (await cases.cancel({ caseId: door.id, reason: "Duplicate" }).orThrow())
          .status,
      ).toBe("canceled");
      expect(await cases.stats({ groupBy: "kind" }).orThrow()).toEqual(
        expect.arrayContaining([
          { key: "spill", count: 1 },
          { key: "observation", count: 1 },
        ]),
      );

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'case%'",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "case_kind.created",
          "case.created",
          "case.root_cause_recorded",
          "case_action.created",
          "case.effectiveness_date_reached",
          "case.effectiveness_recorded",
          "case.closed",
          "case.reopened",
          "case.cancelled",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
