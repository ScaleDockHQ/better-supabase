import { describe, expect, it, vi } from "vitest";

import type {
  DueSchedule,
  ScheduleProvider,
  StoredSchedule,
} from "../../src/blocks/queue/backends.ts";
import type {
  EveDynamicRunArgs,
  EveDynamicSchedules,
  EveScheduleAuthContext,
  EveScheduleJob,
  EveScheduleOccurrence,
  EveScheduleOccurrenceEvent,
  EveScheduleOptions,
  EveScheduleProviderContext,
  EveScheduleRun,
  EveSendOptions,
  EveSessionAuth,
} from "../../src/eve/index.ts";

import { nextCronRun } from "../../src/core/cron.ts";
import { DbException } from "../../src/core/errors.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import { temporal } from "../../src/core/temporal-required.ts";
import {
  eveScheduleRun,
  queueDynamicSchedules,
  queueScheduleProvider,
} from "../../src/eve/index.ts";
import { testScheduleProvider } from "../../src/testing/kits/schedule-provider.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const ORG = "22222222-2222-4222-8222-222222222222";
const ISSUER = "https://project.supabase.co/auth/v1";
const NOW = temporal().Instant.from("2026-11-14T09:00:00Z");

interface Row {
  cron: string;
  timeZone: string;
  queue: string;
  payload: unknown;
  tenant: string | undefined;
  nextRun: Temporal.Instant;
  leasedUntil: Temporal.Instant | null;
}

/**
 * A drain-style scheduler that keeps payloads, as `sqlScheduler({ mode: "drain"
 * })` does.
 */
function memoryScheduler(): ScheduleProvider & {
  readonly rows: Map<string, Row>;
} {
  const rows = new Map<string, Row>();

  const stored = (name: string, row: Row): StoredSchedule => ({
    name,
    cron: row.cron,
    timeZone: row.timeZone,
    queue: row.queue,
    tenant: row.tenant ?? null,
    nextRun: row.nextRun,
    lastRun: null,
    leasedUntil: row.leasedUntil,
    createdAt: null,
    probe: null,
    payload: row.payload,
  });

  return {
    apiVersion: 1,
    name: "memory-drain",
    rows,
    async schedule(name, cron, queue, payload, timeZone, nextRun, tenant) {
      const previous = rows.get(name);
      const same = previous?.cron === cron && previous.timeZone === timeZone;

      rows.set(name, {
        cron,
        timeZone,
        queue,
        payload,
        tenant,
        nextRun: same ? previous.nextRun : nextRun,
        leasedUntil: null,
      });
    },
    async unschedule(name) {
      return rows.delete(name);
    },
    async listSchedules(filter) {
      return [...rows]
        .filter(
          ([name, row]) =>
            name.startsWith(filter.prefix ?? "") &&
            (filter.tenant === undefined || row.tenant === filter.tenant),
        )
        .map(([name, row]) => stored(name, row));
    },
    async unscheduleTenant(tenant) {
      const owned = [...rows].filter(([, row]) => row.tenant === tenant);

      for (const [name] of owned) {
        rows.delete(name);
      }

      return owned.length;
    },
    async dueSchedules(lease) {
      const now = temporal().Now.instant();
      const due: DueSchedule[] = [];

      for (const [name, row] of rows) {
        const free =
          row.leasedUntil === null ||
          temporal().Instant.compare(row.leasedUntil, now) <= 0;

        if (free && temporal().Instant.compare(row.nextRun, now) <= 0) {
          row.leasedUntil = now.add({ seconds: lease });
          due.push({
            name,
            cron: row.cron,
            timeZone: row.timeZone,
            queue: row.queue,
            payload: row.payload,
            nextRun: row.nextRun,
          });
        }
      }

      return due;
    },
    async advanceSchedule(name, ran, next) {
      const row = rows.get(name);

      if (row === undefined || !row.nextRun.equals(ran)) {
        return false;
      }

      row.nextRun = next;
      row.leasedUntil = null;

      return true;
    },
  };
}

