import { describe, expect, it } from "vitest";

import { createTimeTracking } from "../../../src/blocks/time-tracking/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];
  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("better_supabase");
      calls.push([fn, args]);
      const result = results[fn];
      if (!result) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(result(args));
    },
  };
}

const AT = "2026-10-06T09:00:00Z";
const ENTRY = {
  id: "e1",
  organizationId: "o",
  userId: "u1",
  subjectType: "project",
  subjectId: "apollo",
  startedAt: AT,
  endedAt: "2026-10-06T11:00:00Z",
  seconds: 7200,
  billable: true,
  rate: 100,
  note: "Design",
  createdAt: AT,
  updatedAt: AT,
};
const RUNNING = {
  ...ENTRY,
  id: "e2",
  subjectType: null,
  subjectId: null,
  endedAt: null,
  seconds: null,
  billable: false,
  rate: null,
  note: null,
};
const SHEET = {
  id: "t1",
  organizationId: "o",
  userId: "u1",
  week: "2026-10-05",
  status: "submitted",
  approvalId: "a1",
  note: "Week 41",
  submittedAt: AT,
  approvedAt: null,
  createdAt: AT,
};
const WEEK = Temporal.PlainDate.from("2026-10-05");

describe("time-tracking client", () => {
  it("starts, stops and reads timers", async () => {
    const fake = transport({
      start_timer: () => RUNNING,
      stop_timer: () => ENTRY,
      running_timer: () => null,
    });
    const time = createTimeTracking({ transport: fake });
    const started = await time.start("o").orThrow();
    expect(started).toMatchObject({ id: "e2", billable: false });
    expect(started.endedAt).toBeUndefined();
    expect(started.seconds).toBeUndefined();
    expect(started.subjectType).toBeUndefined();
    await time
      .start("o", {
        subjectType: "project",
        subjectId: "apollo",
        billable: true,
        rate: 80,
        note: "x",
      })
      .orThrow();
    const stopped = await time.stop("o").orThrow();
    expect(stopped).toMatchObject({ seconds: 7200, rate: 100, note: "Design" });
    expect(stopped.endedAt?.toString()).toBe("2026-10-06T11:00:00Z");
    expect(await time.running("o").orThrow()).toBeUndefined();
    expect(fake.calls).toEqual([
      [
        "start_timer",
        {
          tenant: "o",
          subject_type: null,
          subject_id: null,
          billable: false,
          rate: null,
          note: null,
        },
      ],
      [
        "start_timer",
        {
          tenant: "o",
          subject_type: "project",
          subject_id: "apollo",
          billable: true,
          rate: 80,
          note: "x",
        },
      ],
      ["stop_timer", { tenant: "o" }],
      ["running_timer", { tenant: "o" }],
    ]);
  });

  it("logs, updates, removes and lists entries", async () => {
    const fake = transport({
      running_timer: () => RUNNING,
      log_time: () => ENTRY,
      update_time_entry: () => ENTRY,
      delete_time_entry: () => ENTRY,
      list_time_entries: () => [ENTRY, RUNNING],
    });
    const time = createTimeTracking({ transport: fake });
    expect((await time.running("o").orThrow())?.id).toBe("e2");
    const start = Temporal.Instant.from(AT);
    const end = Temporal.Instant.from("2026-10-06T11:00:00Z");
    await time.log("o", { startedAt: start, endedAt: end }).orThrow();
    await time
      .log("o", {
        startedAt: start,
        endedAt: end,
        subjectType: "project",
        subjectId: "apollo",
        billable: true,
        rate: 100,
        note: "Design",
        userId: "u2",
      })
      .orThrow();
    await time
      .update("e1", {
        startedAt: start,
        endedAt: end,
        subject: { subjectType: "project", subjectId: "zeus" },
        billable: false,
        rate: null,
        note: null,
      })
      .orThrow();
    await time.update("e1", { subject: null }).orThrow();
    await time.update("e1", {}).orThrow();
    await time.remove("e1").orThrow();
    const listed = await time.list("o").orThrow();
    expect(listed.map((entry) => entry.id)).toEqual(["e1", "e2"]);
    await time
      .list("o", {
        userId: "u2",
        everyone: true,
        from: start,
        to: end,
        subjectType: "project",
        subjectId: "apollo",
        pageSize: 10,
      })
      .orThrow();
    expect(fake.calls.slice(1)).toEqual([
      [
        "log_time",
        {
          tenant: "o",
          started_at: AT,
          ended_at: "2026-10-06T11:00:00Z",
          subject_type: null,
          subject_id: null,
          billable: false,
          rate: null,
          note: null,
          user_id: null,
        },
      ],
      [
        "log_time",
        {
          tenant: "o",
          started_at: AT,
          ended_at: "2026-10-06T11:00:00Z",
          subject_type: "project",
          subject_id: "apollo",
          billable: true,
          rate: 100,
          note: "Design",
          user_id: "u2",
        },
      ],
      [
        "update_time_entry",
        {
          entry_id: "e1",
          patch: {
            startedAt: AT,
            endedAt: "2026-10-06T11:00:00Z",
            subjectType: "project",
            subjectId: "zeus",
            billable: false,
            rate: null,
            note: null,
          },
        },
      ],
      [
        "update_time_entry",
        { entry_id: "e1", patch: { subjectType: null, subjectId: null } },
      ],
      ["update_time_entry", { entry_id: "e1", patch: {} }],
      ["delete_time_entry", { entry_id: "e1" }],
      [
        "list_time_entries",
        {
          tenant: "o",
          user_id: null,
          starts: null,
          ends: null,
          subject_type: null,
          subject_id: null,
          everyone: false,
          page_size: null,
        },
      ],
      [
        "list_time_entries",
        {
          tenant: "o",
          user_id: "u2",
          starts: AT,
          ends: "2026-10-06T11:00:00Z",
          subject_type: "project",
          subject_id: "apollo",
          everyone: true,
          page_size: 10,
        },
      ],
    ]);
  });

  it("reads, submits, reopens and lists timesheets", async () => {
    const fake = transport({
      get_timesheet: () => ({
        ...SHEET,
        entries: [ENTRY],
        totals: { seconds: 7200, billableSeconds: 7200, amount: 200 },
      }),
      submit_timesheet: () => SHEET,
      reopen_timesheet: () => ({
        ...SHEET,
        status: "open",
        approvalId: null,
        submittedAt: null,
      }),
      list_timesheets: () => [{ ...SHEET, status: "approved", approvedAt: AT }],
    });
    const time = createTimeTracking({ transport: fake });
    const sheet = await time.timesheet("o", WEEK).orThrow();
    expect(sheet.week.toString()).toBe("2026-10-05");
    expect(sheet.status).toBe("submitted");
    expect(sheet.entries.map((entry) => entry.id)).toEqual(["e1"]);
    expect(sheet.totals).toEqual({
      seconds: 7200,
      billableSeconds: 7200,
      amount: 200,
    });
    await time.timesheet("o", WEEK, "u2").orThrow();
    expect(await time.submit("o", WEEK).orThrow()).toMatchObject({
      id: "t1",
      approvalId: "a1",
    });
    await time.submit("o", WEEK, "Week 41").orThrow();
    const reopened = await time.reopen("t1").orThrow();
    expect(reopened.status).toBe("open");
    expect(reopened.approvalId).toBeUndefined();
    const [approved] = await time.timesheets("o").orThrow();
    expect(approved?.approvedAt?.toString()).toBe(AT);
    await time
      .timesheets("o", {
        userId: "u2",
        status: "approved",
        pageSize: 5,
        before: WEEK,
      })
      .orThrow();
    expect(fake.calls.map(([, args]) => args)).toEqual([
      { tenant: "o", week: "2026-10-05", user_id: null },
      { tenant: "o", week: "2026-10-05", user_id: "u2" },
      { tenant: "o", week: "2026-10-05", note: null },
      { tenant: "o", week: "2026-10-05", note: "Week 41" },
      { timesheet_id: "t1" },
      {
        tenant: "o",
        user_id: null,
        status: null,
        page_size: null,
        before: null,
      },
      {
        tenant: "o",
        user_id: "u2",
        status: "approved",
        page_size: 5,
        before: "2026-10-05",
      },
    ]);
  });

  it("reads an open week without a timesheet and defaults its totals", async () => {
    const fake = transport({
      get_timesheet: () => ({
        id: null,
        organizationId: "o",
        userId: "u1",
        week: "2026-10-05",
        status: "open",
        entries: [],
        totals: null,
      }),
    });
    const time = createTimeTracking({ transport: fake });
    const sheet = await time.timesheet("o", WEEK).orThrow();
    expect(sheet.id).toBeUndefined();
    expect(sheet.totals).toEqual({ seconds: 0, billableSeconds: 0, amount: 0 });
  });

  it("rejects an unknown timesheet status", async () => {
    const fake = transport({
      submit_timesheet: () => ({ ...SHEET, status: "lost" }),
    });
    const time = createTimeTracking({ transport: fake });
    expect((await time.submit("o", WEEK)).ok).toBe(false);
  });

  it("wraps its methods with hooks", async () => {
    const seen: string[] = [];
    const fake = transport({ stop_timer: () => ENTRY });
    const time = createTimeTracking({
      transport: fake,
      schema: "better_supabase",
      hooks: {
        stop: {
          before: () => {
            seen.push("before");
          },
        },
      },
      logger: console,
    });
    await time.stop("o").orThrow();
    expect(seen).toEqual(["before"]);
  });
});
