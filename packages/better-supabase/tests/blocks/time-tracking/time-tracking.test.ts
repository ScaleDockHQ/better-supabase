import { describe, expect, it } from "vitest";

import { createTimeTracking } from "../../../src/blocks/time-tracking/index.ts";
import { money } from "../../../src/commerce/money.ts";

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
  rate: "10000",
  rateCurrency: "EUR",
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
  rateCurrency: null,
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

    const time = createTimeTracking({ transport: fake, tenant: "o" });
    const started = await time.start().orThrow();
    expect(started).toMatchObject({ id: "e2", billable: false });
    expect(started.endedAt).toBeUndefined();
    expect(started.seconds).toBeUndefined();
    expect(started.subject).toBeUndefined();
    await time
      .start({
        subject: { type: "project", id: "apollo" },
        billable: true,
        rate: money(8000n, "EUR"),
        note: "x",
      })
      .orThrow();
    const stopped = await time.stop().orThrow();
    expect(stopped).toMatchObject({
      seconds: 7200,
      rate: money(10_000n, "EUR"),
      note: "Design",
    });
    expect(stopped.endedAt?.toString()).toBe("2026-10-06T11:00:00Z");
    expect(await time.running().orThrow()).toBeUndefined();
    expect(fake.calls).toEqual([
      [
        "start_timer",
        {
          tenant: "o",
          subject_type: null,
          subject_id: null,
          billable: false,
          rate: null,
          rate_currency: null,
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
          rate: "8000",
          rate_currency: "EUR",
          note: "x",
        },
      ],
      ["stop_timer", { tenant: "o", entry: null }],
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

    const time = createTimeTracking({ transport: fake, tenant: "o" });
    expect((await time.running().orThrow())?.id).toBe("e2");
    const start = Temporal.Instant.from(AT);
    const end = Temporal.Instant.from("2026-10-06T11:00:00Z");
    await time.log({ startedAt: start, endedAt: end }).orThrow();
    await time
      .log({
        startedAt: start,
        endedAt: end,
        subject: { type: "project", id: "apollo" },
        billable: true,
        rate: money(10_000n, "EUR"),
        note: "Design",
        userId: "u2",
      })
      .orThrow();
    await time
      .update("e1", {
        startedAt: start,
        endedAt: end,
        subject: { type: "project", id: "zeus" },
        billable: false,
        rate: null,
        note: null,
      })
      .orThrow();
    await time.update("e1", { subject: null }).orThrow();
    await time.update("e1", {}).orThrow();
    await time.remove("e1").orThrow();
    const listed = await time.list().orThrow();
    expect(listed.map((entry) => entry.id)).toEqual(["e1", "e2"]);
    expect(listed.map((entry) => entry.subject)).toEqual([
      { type: "project", id: "apollo" },
      undefined,
    ]);
    await time
      .list({
        userId: "u2",
        everyone: true,
        from: start,
        to: end,
        subject: { type: "project", id: "apollo" },
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
          rate_currency: null,
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
          rate: "10000",
          rate_currency: "EUR",
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
            rateCurrency: null,
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
        totals: {
          seconds: 7200,
          billableSeconds: 7200,
          amounts: [
            { amount: "20000", currency: "EUR" },
            { amount: "5000", currency: "USD" },
          ],
        },
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

    const time = createTimeTracking({ transport: fake, tenant: "o" });
    const sheet = await time.timesheet(WEEK).orThrow();
    expect(sheet.week.toString()).toBe("2026-10-05");
    expect(sheet.status).toBe("submitted");
    expect(sheet.entries.map((entry) => entry.id)).toEqual(["e1"]);
    expect(sheet.totals).toEqual({
      seconds: 7200,
      billableSeconds: 7200,
      amounts: [money(20_000n, "EUR"), money(5000n, "USD")],
    });
    await time.timesheet(WEEK, "u2").orThrow();
    expect(await time.submit(WEEK).orThrow()).toMatchObject({
      id: "t1",
      approvalId: "a1",
    });
    await time.submit(WEEK, "Week 41").orThrow();
    const reopened = await time.reopen("t1").orThrow();
    expect(reopened.status).toBe("open");
    expect(reopened.approvalId).toBeUndefined();
    const [approved] = await time.timesheets().orThrow();
    expect(approved?.approvedAt?.toString()).toBe(AT);
    await time
      .timesheets({
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

    const time = createTimeTracking({ transport: fake, tenant: "o" });
    const sheet = await time.timesheet(WEEK).orThrow();
    expect(sheet.id).toBeUndefined();
    expect(sheet.totals).toEqual({
      seconds: 0,
      billableSeconds: 0,
      amounts: [],
    });
  });

  it("sends a rate change as minor units and currency, and refuses an unknown code", async () => {
    const fake = transport({ update_time_entry: () => ENTRY });

    const time = createTimeTracking({ transport: fake, tenant: "o" });
    await time.update("e1", { rate: money(12_550n, "USD") }).orThrow();
    expect(fake.calls).toEqual([
      [
        "update_time_entry",
        { entry_id: "e1", patch: { rate: "12550", rateCurrency: "USD" } },
      ],
    ]);

    for (const result of [
      await time.start({ rate: { amount: 100n, currency: "XYZ" } }),
      await time.update("e1", { rate: { amount: 100n, currency: "XYZ" } }),
    ]) {
      expect(result.ok ? undefined : result.error).toMatchObject({
        kind: "invalid_request",
        hint: "CURRENCY_INVALID",
      });
    }

    expect(fake.calls).toHaveLength(1);
  });

  it("refuses a rate sent as a JSON number", async () => {
    const fake = transport({ stop_timer: () => ({ ...ENTRY, rate: 100 }) });

    const time = createTimeTracking({ transport: fake, tenant: "o" });
    expect((await time.stop()).ok).toBe(false);
  });

  it("acts for an employee and reads employee rows without an account", async () => {
    const crew = { ...ENTRY, userId: null, employeeId: "emp1" };

    const fake = transport({
      log_time: () => crew,
      list_time_entries: () => [crew],
      get_timesheet: () => ({
        ...SHEET,
        userId: null,
        employeeId: "emp1",
        entries: [crew],
        totals: { seconds: 7200, billableSeconds: 7200, amounts: [] },
      }),
      submit_timesheet: () => ({ ...SHEET, userId: null, employeeId: "emp1" }),
      list_timesheets: () => [{ ...SHEET, userId: null, employeeId: "emp1" }],
    });

    const time = createTimeTracking({ transport: fake, tenant: "o" });

    const logged = await time
      .log({
        startedAt: Temporal.Instant.from(AT),
        endedAt: Temporal.Instant.from("2026-10-06T11:00:00Z"),
        employeeId: "emp1",
      })
      .orThrow();

    expect(logged).toMatchObject({ userId: "", employeeId: "emp1" });
    await time.list({ employeeId: "emp1" }).orThrow();

    expect(
      await time.timesheet(WEEK, undefined, "emp1").orThrow(),
    ).toMatchObject({ employeeId: "emp1", userId: "" });

    await time.submit(WEEK, undefined, "emp1").orThrow();
    await time.timesheets({ employeeId: "emp1" }).orThrow();

    expect(
      fake.calls.map(
        ([, args]) => (args as { employee_id?: string }).employee_id,
      ),
    ).toEqual(["emp1", "emp1", "emp1", "emp1", "emp1"]);
  });

  it("sends no employee argument unless one is given", async () => {
    const fake = transport({ list_time_entries: () => [] });
    const time = createTimeTracking({ transport: fake, tenant: "o" });

    await time.list().orThrow();
    expect(fake.calls[0]?.[1]).not.toHaveProperty("employee_id");
  });

  it("rejects an unknown timesheet status", async () => {
    const fake = transport({
      submit_timesheet: () => ({ ...SHEET, status: "lost" }),
    });

    const time = createTimeTracking({ transport: fake, tenant: "o" });
    expect((await time.submit(WEEK)).ok).toBe(false);
  });

  it("fails without a tenant", async () => {
    const fake = transport({ stop_timer: () => ENTRY });
    const session: { tenant?: string } = {};

    const time = createTimeTracking({
      transport: fake,
      tenant: () => session.tenant,
    });

    for (const result of [
      await time.start(),
      await time.stop(),
      await time.list(),
      await time.submit(WEEK),
    ]) {
      expect(result).toMatchObject({
        ok: false,
        error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
      });
    }

    expect(fake.calls).toEqual([]);
    session.tenant = "o2";
    await time.stop().orThrow();
    expect(fake.calls).toEqual([["stop_timer", { tenant: "o2", entry: null }]]);
  });

  it("wraps its methods with hooks", async () => {
    const seen: string[] = [];
    const fake = transport({ stop_timer: () => ENTRY });

    const time = createTimeTracking({
      transport: fake,
      schema: "better_supabase",
      tenant: "o",
      hooks: {
        stop: {
          before: () => {
            seen.push("before");
          },
        },
      },
      logger: console,
    });

    await time.stop().orThrow();
    expect(seen).toEqual(["before"]);
  });

  it("stops one of several timers, lists them, resumes one and keeps a currency without a rate", async () => {
    const fake = transport({
      start_timer: () => RUNNING,
      stop_timer: () => ENTRY,
      running_timers: () => [RUNNING],
      resume_timer: () => RUNNING,
    });

    const time = createTimeTracking({ transport: fake, tenant: "o" });
    await time.start({ currency: "EUR" }).orThrow();
    await time.stop("e2").orThrow();
    const running = await time.runningAll().orThrow();
    await time.resume("e2").orThrow();

    expect(running.map((entry) => entry.id)).toEqual(["e2"]);
    expect(fake.calls[0]?.[1]).toMatchObject({
      rate: null,
      rate_currency: "EUR",
    });
    expect(fake.calls.slice(1)).toEqual([
      ["stop_timer", { tenant: "o", entry: "e2" }],
      ["running_timers", { tenant: "o" }],
      ["resume_timer", { entry: "e2" }],
    ]);
  });
});