/** Eve's stored payload for a creator and scope. */
const stored = (
  task: string,
  scope: string | readonly string[] = [ORG, USER],
) => ({
  eve: { application: "planner", collection: "requests", version: 3 },
  envelope: {
    version: 3,
    payload: { task },
    scope,
    principal: {
      type: "user",
      authenticator: "supabase",
      issuer: ISSUER,
      principalId: USER,
      subject: USER,
    },
  },
});

function context(
  overrides: Partial<EveScheduleProviderContext> = {},
): EveScheduleProviderContext & {
  readonly delivered: {
    readonly payload: unknown;
    readonly occurrence: EveScheduleOccurrence;
  }[];
} {
  const delivered: {
    readonly payload: unknown;
    readonly occurrence: EveScheduleOccurrence;
  }[] = [];

  return {
    abortSignal: new AbortController().signal,
    collection: "requests",
    namespace: "eve-ns-user",
    operationId: "op_1",
    target: {
      key: "planner",
      deliver: async (delivery) => {
        delivered.push(delivery);
      },
    },
    ...overrides,
    delivered,
  };
}

const cron = (expression: string, timezone?: string) =>
  ({
    type: "cron",
    cron: expression,
    ...(timezone === undefined ? {} : { timezone }),
  }) as const;

function setup() {
  const scheduler = memoryScheduler();

  const provider = queueScheduleProvider({
    scheduler,
    tenantOf: (scope) => (typeof scope === "string" ? undefined : scope[0]),
    now: () => NOW,
  });

  return { scheduler, provider };
}

