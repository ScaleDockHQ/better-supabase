import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type {
  DueSchedule,
  ScheduleProvider,
} from "../../../src/blocks/queue/backends.ts";
import type { Job } from "../../../src/blocks/queue/types.ts";

import {
  BLOCK_TICKS_QUEUE,
  blockTickSchema,
  createQueue,
  isVercelScheduleMessage,
  parseVercelScheduleRun,
  sqlQueueProvider,
  sqlScheduler,
  vercelCronOf,
  vercelNamespaceOf,
  vercelQueueProvider,
  vercelQueueRoute,
  vercelScheduleBridgeRoute,
  vercelScheduleConfig,
  vercelScheduleNameFrom,
  vercelScheduleNameOf,
  vercelScheduler,
  vercelSchedulesErrorOf,
} from "../../../src/blocks/queue/index.ts";
import { testScheduleProvider } from "../../../src/testing/index.ts";
import { fakeSql } from "../../fixtures/fake-sql.ts";
import {
  FakeSchedulesApiError,
  fakeSchedules,
  fakeVercelQueues,
  memoryOnceQueue,
} from "./vercel-fakes.ts";

const NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,255}$/;

const queues = {
  reports: v.object({ kind: v.string() }),
  [BLOCK_TICKS_QUEUE]: blockTickSchema,
};

describe("vercelCronOf", () => {
  it("expands macros and names into five numeric fields", () => {
    expect(vercelCronOf("@daily")).toBe("0 0 * * *");
    expect(vercelCronOf("@hourly")).toBe("0 * * * *");
    expect(vercelCronOf("@weekly")).toBe("0 0 * * 0");
    expect(vercelCronOf("  0   9 * * MON-FRI ")).toBe("0 9 * * 1-5");
    expect(vercelCronOf("0 0 1 JAN,jul *")).toBe("0 0 1 1,7 *");
  });

  it("writes Sunday as 0", () => {
    expect(vercelCronOf("0 0 * * 7")).toBe("0 0 * * 0");
    expect(vercelCronOf("0 0 * * 5-7")).toBe("0 0 * * 0,5,6");
    expect(vercelCronOf("0 0 * * sat,sun")).toBe("0 0 * * 6,0");
  });

  it("names the rule for intervals and for day of month with day of week", () => {
    expect(() => vercelCronOf("30 seconds")).toThrow(/five cron fields/);
    expect(() => vercelCronOf("0 0 1 * 1")).toThrow(
      /both the day of month and the day of week/,
    );
    expect(() => vercelCronOf("nope")).toThrow(TypeError);
  });
});

describe("Vercel schedule names", () => {
  it("escapes what Vercel rejects and reads it back", async () => {
    for (const name of [
      "block:sla.check",
      "workflow:run_42",
      "0-starts-with-zero",
      ".dot",
      "tenant/äöü report",
      "_",
    ]) {
      const encoded = await vercelScheduleNameOf(name);

      expect(encoded).toMatch(NAME);
      expect(vercelScheduleNameFrom(encoded)).toBe(name);
    }

    expect(await vercelScheduleNameOf("block:sla.check")).toBe(
      "block_3asla.check",
    );
    expect(await vercelScheduleNameOf("cleanup-1.v2")).toBe("cleanup-1.v2");
  });

  it("hashes a name whose encoding passes 256 characters", async () => {
    const encoded = await vercelScheduleNameOf(":".repeat(100));

    expect(encoded).toMatch(/^h_x[0-9a-f]{64}$/);
    expect(vercelScheduleNameFrom(encoded)).toBeNull();
    expect(await vercelScheduleNameOf("a".repeat(256))).toBe("a".repeat(256));
  });

  it("keeps a UUID tenant as its namespace and refuses an empty one", async () => {
    const tenant = "4b7a4c1e-7d5f-4b8e-9c1a-2f3e4d5c6b7a";

    expect(await vercelNamespaceOf(tenant)).toBe(tenant);
    expect(await vercelNamespaceOf(`0${tenant.slice(1)}`)).toBe(
      `0_30${tenant.slice(1)}`,
    );
    expect(await vercelNamespaceOf("org_42")).toBe("org_5f42");
    expect(await vercelNamespaceOf("acme")).toBe("acme");
    await expect(vercelNamespaceOf("")).rejects.toThrow(/empty/);
  });

  it("reads a name it didn't write as null", () => {
    expect(vercelScheduleNameFrom("bad_zz")).toBeNull();
    expect(vercelScheduleNameFrom("bad_ff")).toBeNull();
  });
});

