import { describe, expect, it, vi } from "vitest";

import type { AiTaskOutcome } from "../../../src/blocks/ai-tasks/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createAiTasks } from "../../../src/blocks/ai-tasks/index.ts";
import { DbException } from "../../../src/core/errors.ts";

const AT = "2026-01-01T00:00:00Z";
const NOW = Temporal.Instant.from("2026-01-01T10:15:00Z");

const taskRow = (overrides: Record<string, unknown> = {}) => ({
  id: "t1",
  organization_id: "o1",
  user_id: "u1",
  chat_id: null,
  agent_id: "a1",
  title: "Digest",
  prompt: "Summarize",
  cron: "0 9 * * *",
  timezone: "UTC",
  enabled: true,
  next_run_at: AT,
  last_run_at: null,
  created_at: AT,
  updated_at: AT,
  ...overrides,
});

const runRow = (overrides: Record<string, unknown> = {}) => ({
  id: "r1",
  task_id: "t1",
  organization_id: "o1",
  user_id: "u1",
  status: "queued",
  scheduled_for: AT,
  chat_id: null,
  error: null,
  started_at: null,
  finished_at: null,
  created_at: AT,
  ...overrides,
});

type Handler = (args: Record<string, unknown>) => unknown;

function fakeTransport(handlers: Record<string, Handler>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];
      if (!handler) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(handler(args));
    },
  };
  return { transport, calls };
}

