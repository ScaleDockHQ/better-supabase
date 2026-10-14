import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createMetrics, metricsSink } from "../../src/blocks/metrics/index.ts";
import {
  createTimeTracking,
  sqlTransport,
  TIME_TRACKING_METRIC_EVENTS,
  timeEntryMetricTime,
  timeTrackingMetrics,
  toWeeklyGrid,
} from "../../src/blocks/time-tracking/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "outbox", "approvals", "time-tracking"];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);
const WEEK = Temporal.PlainDate.from("2026-10-05");

describe.skipIf(!live)("time-tracking", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("tracks time, locks a submitted week and unlocks it on rejection or reopen", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      const stranger = await s.user("stranger");
      await s.install(MODULES, {});
      const tenant = await s.organization(owner, { member: ada });
      const time = createTimeTracking({ transport: sqlTransport(s.sql) });

      await s.as(stranger);
      expect(await time.start(tenant).then(hint)).toBe("TIME_FORBIDDEN");

      await s.as(ada);
      expect(await time.running(tenant).orThrow()).toBeUndefined();
      const first = await time.start(tenant, { note: "Inbox" }).orThrow();
      expect(first.endedAt).toBeUndefined();
      const second = await time
        .start(tenant, {
          subjectType: "project",
          subjectId: "apollo",
          billable: true,
          rate: 80,
        })
        .orThrow();
      const running = await time.running(tenant).orThrow();
      expect(running?.id).toBe(second.id);
      const stopped = await time.stop(tenant).orThrow();
      expect(stopped.seconds).toBeGreaterThanOrEqual(0);
      expect(stopped).toMatchObject({ billable: true, rate: 80 });
      expect(await time.stop(tenant).then(hint)).toBe("TIME_NO_TIMER");
      expect(
        await time.start(tenant, { subjectType: "project" }).then(hint),
      ).toBe("TIME_SUBJECT_INVALID");

      const logged = await time
        .log(tenant, {
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T11:00:00Z"),
          subjectType: "project",
          subjectId: "apollo",
          billable: true,
          rate: 100,
        })
        .orThrow();
      expect(logged.seconds).toBe(7200);
      expect(
        await time
          .log(tenant, {
            startedAt: at("2026-10-06T10:00:00Z"),
            endedAt: at("2026-10-06T12:00:00Z"),
          })
          .then(hint),
      ).toBe("TIME_ENTRY_OVERLAP");
      expect(
        await time
          .log(tenant, {
            startedAt: at("2026-10-06T12:00:00Z"),
            endedAt: at("2026-10-06T12:00:00Z"),
          })
          .then(hint),
      ).toBe("TIME_ENTRY_INVALID");
      expect(
        await time
          .log(tenant, {
            startedAt: at("2026-10-07T09:00:00Z"),
            endedAt: at("2026-10-07T10:00:00Z"),
            userId: owner.id,
          })
          .then(hint),
      ).toBe("TIME_FORBIDDEN");
      const internal = await time
        .log(tenant, {
          startedAt: at("2026-10-07T23:00:00Z"),
          endedAt: at("2026-10-08T01:00:00Z"),
          note: "Release",
        })
        .orThrow();
      const edited = await time
        .update(internal.id, { note: null, billable: true, rate: 50 })
        .orThrow();
      expect(edited).toMatchObject({ billable: true, rate: 50 });
      expect(edited.note).toBeUndefined();
      expect(
        await time
          .update(internal.id, { startedAt: at("2026-10-06T10:00:00Z") })
          .then(hint),
      ).toBe("TIME_ENTRY_OVERLAP");

      const sheet = await time
        .timesheet(tenant, WEEK.add({ days: 2 }))
        .orThrow();
      expect(sheet).toMatchObject({ status: "open", userId: ada.id });
      expect(sheet.week.toString()).toBe("2026-10-05");
      expect(sheet.entries.map((entry) => entry.id)).toEqual([
        logged.id,
        internal.id,
      ]);
      expect(sheet.totals).toEqual({
        seconds: 14_400,
        billableSeconds: 14_400,
        amount: 300,
      });
      const grid = toWeeklyGrid(sheet.entries, {
        week: sheet.week,
        timeZone: "UTC",
      });
      expect(grid.days.map((day) => day.seconds)).toEqual([
        0, 7200, 3600, 3600, 0, 0, 0,
      ]);

      const submitted = await time.submit(tenant, WEEK, "Week 41").orThrow();
      expect(submitted).toMatchObject({ status: "submitted", note: "Week 41" });
      expect(await time.submit(tenant, WEEK).then(hint)).toBe(
        "TIMESHEET_SUBMITTED",
      );
      expect(await time.remove(logged.id).then(hint)).toBe(
        "TIME_PERIOD_LOCKED",
      );
      expect(
        await time
          .log(tenant, {
            startedAt: at("2026-10-09T09:00:00Z"),
            endedAt: at("2026-10-09T10:00:00Z"),
          })
          .then(hint),
      ).toBe("TIME_PERIOD_LOCKED");
      expect(await time.list(tenant, { everyone: true }).then(hint)).toBe(
        "TIME_FORBIDDEN",
      );

      await s.as(owner);
      await s.value(
        "better_supabase.decide_approval($1, 'rejected', 'Missing Friday')",
        [submitted.approvalId],
      );
      await s.as(ada);
      expect((await time.timesheet(tenant, WEEK).orThrow()).status).toBe(
        "rejected",
      );
      await time
        .log(tenant, {
          startedAt: at("2026-10-09T09:00:00Z"),
          endedAt: at("2026-10-09T10:00:00Z"),
        })
        .orThrow();
      const again = await time.submit(tenant, WEEK).orThrow();

      await s.as(owner);
      await s.value("better_supabase.decide_approval($1, 'approved')", [
        again.approvalId,
      ]);
      const everyone = await time
        .list(tenant, { everyone: true, subjectId: "apollo" })
        .orThrow();
      expect(everyone.map((entry) => entry.id)).toEqual([second.id, logged.id]);
      const approved = await time
        .timesheets(tenant, { userId: ada.id })
        .orThrow();
      expect(approved.map((row) => row.status)).toEqual(["approved"]);
      expect(approved[0]?.approvedAt).toBeDefined();

      await s.as(ada);
      expect(await time.update(logged.id, { note: "late" }).then(hint)).toBe(
        "TIME_PERIOD_LOCKED",
      );
      expect(await time.submit(tenant, WEEK).then(hint)).toBe(
        "TIMESHEET_APPROVED",
      );
      expect(await time.reopen(again.id!).then(hint)).toBe("TIME_FORBIDDEN");
      expect(
        await time.timesheets(tenant, { userId: owner.id }).then(hint),
      ).toBe("TIME_FORBIDDEN");

      await s.as(owner);
      const reopened = await time.reopen(again.id!).orThrow();
      expect(reopened.status).toBe("open");
      expect(await time.reopen(again.id!).then(hint)).toBe(
        "TIMESHEET_NOT_APPROVED",
      );
      await s.as(ada);
      await time.remove(logged.id).orThrow();

      await time.start(tenant).orThrow();
      const today = Temporal.Now.plainDateISO("UTC");
      expect(await time.submit(tenant, today).then(hint)).toBe(
        "TIMESHEET_TIMER_RUNNING",
      );

      await s.service();
      await expect(
        s.client.query(
          `insert into better_supabase.time_entries (tenant_id, user_id, started_at, ended_at)
           values ($1, $2, '2026-09-01T09:00:00Z', '2026-09-01T11:00:00Z'),
                  ($1, $2, '2026-09-01T10:00:00Z', '2026-09-01T12:00:00Z')`,
          [tenant, ada.id],
        ),
      ).rejects.toMatchObject({ code: "23P01" });
    } finally {
      await s.close();
    }
  });

  it("records time and timesheet events", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, {});
      const tenant = await s.organization(owner, { member: ada });
      const time = createTimeTracking({ transport: sqlTransport(s.sql) });
      await s.as(ada);
      const entry = await time
        .log(tenant, {
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T10:00:00Z"),
        })
        .orThrow();
      await time.update(entry.id, { billable: true }).orThrow();
      const sheet = await time.submit(tenant, WEEK).orThrow();
      await s.as(owner);
      await s.value("better_supabase.decide_approval($1, 'approved')", [
        sheet.approvalId,
      ]);
      await time.reopen(sheet.id!).orThrow();
      await s.as(ada);
      await time.remove(entry.id).orThrow();
      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and (type like 'time_entry.%' or type like 'timesheet.%') order by position",
        [tenant],
      );
      expect(events.map((row) => row.type)).toEqual([
        "time_entry.recorded",
        "time_entry.updated",
        "timesheet.submitted",
        "timesheet.approved",
        "timesheet.reopened",
        "time_entry.deleted",
      ]);
    } finally {
      await s.close();
    }
  });

  it("rolls tracked seconds up by the day each entry started", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install([...MODULES, "metrics"], {
        modules: { metrics: { options: { metrics: timeTrackingMetrics() } } },
      });
      const tenant = await s.organization(owner, { member: ada });
      const time = createTimeTracking({ transport: sqlTransport(s.sql) });
      await s.as(ada);
      await time
        .log(tenant, {
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T10:30:00Z"),
          billable: true,
        })
        .orThrow();
      await time
        .log(tenant, {
          startedAt: at("2026-10-07T09:00:00Z"),
          endedAt: at("2026-10-07T09:30:00Z"),
        })
        .orThrow();
      await time.start(tenant).orThrow();

      await s.service();
      const metrics = createMetrics({
        transport: sqlTransport(s.sql),
        metrics: timeTrackingMetrics(),
      });
      const events = await s.rows<{
        type: string;
        payload: unknown;
        created_at: Date;
      }>(
        "select type, payload, created_at from better_supabase.outbox_events where organization_id = $1 and type like 'time_entry.%' order by position",
        [tenant],
      );
      await metricsSink(metrics, {
        on: TIME_TRACKING_METRIC_EVENTS,
        time: timeEntryMetricTime,
      }).send(
        events.map((row, n) => ({
          specversion: "1.0",
          id: `e${n}`,
          source: "/test",
          type: `dev.better-supabase.${row.type}`,
          time: row.created_at.toISOString(),
          data: row.payload,
        })),
      );

      await s.as(owner);
      const week = {
        from: at("2026-10-05T00:00:00Z"),
        until: at("2026-10-12T00:00:00Z"),
      };
      const series = await metrics
        .series("time_tracked", week, { organizationId: tenant, grain: "day" })
        .orThrow();
      expect(series.points.slice(1, 3).map((p) => p.value)).toEqual([
        5400, 1800,
      ]);
      expect(
        await metrics
          .kpi("time_tracked", week, {
            organizationId: tenant,
            filter: { billable: true },
          })
          .orThrow(),
      ).toMatchObject({ value: 5400, count: 1 });
    } finally {
      await s.close();
    }
  });
});