const runHeaders = {
  "ce-specversion": "1.0",
  "ce-type": "com.vercel.schedule.v1beta",
  "ce-source": "/schedule/default/cleanup",
  "ce-id": "schx_1",
  "ce-vssscheduleid": "sch_1",
  "ce-vssschedulename": "cleanup",
  "ce-vssnamespace": "default",
  "ce-vssscheduledat": "2026-11-14T09:00:00.000Z",
  "ce-vssschedulesource": "static",
  "ce-vssexpression": "0 9 * * *",
};

describe("parseVercelScheduleRun", () => {
  it("reads the ce headers of a run", () => {
    const run = parseVercelScheduleRun(
      new Request("https://app.test/api/jobs/drain", {
        method: "POST",
        headers: runHeaders,
      }),
    );

    expect(run).toMatchObject({
      executionId: "schx_1",
      scheduleId: "sch_1",
      name: "cleanup",
      namespace: "default",
      source: "static",
      expression: "0 9 * * *",
    });
    expect(run?.scheduledAt.toString()).toBe("2026-11-14T09:00:00Z");
  });

  it("answers null for a request that isn't a run", () => {
    expect(
      parseVercelScheduleRun(
        new Request("https://app.test/", { method: "POST" }),
      ),
    ).toBeNull();
    expect(
      parseVercelScheduleRun(
        new Request("https://app.test/", {
          method: "POST",
          headers: { ...runHeaders, "ce-vssscheduledat": "yesterday" },
        }),
      ),
    ).toBeNull();
  });

  it("recognizes a schedule queue message", () => {
    expect(
      isVercelScheduleMessage({
        scheduleId: "sch_1",
        executionId: "schx_1",
        name: "n",
        namespace: "default",
        scheduledAt: "2026-11-14T09:00:00.000Z",
        expression: "0 9 * * *",
        source: "dynamic",
      }),
    ).toBe(true);
    expect(isVercelScheduleMessage({ payload: {}, max_attempts: 5 })).toBe(
      false,
    );
  });
});

describe("vercelScheduleConfig", () => {
  it("writes workers as paths, private workers as functions and timers as topics", async () => {
    const config = await vercelScheduleConfig({
      workers: [
        { name: "queue-drain", path: "/api/jobs/drain", schedule: "* * * * *" },
        { name: "outbox-relay", path: "/api/outbox", schedule: "*/5 * * * *" },
        { name: "no-path" },
      ],
      private: {
        "queue-drain": {
          source: "src/app/api/jobs/drain/route.ts",
          function: "app/api/jobs/drain/route",
        },
      },
      timers: [{ name: "block:sla.check", cron: "@hourly" }],
      jitter: 2,
    });

    expect(config).toEqual({
      functions: {
        "src/app/api/jobs/drain/route.ts": {
          experimentalTriggers: [{ type: "schedule/v1beta" }],
        },
      },
      schedules: {
        "queue-drain": {
          schedule: "* * * * *",
          jitter: 2,
          function: "app/api/jobs/drain/route",
        },
        "outbox-relay": {
          schedule: "*/5 * * * *",
          jitter: 2,
          path: "/api/outbox",
        },
        "block_3asla.check": {
          schedule: "0 * * * *",
          jitter: 2,
          topic: "block_ticks",
        },
      },
    });
  });

  it("checks the Hobby limits", async () => {
    await expect(
      vercelScheduleConfig({
        hobby: true,
        timers: [{ name: "block:sla.check", cron: "*/5 * * * *" }],
      }),
    ).rejects.toThrow(/every 5 minutes; Hobby/);
    await expect(
      vercelScheduleConfig({
        hobby: true,
        timers: [{ name: "a", cron: "0,10 3 * * *" }],
      }),
    ).rejects.toThrow(/every 10 minutes/);
    await expect(
      vercelScheduleConfig({ hobby: true, jitter: 5, timers: [] }),
    ).rejects.toThrow(/15-minute jitter/);

    const ok = await vercelScheduleConfig({
      hobby: true,
      ticks: "bsb_schedules",
      timers: [{ name: "block:a.b", cron: "*/15 * * * *" }],
    });

    expect(ok.schedules["block_3aa.b"]).toEqual({
      schedule: "*/15 * * * *",
      topic: "bsb_schedules",
    });
  });
});