describe("createAiTasks", () => {
  it("computes the next run when the schedule changes", async () => {
    const { transport, calls } = fakeTransport({
      save_ai_task: () => taskRow(),
    });
    const tasks = createAiTasks({ transport, now: () => NOW });
    await tasks.create("o1", {
      title: "Digest",
      prompt: "Summarize",
      cron: "0 9 * * *",
      timezone: "Europe/Amsterdam",
      chatId: null,
      agentId: "a1",
    });
    expect(calls[0]?.args).toEqual({
      tenant: "o1",
      id: undefined,
      fields: {
        title: "Digest",
        prompt: "Summarize",
        cron: "0 9 * * *",
        timezone: "Europe/Amsterdam",
        chat_id: null,
        agent_id: "a1",
      },
      next_run_at: "2026-01-02T08:00:00Z",
    });
    await tasks.update("o1", "t1", { title: "New" });
    expect(calls[1]?.args["next_run_at"]).toBeUndefined();
    await tasks.update("o1", "t1", { cron: "30 minutes" });
    expect(calls[2]?.args["next_run_at"]).toBe("2026-01-01T10:45:00Z");
    await tasks.pause("o1", "t1");
    await tasks.resume("o1", "t1");
    expect(calls.slice(3).map(({ args }) => args["fields"])).toEqual([
      { enabled: false },
      { enabled: true },
    ]);
  });

  it("rejects bad schedules before calling the database", async () => {
    const { transport, calls } = fakeTransport({});
    const tasks = createAiTasks({ transport, now: () => NOW });
    const bad = await tasks.create("o1", {
      title: "x",
      prompt: "y",
      cron: "every tuesday",
    });
    expect(bad.ok ? undefined : bad.error.hint).toBe("AI_TASK_INVALID");
    const zoneOnly = await tasks.update("o1", "t1", { timezone: "UTC" });
    expect(zoneOnly.ok ? undefined : zoneOnly.error.message).toContain(
      "together",
    );
    expect(calls).toEqual([]);
  });

  it("lists tasks and runs", async () => {
    const { transport, calls } = fakeTransport({
      list_ai_tasks: () => [
        taskRow({
          last_run: runRow({ status: "succeeded", chat_id: "c1" }),
          enabled: false,
          created_at: new Date(AT),
        }),
      ],
      list_ai_task_runs: () => [runRow({ status: "bogus", error: "boom" })],
      delete_ai_task: () => true,
    });
    const tasks = createAiTasks({ transport });
    const [task] = await tasks.list("o1", { all: true }).orThrow();
    expect(task?.lastRun).toMatchObject({ chatId: "c1", status: "completed" });
    expect(task?.enabled).toBe(false);
    const [run] = await tasks.runs("t1", { limit: 2 }).orThrow();
    expect(run).toMatchObject({ status: "failed", error: "boom" });
    expect(await tasks.remove("t1").orThrow()).toBe(true);
    await tasks.list("o1");
    expect(calls.map(({ args }) => args)).toEqual([
      { tenant: "o1", mine: false },
      { task_id: "t1", max_rows: 2 },
      { id: "t1" },
      { tenant: "o1", mine: true },
    ]);
  });

  it("ticks, schedules and drains runs", async () => {
    const outcomes: AiTaskOutcome[] = [];
    const service = fakeTransport({
      claim_due_ai_tasks: () => ({
        runs: [runRow(), runRow({ id: "r2" }), runRow({ id: "r3" })],
        unscheduled: [
          { id: "t1", cron: "0 9 * * *", timezone: "UTC" },
          { id: "t2", cron: "nope", timezone: "UTC" },
        ],
      }),
      schedule_ai_tasks: () => 2,
      start_ai_task_run: (args) =>
        args["id"] === "r3"
          ? null
          : {
              ...runRow({ id: args["id"], status: "running" }),
              task: taskRow(),
            },
      finish_ai_task_run: () => true,
    });
    const run = vi
      .fn()
      .mockResolvedValueOnce({ chatId: "c1" })
      .mockRejectedValueOnce(new Error("model down"));
    const tasks = createAiTasks({
      transport: fakeTransport({}).transport,
      service: service.transport,
      run,
      notify: (outcome) => outcomes.push(outcome),
      now: () => NOW,
    });
    expect(await tasks.drain({ batch: 5 }).orThrow()).toBe(2);
    expect(
      service.calls.find(({ fn }) => fn === "schedule_ai_tasks")?.args,
    ).toEqual({
      items: {
        items: [
          { id: "t1", next_run_at: "2026-01-02T09:00:00Z" },
          { id: "t2", next_run_at: "2026-01-02T10:15:00Z" },
        ],
      },
    });
    expect(
      service.calls
        .filter(({ fn }) => fn === "finish_ai_task_run")
        .map(({ args }) => args),
    ).toEqual([
      { id: "r1", succeeded: true, error: undefined, chat_id: "c1" },
      { id: "r2", succeeded: false, error: "model down", chat_id: undefined },
    ]);
    expect(outcomes.map((outcome) => outcome.ok)).toEqual([true, false]);
  });

  it("skips scheduling when nothing needs it and stops on abort", async () => {
    const service = fakeTransport({
      claim_due_ai_tasks: () => ({ runs: [runRow()], unscheduled: [] }),
    });
    const tasks = createAiTasks({ transport: service.transport });
    const controller = new AbortController();
    controller.abort();
    expect(await tasks.drain({ signal: controller.signal }).orThrow()).toBe(0);
    expect(service.calls.map(({ fn }) => fn)).toEqual(["claim_due_ai_tasks"]);
  });

  it("fails a run without a runner, and the job throws on errors", async () => {
    const service = fakeTransport({
      start_ai_task_run: (args) =>
        args["id"] === "bad"
          ? Promise.reject(new Error("db down"))
          : { ...runRow(), task: taskRow() },
      finish_ai_task_run: () => true,
    });
    const tasks = createAiTasks({ transport: service.transport });
    const job = tasks.runJob();
    await job({ run_id: "r1" }, {} as never, new AbortController().signal);
    expect(service.calls.at(-1)?.args).toMatchObject({
      succeeded: false,
      error: "createAiTasks has no run",
    });
    await expect(
      job({ run_id: "bad" }, {} as never, new AbortController().signal),
    ).rejects.toBeInstanceOf(DbException);
  });

  it("drains every run when one fails and reports each failure", async () => {
    const service = fakeTransport({
      claim_due_ai_tasks: () => ({
        runs: [runRow(), runRow({ id: "r2" }), runRow({ id: "r3" })],
        unscheduled: [],
      }),
      start_ai_task_run: (args) =>
        args["id"] === "r1"
          ? Promise.reject(new Error("db down"))
          : { ...runRow({ id: args["id"] }), task: taskRow() },
      finish_ai_task_run: () => true,
    });
    const result = await createAiTasks({
      transport: service.transport,
      run: () => Promise.resolve(),
    }).drain();
    expect(
      service.calls
        .filter(({ fn }) => fn === "finish_ai_task_run")
        .map(({ args }) => args["id"]),
    ).toEqual(["r2", "r3"]);
    expect(result.ok ? undefined : result.error.details).toBe(
      "1 of 3 runs failed: r1 (db down)",
    );
  });

  it("schedules a saved task right away with a service transport", async () => {
    const user = fakeTransport({
      save_ai_task: () => taskRow({ next_run_at: null }),
    });
    const service = fakeTransport({ schedule_ai_tasks: () => 1 });
    const tasks = createAiTasks({
      transport: user.transport,
      service: service.transport,
      now: () => NOW,
    });
    const task = await tasks.resume("o1", "t1").orThrow();
    expect(task.nextRunAt?.toString()).toBe("2026-01-02T09:00:00Z");
    expect(service.calls[0]?.args).toEqual({
      items: { items: [{ id: "t1", next_run_at: "2026-01-02T09:00:00Z" }] },
    });
    const paused = fakeTransport({
      save_ai_task: () => taskRow({ next_run_at: null, enabled: false }),
    });
    await createAiTasks({
      transport: paused.transport,
      service: service.transport,
    }).pause("o1", "t1");
    expect(service.calls).toHaveLength(1);
  });

  it("returns the finish error", async () => {
    const service = fakeTransport({
      start_ai_task_run: () => ({ ...runRow(), task: taskRow() }),
      finish_ai_task_run: () => Promise.reject(new Error("db down")),
    });
    const result = await createAiTasks({
      transport: service.transport,
      run: () => Promise.resolve(),
    }).execute("r1");
    expect(result.ok).toBe(false);
  });
});