describe("queueScheduleProvider", () => {
  it("runs on a scheduler that passes testScheduleProvider", async () => {
    const report = await testScheduleProvider(memoryScheduler(), {
      prefix: "conformance:eve:",
      queue: "eve_schedules",
      tenant: ORG,
    });

    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("refuses a scheduler that can't list schedules", () => {
    const scheduler = memoryScheduler();

    delete scheduler.listSchedules;

    expect(() => queueScheduleProvider({ scheduler })).toThrow(TypeError);
  });

  it("stores a schedule as one queue block schedule and reads it back without its payload", async () => {
    const { scheduler, provider } = setup();
    const ctx = context();

    const created = await provider.create(ctx, {
      name: `daily--${"a".repeat(8)}-aaaa-4aaa-8aaa-${"a".repeat(12)}`,
      expression: cron("0 9 * * 1-5", "Europe/Amsterdam"),
      payload: stored("Summarize issues"),
    });

    expect(created).toMatchObject({
      displayName: "daily",
      state: "active",
      createdAt: NOW.epochMilliseconds,
      updatedAt: NOW.epochMilliseconds,
      expression: cron("0 9 * * 1-5", "Europe/Amsterdam"),
    });
    expect(created).not.toHaveProperty("payload");
    expect(provider.kind).toBe("better-supabase:memory-drain");

    const [name, row] = [...scheduler.rows][0] ?? [];

    expect(name).toBe(`eve:requests:eve-ns-user:${created.name}`);
    expect(row).toMatchObject({
      cron: "0 9 * * 1-5",
      timeZone: "Europe/Amsterdam",
      queue: "eve_schedules",
      tenant: ORG,
      nextRun: nextCronRun("0 9 * * 1-5", "Europe/Amsterdam", NOW),
    });
    expect(eveScheduleRun["~standard"].validate(row?.payload)).toEqual({
      value: row?.payload,
    });
    expect(await provider.get(ctx, created.name)).toEqual(created);
  });

  it("keeps each collection and namespace apart and pages the list", async () => {
    const { provider } = setup();
    const mine = context();
    const theirs = context({ namespace: "eve-ns-other" });
    const other = context({ collection: "billing/requests" });

    for (const label of ["a", "b", "c"]) {
      await provider.create(mine, {
        name: label,
        expression: cron("0 9 * * *"),
        payload: stored(label),
      });
    }

    await provider.create(theirs, {
      name: "z",
      expression: cron("0 9 * * *"),
      payload: stored("z"),
    });

    const first = await provider.list(mine, { limit: 2 });

    expect(first.data.map((record) => record.name)).toEqual(["a", "b"]);
    expect(first.cursor).toBe("b");
    expect(
      (await provider.list(mine, { cursor: "b" })).data.map(
        (record) => record.name,
      ),
    ).toEqual(["c"]);
    expect((await provider.list(mine, { cursor: "b" })).cursor).toBeNull();
    expect(await provider.get(theirs, "a")).toBeNull();
    expect((await provider.list(other, {})).data).toEqual([]);
    expect(await provider.delete(theirs, "a")).toBe(false);
    await expect(provider.update(other, "a", { payload: {} })).rejects.toThrow(
      DbException,
    );
  });

  it("updates timing alone, replaces the payload and its tenant, and changes state", async () => {
    const { scheduler, provider } = setup();
    const ctx = context();

    await provider.create(ctx, {
      name: "job",
      expression: cron("0 9 * * *"),
      payload: stored("first"),
    });

    const key = "eve:requests:eve-ns-user:job";

    const timed = await provider.update(ctx, "job", {
      expression: cron("0 10 * * *"),
    });

    expect(timed.expression).toEqual(cron("0 10 * * *"));
    expect(scheduler.rows.get(key)?.payload).toMatchObject({
      tenant: ORG,
      payload: stored("first"),
    });

    await provider.update(ctx, "job", { payload: stored("second", "solo") });

    const replaced = scheduler.rows.get(key)?.payload as EveScheduleRun;

    expect(replaced.payload).toEqual(stored("second", "solo"));
    expect(replaced).not.toHaveProperty("tenant");
    expect(replaced.expression).toEqual(cron("0 10 * * *"));

    expect((await provider.disable(ctx, "job")).state).toBe("inactive");
    expect((await provider.disable(ctx, "job")).state).toBe("inactive");
    expect((await provider.enable(ctx, "job")).state).toBe("active");
    expect(await provider.delete(ctx, "job")).toBe(true);
    expect(scheduler.rows.size).toBe(0);
    await expect(provider.enable(ctx, "job")).rejects.toMatchObject({
      error: { kind: "not_found", hint: "EVE_SCHEDULE_NOT_FOUND" },
    });
  });

  it("invokes through the target eve passes, once per operation", async () => {
    const { scheduler, provider } = setup();
    const ctx = context();

    const created = await provider.create(ctx, {
      name: "job",
      expression: cron("0 9 * * *"),
      payload: stored("now"),
    });

    await provider.invoke(ctx, "job");

    expect(ctx.delivered).toEqual([
      {
        payload: stored("now"),
        occurrence: {
          executionId: `${created.scheduleId}:invoke:op_1`,
          name: "job",
          scheduleId: created.scheduleId,
          scheduledAt: NOW.toString(),
        },
      },
    ]);

    await expect(
      provider.invoke(context({ target: { key: "planner" } }), "job"),
    ).rejects.toMatchObject({
      error: { kind: "unsupported", hint: "EVE_SCHEDULE_NO_TARGET" },
    });

    const key = "eve:requests:eve-ns-user:job";
    const row = scheduler.rows.get(key)!;
    row.payload = { ...(row.payload as EveScheduleRun), state: "completed" };

    await expect(provider.invoke(ctx, "job")).rejects.toMatchObject({
      error: { kind: "conflict", hint: "EVE_SCHEDULE_COMPLETED" },
    });
  });

  it("stores a one-time schedule as the cron of its local minute", async () => {
    const { scheduler, provider } = setup();

    await provider.create(context(), {
      name: "once",
      expression: {
        type: "single",
        at: "2026-12-24T18:30",
        timezone: "Europe/Amsterdam",
      },
      payload: stored("gifts"),
    });

    expect(scheduler.rows.get("eve:requests:eve-ns-user:once")).toMatchObject({
      cron: "30 18 24 12 *",
      timeZone: "Europe/Amsterdam",
      nextRun: temporal().Instant.from("2026-12-24T17:30:00Z"),
    });
  });

  it("rejects timing the scheduler can't run and writes nothing", async () => {
    const { scheduler, provider } = setup();

    const create = (
      expression: Parameters<typeof provider.create>[1]["expression"],
    ) =>
      provider.create(context(), {
        name: "job",
        expression,
        payload: stored("x"),
      });

    await expect(create(cron("not a cron"))).rejects.toBeInstanceOf(
      DbException,
    );
    await expect(create({ type: "single", at: "tomorrow" })).rejects.toThrow(
      /YYYY-MM-DDTHH:mm/,
    );
    await expect(
      create(cron("0 9 * * *", "Mars/Olympus")),
    ).rejects.toMatchObject({ error: { kind: "validation" } });
    expect(scheduler.rows.size).toBe(0);
  });

  it("offers eve exactly the keys of its provider contract", () => {
    const { provider } = setup();

    expect(Object.keys(provider).toSorted()).toEqual(
      [
        "kind",
        "create",
        "list",
        "get",
        "update",
        "enable",
        "disable",
        "invoke",
        "delete",
      ].toSorted(),
    );
  });

  it("fails reads on a scheduler that lists schedules without payloads", async () => {
    const scheduler = memoryScheduler();
    const listSchedules = scheduler.listSchedules!.bind(scheduler);

    const provider = queueScheduleProvider({
      scheduler: {
        ...scheduler,
        listSchedules: async (filter) =>
          (await listSchedules(filter)).map(
            ({ payload: _payload, ...schedule }) => schedule,
          ),
      },
    });

    await provider.create(context(), {
      name: "job",
      expression: cron("0 9 * * *"),
      payload: stored("x"),
    });

    await expect(provider.get(context(), "job")).rejects.toMatchObject({
      error: { kind: "unsupported", hint: "EVE_SCHEDULE_PAYLOAD_UNREADABLE" },
    });
  });
});

describe("eveScheduleRun", () => {
  it("rejects a payload that isn't a stored run", () => {
    expect(eveScheduleRun["~standard"].validate({ version: 2 })).toMatchObject({
      issues: [{ message: expect.stringContaining("version 1") }],
    });
  });
});

/**
 * A queue over the scheduler: `runSchedules` enqueues due runs, `drain` hands
 * them over once.
 */
function drainer(scheduler: ReturnType<typeof memoryScheduler>) {
  const waiting: { payload: EveScheduleRun; job: EveScheduleJob }[] = [];
  const failures: unknown[] = [];
  let id = 0;

  const queue = {
    runSchedules: () =>
      AsyncResult.from(async () => {
        const due = await scheduler.dueSchedules!(60, 100);

        for (const run of due) {
          id += 1;
          waiting.push({
            payload: run.payload as EveScheduleRun,
            job: {
              id,
              attempts: 1,
              maxAttempts: 5,
              enqueuedAt: run.nextRun,
              context: {},
            },
          });
          await scheduler.advanceSchedule!(
            run.name,
            run.nextRun,
            nextCronRun(run.cron, run.timeZone, temporal().Now.instant()),
          );
        }

        return ok(due.length);
      }),
    drain: vi.fn(
      async (input: {
        queue: string;
        handler: (payload: EveScheduleRun, job: EveScheduleJob) => unknown;
        budgetMs?: number;
      }) => {
        for (const { payload, job } of waiting.splice(0)) {
          try {
            await input.handler(payload, job);
          } catch (cause) {
            failures.push(cause);
          }
        }
      },
    ),
  };

  return { queue, waiting, failures };
}

function staticArgs() {
  const sent: {
    readonly channel: unknown;
    readonly target: unknown;
    readonly message: string;
    readonly options: EveSendOptions;
  }[] = [];

  const tasks: Promise<unknown>[] = [];

  const args: EveScheduleOptions = {
    appAuth: {
      authenticator: "app",
      principalType: "runtime",
      principalId: "eve:app",
      attributes: {},
    },
    to: (channel, target) => ({
      send: async (message, options) => {
        sent.push({ channel, target, message, options });

        return { sessionId: `sess_${String(sent.length)}`, deliveryId: "d" };
      },
    }),
    waitUntil: (task) => {
      tasks.push(task);
    },
  };

  return { args, sent, settle: () => Promise.all(tasks) };
}

const slack = { name: "slack" };

function definition(
  overrides: {
    auth?: (ctx: EveScheduleAuthContext) => unknown;
    run?: (args: EveDynamicRunArgs) => unknown;
    preparePayload?: unknown;
  } = {},
) {
  const events: EveScheduleOccurrenceEvent[] = [];

  const auth = vi.fn(
    overrides.auth ??
      ((ctx: EveScheduleAuthContext) =>
        ctx.principal.principalId === USER
          ? { attributes: { tenantId: ORG } }
          : null),
  );

  const run = vi.fn(
    overrides.run ??
      (async ({ payload, to }: EveDynamicRunArgs) => {
        const { task } = payload as { task: string };
        await to(slack as never, { channelId: "C1" } as never).send(
          `Do ${task}`,
        );
      }),
  );

  const collection: EveDynamicSchedules = {
    inputSchema: {
      "~standard": {
        validate: (value: unknown) =>
          typeof value === "object" &&
          value !== null &&
          typeof (value as { task?: unknown }).task === "string"
            ? { value }
            : { issues: [{ message: "task is required" }] },
      },
    },
    ...(overrides.preparePayload === undefined
      ? {}
      : { preparePayload: overrides.preparePayload }),
    auth,
    run,
    events: {
      "occurrence.dispatched": (event: EveScheduleOccurrenceEvent) => {
        events.push(event);
      },
      "occurrence.failed": (event: EveScheduleOccurrenceEvent) => {
        events.push(event);
      },
    },
  };

  return { collection, auth, run, events };
}

const creator: EveSessionAuth = {
  authenticator: "supabase",
  principalType: "user",
  principalId: USER,
  issuer: ISSUER,
  subject: USER,
  attributes: { tenantId: ORG },
};

async function tick(
  options: {
    readonly collection?: ReturnType<typeof definition>;
    readonly expression?: Parameters<
      ReturnType<typeof queueScheduleProvider>["create"]
    >[1]["expression"];
    readonly payload?: unknown;
    readonly now?: Temporal.Instant;
  } = {},
) {
  const scheduler = memoryScheduler();
  const provider = queueScheduleProvider({ scheduler });
  const ctx = context();
  const def = options.collection ?? definition();
  const { queue, waiting, failures } = drainer(scheduler);

  const created = await provider.create(ctx, {
    name: "job",
    expression: options.expression ?? cron("* * * * *"),
    payload: options.payload ?? stored("triage"),
  });

  const key = "eve:requests:eve-ns-user:job";

  const due = () => {
    scheduler.rows.get(key)!.nextRun = temporal()
      .Now.instant()
      .subtract({ minutes: 1 });
  };

  const fire = async () => {
    const { args, sent, settle } = staticArgs();

    queueDynamicSchedules({
      queue,
      provider,
      collections: { requests: def.collection },
      ...(options.now === undefined ? {} : { now: () => options.now! }),
    })(args);
    await settle();

    return sent;
  };

  return {
    scheduler,
    provider,
    ctx,
    def,
    created,
    key,
    due,
    fire,
    waiting,
    failures,
    queue,
  };
}

describe("queueDynamicSchedules", () => {
  it("fires a due schedule into its definition's run, as the creator", async () => {
    const t = await tick();

    t.due();
    const sent = await t.fire();

    expect(t.queue.drain).toHaveBeenCalledWith(
      expect.objectContaining({ queue: "eve_schedules", budgetMs: 50_000 }),
    );
    expect(t.def.auth).toHaveBeenCalledWith(
      expect.objectContaining({
        principal: {
          type: "user",
          authenticator: "supabase",
          issuer: ISSUER,
          principalId: USER,
          subject: USER,
        },
        payload: { task: "triage" },
      }),
    );
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      channel: slack,
      target: { channelId: "C1" },
      message: "Do triage",
      options: { auth: creator },
    });
    expect(sent[0]?.options.idempotencyKey).toMatch(/^eve-schedule:/);

    const [event] = t.def.events;

    expect(event).toMatchObject({
      type: "occurrence.dispatched",
      collection: "requests",
      name: "job",
      scheduleId: t.created.scheduleId,
      executionId: `${t.created.scheduleId}:1`,
      sessionIds: ["sess_1"],
      occurrence: { displayName: "job", collection: "requests" },
    });
    expect(t.failures).toEqual([]);

    // Nothing is due on the next minute's run.
    expect(await t.fire()).toEqual([]);
  });

  it("keeps a send's own key and context, and lets the run control its schedule", async () => {
    const t = await tick({
      collection: definition({
        run: async ({ to, schedule }) => {
          await to(slack as never, { channelId: "C2" } as never).send("hi", {
            idempotencyKey: "own",
            title: "Digest",
          });
          await schedule.disable();
        },
      }),
    });

    t.due();
    const sent = await t.fire();

    expect(sent[0]?.options).toEqual({
      auth: creator,
      idempotencyKey: "own",
      title: "Digest",
    });
    expect((await t.provider.get(t.ctx, "job"))?.state).toBe("inactive");

    t.due();
    expect(await t.fire()).toEqual([]);
  });

  it("deletes the schedule from the run's handle", async () => {
    const t = await tick({
      collection: definition({
        run: async ({ schedule }) => {
          await schedule.delete();
        },
      }),
    });

    t.due();
    await t.fire();

    expect(t.scheduler.rows.size).toBe(0);
  });

  it("skips runs of a schedule deleted or disabled after they were enqueued", async () => {
    const t = await tick();

    t.due();
    await t.queue.runSchedules().orThrow();
    await t.provider.disable(t.ctx, "job");

    expect(await t.fire()).toEqual([]);

    t.due();
    await t.queue.runSchedules().orThrow();
    await t.provider.delete(t.ctx, "job");

    expect(await t.fire()).toEqual([]);
    expect(t.def.run).not.toHaveBeenCalled();
  });

  it("completes a one-time schedule after its run, and skips a match before its year", async () => {
    const at = temporal().Now.instant().subtract({ minutes: 5 });
    const local = at.toZonedDateTimeISO("UTC");
    const pad = (value: number) => String(value).padStart(2, "0");

    const expression = {
      type: "single" as const,
      at: `${String(local.year)}-${pad(local.month)}-${pad(local.day)}T${pad(local.hour)}:${pad(local.minute)}`,
    };

    const early = await tick({
      expression,
      now: at.subtract({ hours: 24 * 365 }),
    });

    early.due();
    expect(await early.fire()).toEqual([]);
    expect((await early.provider.get(early.ctx, "job"))?.state).toBe("active");

    const t = await tick({ expression });

    t.due();
    expect(await t.fire()).toHaveLength(1);
    expect((await t.provider.get(t.ctx, "job"))?.state).toBe("completed");
    expect(t.def.events[0]?.scheduledAt).toBe(
      temporal()
        .PlainDateTime.from(expression.at)
        .toZonedDateTime("UTC")
        .toInstant()
        .toString(),
    );
  });

  it("fails the occurrence for good when auth returns null or the creator changes", async () => {
    for (const result of [
      null,
      { ...creator, principalId: "someone-else" },
      "yes",
    ]) {
      const t = await tick({ collection: definition({ auth: () => result }) });

      t.due();
      expect(await t.fire()).toEqual([]);
      expect(t.def.run).not.toHaveBeenCalled();
      expect(t.failures).toEqual([]);
      expect(t.def.events).toMatchObject([
        { type: "occurrence.failed", reason: expect.any(String) },
      ]);
    }
  });

  it("runs as a full context that names the creator", async () => {
    const t = await tick({ collection: definition({ auth: () => creator }) });

    t.due();
    expect((await t.fire())[0]?.options.auth).toEqual(creator);
  });

  it("fails an invalid payload for good, unless preparePayload shaped it", async () => {
    const invalidPayload = {
      ...stored("x"),
      envelope: { ...stored("x").envelope, payload: { other: 1 } },
    };

    const t = await tick({ payload: invalidPayload });

    t.due();
    await t.fire();
    expect(t.def.events).toMatchObject([
      {
        type: "occurrence.failed",
        reason: expect.stringContaining("task is required"),
      },
    ]);

    const prepared = await tick({
      payload: invalidPayload,
      collection: definition({
        preparePayload: (value: unknown) => value,
        run: () => undefined,
      }),
    });

    prepared.due();
    await prepared.fire();
    expect(prepared.def.events).toMatchObject([
      { type: "occurrence.dispatched" },
    ]);

    const broken = await tick({ payload: { not: "eve" } });

    broken.due();
    await broken.fire();
    expect(broken.def.events).toMatchObject([
      {
        type: "occurrence.failed",
        reason: expect.stringContaining("recreate"),
      },
    ]);
  });

  it("retries a thrown error and reports it once the attempts run out", async () => {
    const t = await tick({
      collection: definition({
        auth: () => {
          throw new Error("directory down");
        },
      }),
    });

    t.due();
    await t.fire();
    expect(t.failures).toMatchObject([{ message: "directory down" }]);
    expect(t.def.events).toEqual([]);

    const handler = vi.mocked(t.queue.drain).mock.calls[0]![0].handler;
    const run = t.scheduler.rows.get(t.key)!.payload as EveScheduleRun;

    await expect(
      handler(run, {
        id: 9,
        attempts: 5,
        maxAttempts: 5,
        enqueuedAt: NOW,
        context: {},
        schedule: { executionId: "vercel-exec", scheduledAt: NOW },
      }),
    ).rejects.toThrow("directory down");
    expect(t.def.events).toMatchObject([
      {
        type: "occurrence.failed",
        executionId: "vercel-exec",
        scheduledAt: NOW.toString(),
        reason: "directory down",
      },
    ]);
  });

  it("refuses a provider queueScheduleProvider didn't build", () => {
    const { queue } = drainer(memoryScheduler());
    const { provider } = setup();

    expect(() =>
      queueDynamicSchedules({
        queue,
        provider: { ...provider },
        collections: {},
      }),
    ).toThrow(TypeError);
  });

  it("fails a run whose collection isn't listed", async () => {
    const scheduler = memoryScheduler();
    const provider = queueScheduleProvider({ scheduler });
    const { queue, failures } = drainer(scheduler);

    await provider.create(context({ collection: "unknown" }), {
      name: "job",
      expression: cron("* * * * *"),
      payload: stored("x"),
    });

    for (const row of scheduler.rows.values()) {
      row.nextRun = temporal().Now.instant().subtract({ minutes: 1 });
    }

    const { args, settle } = staticArgs();

    queueDynamicSchedules({ queue, provider, collections: {} })(args);
    await settle();

    expect(failures).toMatchObject([
      { message: expect.stringContaining('"unknown"') },
    ]);
  });
});