describe("vercelSchedulesErrorOf", () => {
  it("maps the API's codes to DbErrors", () => {
    const kind = (status: number, code: string, retryAfter?: number) =>
      vercelSchedulesErrorOf(
        new FakeSchedulesApiError(status, code, retryAfter),
      );

    expect(kind(429, "rate_limited", 7)).toMatchObject({
      kind: "rate_limited",
      retryAfter: 7,
      code: "rate_limited",
    });

    for (const code of [
      "static_schedule",
      "invalid_cron_expression",
      "payload_too_large",
      "jitter_exceeds_cadence",
    ]) {
      expect(kind(400, code)?.kind).toBe("invalid_request");
    }

    expect(kind(403, "forbidden")?.kind).toBe("forbidden");
    expect(kind(402, "feature_blocked")?.kind).toBe("quota_exceeded");
    expect(kind(503, "service_unavailable", 3)).toMatchObject({
      kind: "network",
      retryAfter: 3,
    });
    expect(kind(404, "not_found")?.kind).toBe("not_found");
    expect(vercelSchedulesErrorOf(new Error("plain"))).toBeUndefined();
  });
});

describe("vercelScheduler", () => {
  it("passes the schedule provider kit", async () => {
    const report = await testScheduleProvider(
      vercelScheduler(fakeSchedules().client),
      { prefix: "kit:", queue: "reports", tenant: "acme", rejectsProbes: true },
    );

    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });

  it("passes the kit with a bridge, keeping probes", async () => {
    const report = await testScheduleProvider(
      vercelScheduler(fakeSchedules().client, { bridge: "bsb_schedules" }),
      { prefix: "kit:", queue: "reports", probe: "public.has_reports" },
    );

    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });

  it("writes the job body as the payload, in its tenant's namespace", async () => {
    const schedules = fakeSchedules();
    const vq = fakeVercelQueues();

    const jobs = createQueue({
      backend: vercelQueueProvider(vq.client),
      scheduler: vercelScheduler(schedules.client, { jitter: 3 }),
      queues,
    });

    await jobs
      .schedule({
        name: "report:daily",
        cron: "0 9 * * MON",
        queue: "reports",
        payload: { kind: "daily" },
        timeZone: "Europe/Amsterdam",
        tenant: "acme",
      })
      .orThrow();

    const stored = schedules.space("acme").get("report_3adaily");

    expect(stored).toMatchObject({
      expression: { type: "cron", cron: "0 9 * * 1" },
      timezone: "Europe/Amsterdam",
      target: { type: "queue", topic: "reports" },
      payload: {
        payload: { kind: "daily" },
        max_attempts: 5,
        name: "report:daily",
        queue: "reports",
      },
    });

    expect(
      await jobs.listSchedules({ tenant: "acme" }).orThrow(),
    ).toMatchObject([
      {
        name: "report:daily",
        cron: "0 9 * * 1",
        queue: "reports",
        tenant: "acme",
        probe: null,
      },
    ]);
    expect(await jobs.listSchedules().orThrow()).toEqual([]);
    expect(
      await jobs.unschedule("report:daily", { tenant: "acme" }).orThrow(),
    ).toBe(true);
    expect(
      await jobs.unschedule("report:daily", { tenant: "acme" }).orThrow(),
    ).toBe(false);
  });

  it("rejects a probe without a bridge as invalid_request", async () => {
    const jobs = createQueue({
      backend: vercelQueueProvider(fakeVercelQueues().client),
      scheduler: vercelScheduler(fakeSchedules().client),
      queues,
    });

    const result = await jobs.schedule({
      name: "report:probe",
      cron: "0 9 * * *",
      queue: "reports",
      payload: { kind: "daily" },
      probe: "public.has_reports",
    });

    expect(result.ok).toBe(false);
    expect(!result.ok && result.error.kind).toBe("invalid_request");
    expect(!result.ok && result.error.message).toMatch(/bridge/);
  });

  it("refuses what Vercel can't store before calling it", async () => {
    const schedules = fakeSchedules();
    const scheduler = vercelScheduler(schedules.client);
    const at = Temporal.Now.instant();

    await expect(
      scheduler.schedule(
        "big",
        "0 9 * * *",
        "reports",
        { x: "y".repeat(17_000) },
        "UTC",
        at,
      ),
    ).rejects.toMatchObject({ kind: "invalid_request" });
    await expect(
      scheduler.schedule("fast", "30 seconds", "reports", {}, "UTC", at),
    ).rejects.toMatchObject({ kind: "invalid_request" });
    expect(schedules.calls).toEqual([]);
  });

  it("maps a static schedule and a rate limit, and retries a create race", async () => {
    const schedules = fakeSchedules();
    const at = Temporal.Now.instant();

    schedules.addStatic("cleanup", "0 3 * * *", "reports");

    await expect(
      vercelScheduler(schedules.client, { namespace: "default" }).schedule(
        "cleanup",
        "0 4 * * *",
        "reports",
        {},
        "UTC",
        at,
      ),
    ).rejects.toMatchObject({
      kind: "invalid_request",
      code: "static_schedule",
    });

    const limited = vercelScheduler({
      ...schedules.client,
      update: () =>
        Promise.reject(new FakeSchedulesApiError(429, "rate_limited", 2)),
    });

    await expect(
      limited.schedule("x", "0 4 * * *", "reports", {}, "UTC", at),
    ).rejects.toMatchObject({ error: { kind: "rate_limited", retryAfter: 2 } });

    let updates = 0;

    const raced = vercelScheduler({
      ...schedules.client,
      update: async (params) => {
        updates += 1;

        if (updates === 1) {
          throw new FakeSchedulesApiError(404, "not_found");
        }

        return schedules.client.update(params);
      },
      create: async (params) => {
        await schedules.client.create(params);
        throw new FakeSchedulesApiError(409, "schedule_already_exists");
      },
    });

    await raced.schedule("race", "0 4 * * *", "reports", {}, "UTC", at);
    expect(updates).toBe(2);
  });

  it("removes a tenant's schedules across pages", async () => {
    const schedules = fakeSchedules();
    const scheduler = vercelScheduler(schedules.client);
    const at = Temporal.Now.instant();

    for (let index = 0; index < 130; index += 1) {
      await scheduler.schedule(
        `t:${String(index)}`,
        "0 4 * * *",
        "reports",
        {},
        "UTC",
        at,
        "acme",
      );
    }

    const passed = vercelScheduler({
      ...schedules.client,
      delete: async (params) => {
        if (params.name === "t_3a7") {
          throw new FakeSchedulesApiError(400, "schedule_single_at_passed");
        }

        return schedules.client.delete(params);
      },
    });

    expect(await passed.unscheduleTenant?.("acme")).toBe(129);
    expect(schedules.space("acme").size).toBe(1);
  });

  it("keeps the tenant-less namespace apart from tenants", async () => {
    const scheduler = vercelScheduler(fakeSchedules().client);

    await expect(
      scheduler.schedule(
        "x",
        "0 4 * * *",
        "reports",
        {},
        "UTC",
        Temporal.Now.instant(),
        "better-supabase",
      ),
    ).rejects.toMatchObject({ kind: "invalid_request" });
  });
});

