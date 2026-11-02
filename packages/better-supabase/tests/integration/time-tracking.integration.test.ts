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
import { money } from "../../src/commerce/money.ts";
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

      const time = createTimeTracking({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.as(stranger);
      expect(await time.start().then(hint)).toBe("TIME_FORBIDDEN");

      await s.as(ada);
      expect(await time.running().orThrow()).toBeUndefined();
      const first = await time.start({ note: "Inbox" }).orThrow();
      expect(first.endedAt).toBeUndefined();

      const second = await time
        .start({
          subject: { type: "project", id: "apollo" },
          billable: true,
          rate: money(8000n, "EUR"),
        })
        .orThrow();

      const running = await time.running().orThrow();
      expect(running?.id).toBe(second.id);
      const stopped = await time.stop().orThrow();
      expect(stopped.seconds).toBeGreaterThanOrEqual(0);
      expect(stopped).toMatchObject({
        billable: true,
        rate: money(8000n, "EUR"),
      });
      expect(await time.stop().then(hint)).toBe("TIME_NO_TIMER");
      expect(
        await time
          .start({ subject: { type: "project", id: undefined as never } })
          .then(hint),
      ).toBe("TIME_SUBJECT_INVALID");

      const logged = await time
        .log({
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T11:00:00Z"),
          subject: { type: "project", id: "apollo" },
          billable: true,
          rate: money(10_000n, "EUR"),
        })
        .orThrow();

      expect(logged.seconds).toBe(7200);
      expect(
        await time
          .log({
            startedAt: at("2026-10-06T10:00:00Z"),
            endedAt: at("2026-10-06T12:00:00Z"),
          })
          .then(hint),
      ).toBe("TIME_ENTRY_OVERLAP");
      expect(
        await time
          .log({
            startedAt: at("2026-10-06T12:00:00Z"),
            endedAt: at("2026-10-06T12:00:00Z"),
          })
          .then(hint),
      ).toBe("TIME_ENTRY_INVALID");
      expect(
        await time
          .log({
            startedAt: at("2026-10-07T09:00:00Z"),
            endedAt: at("2026-10-07T10:00:00Z"),
            userId: owner.id,
          })
          .then(hint),
      ).toBe("TIME_FORBIDDEN");

      const internal = await time
        .log({
          startedAt: at("2026-10-07T23:00:00Z"),
          endedAt: at("2026-10-08T01:00:00Z"),
          note: "Release",
        })
        .orThrow();

      const edited = await time
        .update({
          entryId: internal.id,
          patch: { note: null, billable: true, rate: money(5000n, "EUR") },
        })
        .orThrow();

      expect(edited).toMatchObject({
        billable: true,
        rate: money(5000n, "EUR"),
      });
      expect(edited.note).toBeUndefined();
      expect(
        await time
          .update({
            entryId: internal.id,
            patch: { startedAt: at("2026-10-06T10:00:00Z") },
          })
          .then(hint),
      ).toBe("TIME_ENTRY_OVERLAP");

      const sheet = await time
        .timesheet({ week: WEEK.add({ days: 2 }) })
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
        amounts: [money(30_000n, "EUR")],
      });

      const grid = toWeeklyGrid(sheet.entries, {
        week: sheet.week,
        timeZone: "UTC",
      });

      expect(grid.days.map((day) => day.seconds)).toEqual([
        0, 7200, 3600, 3600, 0, 0, 0,
      ]);

      const submitted = await time
        .submit({ week: WEEK, note: "Week 41" })
        .orThrow();

      expect(submitted).toMatchObject({ status: "submitted", note: "Week 41" });
      expect(await time.submit({ week: WEEK }).then(hint)).toBe(
        "TIMESHEET_SUBMITTED",
      );
      expect(await time.remove(logged.id).then(hint)).toBe(
        "TIME_PERIOD_LOCKED",
      );
      expect(
        await time
          .log({
            startedAt: at("2026-10-09T09:00:00Z"),
            endedAt: at("2026-10-09T10:00:00Z"),
          })
          .then(hint),
      ).toBe("TIME_PERIOD_LOCKED");
      expect(await time.list({ everyone: true }).then(hint)).toBe(
        "TIME_FORBIDDEN",
      );

      await s.as(owner);
      await s.value(
        "better_supabase.decide_approval($1, 'rejected', 'Missing Friday')",
        [submitted.approvalId],
      );
      await s.as(ada);
      expect((await time.timesheet({ week: WEEK }).orThrow()).status).toBe(
        "rejected",
      );
      await time
        .log({
          startedAt: at("2026-10-09T09:00:00Z"),
          endedAt: at("2026-10-09T10:00:00Z"),
        })
        .orThrow();
      const again = await time.submit({ week: WEEK }).orThrow();

      await s.as(owner);
      await s.value("better_supabase.decide_approval($1, 'approved')", [
        again.approvalId,
      ]);

      const everyone = await time
        .list({ everyone: true, subject: { type: "project", id: "apollo" } })
        .orThrow();

      expect(everyone.map((entry) => entry.id)).toEqual([second.id, logged.id]);

      const approved = await time.timesheets({ userId: ada.id }).orThrow();

      expect(approved.map((row) => row.status)).toEqual(["approved"]);
      expect(approved[0]?.approvedAt).toBeDefined();

      await s.as(ada);
      expect(
        await time
          .update({
            entryId: logged.id,
            patch: { startedAt: at("2026-10-06T07:00:00Z") },
          })
          .then(hint),
      ).toBe("TIME_PERIOD_LOCKED");
      expect(
        await time
          .update({
            entryId: logged.id,
            patch: { note: "late", billable: false },
          })
          .orThrow(),
      ).toMatchObject({ note: "late", billable: false });
      expect(await time.submit({ week: WEEK }).then(hint)).toBe(
        "TIMESHEET_APPROVED",
      );
      expect(await time.reopen(again.id!).then(hint)).toBe("TIME_FORBIDDEN");
      expect(await time.timesheets({ userId: owner.id }).then(hint)).toBe(
        "TIME_FORBIDDEN",
      );

      await s.as(owner);
      const reopened = await time.reopen(again.id!).orThrow();
      expect(reopened.status).toBe("open");
      expect(await time.reopen(again.id!).then(hint)).toBe(
        "TIMESHEET_NOT_APPROVED",
      );
      await s.as(ada);
      await time.remove(logged.id).orThrow();

      await time.start().orThrow();
      const today = Temporal.Now.plainDateISO("UTC");
      expect(await time.submit({ week: today }).then(hint)).toBe(
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

      const time = createTimeTracking({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.as(ada);

      const entry = await time
        .log({
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T10:00:00Z"),
        })
        .orThrow();

      await time
        .update({ entryId: entry.id, patch: { billable: true } })
        .orThrow();
      const sheet = await time.submit({ week: WEEK }).orThrow();
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

      const time = createTimeTracking({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.as(ada);
      await time
        .log({
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T10:30:00Z"),
          billable: true,
        })
        .orThrow();

      const moved = await time
        .log({
          startedAt: at("2026-10-07T09:00:00Z"),
          endedAt: at("2026-10-07T09:30:00Z"),
        })
        .orThrow();

      await time.start().orThrow();

      await s.service();

      const metrics = createMetrics({
        transport: sqlTransport(s.sql),
        metrics: timeTrackingMetrics(),
      });

      let relayed = 0;

      const relay = async () => {
        await s.service();

        const events = await s.rows<{
          type: string;
          payload: unknown;
          created_at: Date;
        }>(
          "select type, payload, created_at from better_supabase.outbox_events where organization_id = $1 and type like 'time_entry.%' order by position offset $2",
          [tenant, relayed],
        );

        relayed += events.length;
        await metricsSink(metrics, {
          on: TIME_TRACKING_METRIC_EVENTS,
          time: timeEntryMetricTime,
        }).send(
          events.map((row, n) => ({
            specversion: "1.0",
            id: `e${relayed}-${n}`,
            source: "/test",
            type: `dev.better-supabase.${row.type}`,
            time: row.created_at.toISOString(),
            data: row.payload,
          })),
        );
      };

      await relay();

      await s.as(owner);

      const week = {
        from: at("2026-10-05T00:00:00Z"),
        until: at("2026-10-12T00:00:00Z"),
      };

      const series = await metrics
        .series({
          metric: "time_tracked",
          range: week,
          options: { organizationId: tenant, grain: "day" },
        })
        .orThrow();

      expect(series.points.slice(1, 3).map((p) => p.value)).toEqual([
        5400, 1800,
      ]);
      expect(
        await metrics
          .kpi({
            metric: "time_tracked",
            range: week,
            options: { organizationId: tenant, filter: { billable: true } },
          })
          .orThrow(),
      ).toMatchObject({ value: 5400, count: 1 });

      await s.as(ada);
      await time
        .update({
          entryId: moved.id,
          patch: {
            startedAt: at("2026-10-09T09:00:00Z"),
            endedAt: at("2026-10-09T09:30:00Z"),
          },
        })
        .orThrow();
      await relay();
      await s.as(owner);

      const after = await metrics
        .series({
          metric: "time_tracked",
          range: week,
          options: { organizationId: tenant, grain: "day" },
        })
        .orThrow();

      expect(after.points.slice(1, 5).map((p) => p.value)).toEqual([
        5400, 0, 0, 1800,
      ]);
    } finally {
      await s.close();
    }
  });

  it("decides timesheets without approvals and starts weeks in each member's time zone", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(`create schema tt_status_it;
create table tt_status_it.zones (id uuid primary key, timezone text);`);
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      const grace = await s.user("grace");
      await s.install(["organizations", "outbox", "time-tracking"], {
        modules: {
          "time-tracking": {
            schema: "tt_status_it",
            options: {
              approvals: false,
              userTimeZone: { column: "tt_status_it.zones.timezone" },
            },
          },
        },
      });
      const tenant = await s.organization(owner, { member: ada, admin: grace });
      await s.service();
      await s.client.query(
        "insert into tt_status_it.zones (id, timezone) values ($1, 'Pacific/Auckland')",
        [ada.id],
      );

      await s.as(ada);
      await s.value(
        "tt_status_it.log_time($1, '2026-03-01T11:30:00Z', '2026-03-01T12:30:00Z')",
        [tenant],
      );
      expect(
        await s.value<string>(
          "to_char(tt_status_it.time_week('2026-03-01T11:30:00Z', $1::uuid), 'YYYY-MM-DD')",
          [ada.id],
        ),
      ).toBe("2026-03-02");

      const submitted = await s.value<{ id: string; status: string }>(
        "tt_status_it.submit_timesheet($1, '2026-03-02')",
        [tenant],
      );

      expect(submitted.status).toBe("submitted");
      expect(
        await s.hint(
          "select tt_status_it.log_time($1, '2026-03-03T09:00:00Z', '2026-03-03T10:00:00Z')",
          [tenant],
        ),
      ).toBe("TIME_PERIOD_LOCKED");
      expect(
        await s.hint("select tt_status_it.approve_timesheet($1)", [
          submitted.id,
        ]),
      ).toBe("TIME_FORBIDDEN");

      await s.as(grace);

      const rejected = await s.value<{ status: string; decisionNote: string }>(
        "tt_status_it.reject_timesheet($1, 'missing Friday')",
        [submitted.id],
      );

      expect(rejected).toMatchObject({
        status: "rejected",
        decisionNote: "missing Friday",
      });

      await s.as(ada);
      await s.value(
        "tt_status_it.log_time($1, '2026-03-06T09:00:00Z', '2026-03-06T10:00:00Z')",
        [tenant],
      );
      await s.value("tt_status_it.submit_timesheet($1, '2026-03-02')", [
        tenant,
      ]);

      await s.as(grace);

      const approved = await s.value<{
        status: string;
        approvedAt: string | null;
      }>("tt_status_it.approve_timesheet($1)", [submitted.id]);

      expect(approved.status).toBe("approved");
      expect(approved.approvedAt).not.toBeNull();
    } finally {
      await s.close();
    }
  });

  it("keeps time and timesheets per employee, also without an account", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      const grace = await s.user("grace");
      await s.install(
        ["organizations", "outbox", "employees", "time-tracking"],
        {
          modules: {
            employees: { schema: "tt_employee_it" },
            "time-tracking": {
              schema: "tt_employee_it",
              columns: { timesheets: { user: null } },
              options: { approvals: false, owner: "employee" },
            },
          },
        },
      );
      const tenant = await s.organization(owner, { member: ada, admin: grace });
      await s.service();
      const adaEmployee = await s.value<string>("gen_random_uuid()");
      const crew = await s.value<string>("gen_random_uuid()");
      await s.client.query(
        "insert into tt_employee_it.employees (id, tenant_id, user_id, name) values ($1, $2, $3, 'Ada'), ($4, $2, null, 'Crew')",
        [adaEmployee, tenant, ada.id, crew],
      );

      await s.as(ada);

      const started = await s.value<{ employeeId: string }>(
        "tt_employee_it.start_timer($1)",
        [tenant],
      );

      expect(started.employeeId).toBe(adaEmployee);
      await s.value("tt_employee_it.stop_timer($1)", [tenant]);
      expect(
        await s.hint(
          "select tt_employee_it.log_time($1, '2026-03-02T09:00:00Z', '2026-03-02T10:00:00Z', employee_id => $2)",
          [tenant, crew],
        ),
      ).toBe("TIME_FORBIDDEN");

      await s.as(grace);

      const logged = await s.value<{
        employeeId: string;
        userId: string | null;
      }>(
        "tt_employee_it.log_time($1, '2026-03-02T09:00:00Z', '2026-03-02T10:00:00Z', employee_id => $2)",
        [tenant, crew],
      );

      expect(logged).toMatchObject({ employeeId: crew, userId: null });

      const submitted = await s.value<{
        id: string;
        status: string;
        employeeId: string;
      }>("tt_employee_it.submit_timesheet($1, '2026-03-02', null, $2)", [
        tenant,
        crew,
      ]);

      expect(submitted).toMatchObject({
        status: "submitted",
        employeeId: crew,
      });
      expect(
        await s.hint(
          "select tt_employee_it.log_time($1, '2026-03-03T09:00:00Z', '2026-03-03T10:00:00Z', employee_id => $2)",
          [tenant, crew],
        ),
      ).toBe("TIME_PERIOD_LOCKED");

      const approved = await s.value<{ status: string }>(
        "tt_employee_it.approve_timesheet($1)",
        [submitted.id],
      );

      expect(approved.status).toBe("approved");

      await s.as(ada);
      expect(
        await s.hint(
          "select tt_employee_it.get_timesheet($1, '2026-03-02', employee_id => $2)",
          [tenant, crew],
        ),
      ).toBe("TIME_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