describe("queue and scheduler pairs", () => {
  const sql = fakeSql().sql;

  it("throws when pg_cron meets a queue outside the database", () => {
    expect(() =>
      createQueue({
        backend: vercelQueueProvider(fakeVercelQueues().client),
        scheduler: sqlScheduler(sql),
        queues,
      }),
    ).toThrow(/pg_cron, which the "vercel-queues" queue never reads/);
  });

  it("throws when Vercel Schedules publishes to topics a SQL queue never reads", () => {
    expect(() =>
      createQueue({
        sql,
        scheduler: vercelScheduler(fakeSchedules().client),
        queues,
      }),
    ).toThrow(/bridge/);
  });

  it("accepts the four pairs", () => {
    const vercel = () => vercelQueueProvider(fakeVercelQueues().client);
    const schedules = () => fakeSchedules().client;

    expect(() => createQueue({ sql, queues })).not.toThrow();
    expect(() =>
      createQueue({
        sql,
        scheduler: vercelScheduler(schedules(), { bridge: "bsb_schedules" }),
        queues,
      }),
    ).not.toThrow();
    expect(() =>
      createQueue({
        backend: vercel(),
        scheduler: sqlScheduler(sql, { mode: "drain" }),
        queues,
      }),
    ).not.toThrow();
    expect(() =>
      createQueue({
        backend: vercel(),
        scheduler: vercelScheduler(schedules()),
        queues,
      }),
    ).not.toThrow();
    expect(() =>
      createQueue({
        backend: sqlQueueProvider(sql),
        scheduler: sqlScheduler(sql),
        queues,
      }),
    ).not.toThrow();
  });
});

/** A drain scheduler in memory: every schedule is due once. */
function memoryDrain(): ScheduleProvider & { readonly advanced: string[] } {
  const due = new Map<string, DueSchedule>();
  const advanced: string[] = [];

  return {
    apiVersion: 1,
    name: "memory-drain",
    advanced,
    schedule: async (name, cron, queue, payload, timeZone, nextRun) => {
      due.set(name, { name, cron, queue, payload, timeZone, nextRun });
    },
    unschedule: async (name) => due.delete(name),
    dueSchedules: async () => {
      const list = [...due.values()];
      due.clear();

      return list;
    },
    advanceSchedule: async (name) => {
      advanced.push(name);

      return true;
    },
  };
}

describe("runSchedules on Vercel Queues", () => {
  it("sends due runs in batches and advances only the sent ones", async () => {
    const vq = fakeVercelQueues();
    const drain = memoryDrain();
    const past = Temporal.Now.instant().subtract({ minutes: 1 });

    const jobs = createQueue({
      backend: vercelQueueProvider(vq.client),
      scheduler: drain,
      queues,
    });

    for (const name of ["a", "b", "c"]) {
      await drain.schedule(
        name,
        "* * * * *",
        "reports",
        { kind: name },
        "UTC",
        past,
      );
    }

    expect(await jobs.runSchedules().orThrow()).toBe(3);
    expect(vq.batches).toEqual([3]);
    expect(vq.open("reports")).toHaveLength(3);
    expect(drain.advanced).toEqual(["a", "b", "c"]);

    const failing = vercelQueueProvider({
      ...vq.client,
      sendBatch: async (_topic, messages) =>
        messages.map((_, index) =>
          index === 0
            ? { status: "failed" as const, statusCode: 500, error: "boom" }
            : { status: "sent" as const, messageId: `x${String(index)}` },
        ),
    });

    const partial = memoryDrain();
    const jobs2 = createQueue({ backend: failing, scheduler: partial, queues });

    await partial.schedule("a", "* * * * *", "reports", {}, "UTC", past);
    await partial.schedule("b", "* * * * *", "reports", {}, "UTC", past);

    const result = await jobs2.runSchedules();

    expect(result.ok).toBe(false);
    expect(partial.advanced).toEqual(["b"]);
  });

  it("sends one at a time without sendBatch", async () => {
    const vq = fakeVercelQueues({ batch: false });
    const drain = memoryDrain();

    const jobs = createQueue({
      backend: vercelQueueProvider(vq.client),
      scheduler: drain,
      queues,
    });

    const past = Temporal.Now.instant().subtract({ minutes: 1 });

    await drain.schedule("a", "* * * * *", "reports", {}, "UTC", past);
    await drain.schedule("b", "* * * * *", "reports", {}, "UTC", past);

    expect(await jobs.runSchedules().orThrow()).toBe(2);
    expect(vq.batches).toEqual([]);
    expect(vq.open("reports")).toHaveLength(2);
  });
});

describe("schedulesRoute", () => {
  it("runs the due schedules behind the bearer secret", async () => {
    const drain = memoryDrain();

    const jobs = createQueue({
      backend: vercelQueueProvider(fakeVercelQueues().client),
      scheduler: drain,
      queues,
    });

    await drain.schedule(
      "a",
      "* * * * *",
      "reports",
      {},
      "UTC",
      Temporal.Now.instant(),
    );

    const route = jobs.schedulesRoute({ secret: "s3cret" });

    const denied = await route(
      new Request("https://app.test/api/jobs/schedules"),
    );

    expect(denied.status).toBe(401);

    const ran = await route(
      new Request("https://app.test/api/jobs/schedules", {
        method: "POST",
        headers: { authorization: "Bearer s3cret" },
      }),
    );

    expect(await ran.json()).toEqual({ schedules: 1, errors: 0 });
  });

  it("takes a Vercel schedule run without the secret when caller says so", async () => {
    const jobs = createQueue({
      backend: vercelQueueProvider(fakeVercelQueues().client),
      scheduler: memoryDrain(),
      queues,
    });

    const route = jobs.schedulesRoute({
      secret: undefined,
      caller: "vercel-schedule",
    });

    expect(
      (
        await route(
          new Request("https://app.test/api/jobs/schedules", {
            method: "POST",
            headers: runHeaders,
          }),
        )
      ).status,
    ).toBe(200);
    expect(
      (await route(new Request("https://app.test/api/jobs/schedules"))).status,
    ).toBe(401);
  });
});

describe("vercelQueueRoute with Vercel Schedules", () => {
  it("unwraps a dynamic run and exposes it on the job", async () => {
    const schedules = fakeSchedules();
    const vq = fakeVercelQueues();
    const seen: Job[] = [];

    const jobs = createQueue({
      backend: vercelQueueProvider(vq.client),
      scheduler: vercelScheduler(schedules.client),
      queues,
    });

    vercelQueueRoute(jobs, {
      client: vq.client,
      handlers: {
        reports: (payload, job) => {
          seen.push(job);
          expect(payload).toEqual({ kind: "weekly" });
        },
      },
    });

    await jobs
      .schedule({
        name: "report:weekly",
        cron: "@weekly",
        queue: "reports",
        payload: { kind: "weekly" },
      })
      .orThrow();

    const run = schedules.fire("report_3aweekly", "better-supabase");

    vq.publish(run.topic, run.message);
    expect(await vq.deliver("reports")).toEqual([]);
    expect(seen[0]?.schedule).toMatchObject({
      name: "report:weekly",
      executionId: "schx_1",
    });
    expect(seen[0]?.schedule?.scheduledAt.toString()).toBe(
      "2026-11-14T09:00:00Z",
    );
  });

  it("maps a static block timer back to its tick", async () => {
    const schedules = fakeSchedules();
    const vq = fakeVercelQueues();
    const ticks: unknown[] = [];

    const jobs = createQueue({
      backend: vercelQueueProvider(vq.client),
      queues,
    });

    vercelQueueRoute(jobs, {
      client: vq.client,
      handlers: { [BLOCK_TICKS_QUEUE]: (payload) => void ticks.push(payload) },
    });

    const config = await vercelScheduleConfig({
      timers: [{ name: "block:workflows.schedules.tick", cron: "* * * * *" }],
    });

    for (const [name, schedule] of Object.entries(config.schedules)) {
      schedules.addStatic(name, schedule.schedule, schedule.topic ?? "");
      const run = schedules.fire(name);
      vq.publish(run.topic, run.message);
    }

    expect(await vq.deliver(BLOCK_TICKS_QUEUE)).toEqual([]);
    expect(ticks).toEqual([{ block: "workflows", name: "schedules.tick" }]);
  });
});

describe("vercelScheduleBridgeRoute", () => {
  it("enqueues each run once, and skips a run whose probe has no work", async () => {
    const schedules = fakeSchedules();
    const vq = fakeVercelQueues();
    const db = memoryOnceQueue({ "public.no_reports": false });
    const skipped: string[] = [];

    const jobs = createQueue({
      backend: db.provider,
      scheduler: vercelScheduler(schedules.client, { bridge: "bsb_schedules" }),
      queues,
    });

    vercelScheduleBridgeRoute(jobs, {
      client: vq.client,
      onSkip: (run) => skipped.push(run.name),
    });

    await jobs
      .schedule({
        name: "report:daily",
        cron: "0 9 * * *",
        queue: "reports",
        payload: { kind: "daily" },
      })
      .orThrow();
    await jobs
      .schedule({
        name: "report:probed",
        cron: "0 9 * * *",
        queue: "reports",
        payload: { kind: "probed" },
        probe: "public.no_reports",
      })
      .orThrow();

    const daily = schedules.fire("report_3adaily", "better-supabase");

    vq.publish(daily.topic, daily.message);
    vq.publish(daily.topic, daily.message);
    const probed = schedules.fire("report_3aprobed", "better-supabase");
    vq.publish(probed.topic, probed.message);

    expect(daily.topic).toBe("bsb_schedules");
    expect(await vq.deliver("bsb_schedules")).toEqual([]);
    expect(db.sent).toEqual([
      {
        queue: "reports",
        payload: { kind: "daily" },
        key: "schedule:report:daily:schx_1",
      },
    ]);
    expect(db.probes).toEqual(["public.no_reports"]);
    expect(skipped).toEqual(["report:probed"]);
  });

  it("runs a static block timer on block_ticks and retries what names no queue", async () => {
    const schedules = fakeSchedules();
    const vq = fakeVercelQueues();
    const db = memoryOnceQueue();
    const errors: string[] = [];

    const jobs = createQueue({ backend: db.provider, queues });

    vercelScheduleBridgeRoute(jobs, {
      client: vq.client,
      onError: (error) => errors.push(error.message),
    });

    schedules.addStatic("block_3asla.check", "* * * * *", "bsb_schedules");
    schedules.addStatic("cleanup", "0 3 * * *", "bsb_schedules");

    for (const name of ["block_3asla.check", "cleanup"]) {
      const run = schedules.fire(name);
      vq.publish(run.topic, run.message);
    }

    const failures = await vq.deliver("bsb_schedules");

    expect(db.sent).toEqual([
      {
        queue: BLOCK_TICKS_QUEUE,
        payload: { block: "sla", name: "check" },
        key: "schedule:block:sla.check:schx_1",
      },
    ]);
    expect(failures).toHaveLength(1);
    expect(String(failures[0])).toMatch(/names no queue/);
    expect(errors).toEqual([]);
  });
});
