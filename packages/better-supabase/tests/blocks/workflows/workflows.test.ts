import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createWorkflows,
  workflowRunOf,
} from "../../../src/blocks/workflows/workflows.ts";

const RUN = {
  id: "r1",
  engine: "workflow-sdk",
  externalId: "wrun_1",
  definition: "onboard",
  tenant: "t1",
  actor: "u1",
  status: "running",
  attributes: { plan: "pro" },
  error: null,
  createdAt: "2026-01-01T00:00:00Z",
  updatedAt: "2026-01-01T00:00:01Z",
  startedAt: "2026-01-01T00:00:00Z",
  completedAt: null,
  cancelRequestedAt: null,
};

const SCHEDULE = {
  id: "s1",
  tenant: "t1",
  name: "digest",
  workflow: "digest",
  input: ["weekly"],
  cron: "0 9 * * 1",
  timezone: "Europe/Amsterdam",
  nextRunAt: "2026-01-05T08:00:00Z",
  lastRunAt: null,
  paused: false,
  createdBy: "u1",
  createdAt: "2026-01-01T00:00:00Z",
};

type Reply = (args: Readonly<Record<string, unknown>>) => unknown;

function fake(replies: Record<string, Reply>) {
  const calls: { fn: string; args: Readonly<Record<string, unknown>> }[] = [];
  const transport: BlockTransport = {
    call: vi.fn(async (_schema, fn, args) => {
      calls.push({ fn, args });
      const reply = replies[fn];
      if (reply === undefined) throw new Error(`unexpected ${fn}`);
      return reply(args);
    }),
  };
  return { transport, calls };
}

describe("workflowRunOf", () => {
  it("reads a run, maps unknown statuses to running and rejects missing times", () => {
    const run = workflowRunOf(RUN);
    expect(run).toMatchObject({
      externalId: "wrun_1",
      status: "running",
      attributes: { plan: "pro" },
      error: undefined,
      completedAt: undefined,
    });
    expect(run.createdAt.toString()).toBe("2026-01-01T00:00:00Z");
    expect(workflowRunOf({ ...RUN, attributes: null }).attributes).toEqual({});
    for (const status of ["paused", "", null, 3])
      expect(workflowRunOf({ ...RUN, status }).status).toBe("running");
    expect(workflowRunOf({ ...RUN, status: "cancelled" }).status).toBe(
      "cancelled",
    );
    expect(() => workflowRunOf({ ...RUN, createdAt: null })).toThrow(
      "createdAt is missing",
    );
  });
});

describe("createWorkflows", () => {
  it("lists, reads, cancels, records and purges runs", async () => {
    const { transport, calls } = fake({
      workflow_runs_list: () => [RUN],
      workflow_run_get: (args) => (args["run"] === "r1" ? RUN : null),
      request_workflow_cancel: () => ({
        ...RUN,
        cancelRequestedAt: "2026-01-01T00:01:00Z",
      }),
      record_workflow_run: () => "r1",
      purge_workflow_runs: () => "3",
    });
    const workflows = createWorkflows({ transport, schema: "app" });

    const before = Temporal.Instant.from("2026-02-01T00:00:00Z");
    const runs = await workflows.runs
      .list({ tenant: "t1", status: "running", limit: 10, before })
      .orThrow();
    expect(runs.map((run) => run.id)).toEqual(["r1"]);
    expect(calls[0]?.args).toMatchObject({
      tenant: "t1",
      status: "running",
      max: 10,
      before: "2026-02-01T00:00:00Z",
    });
    expect((await workflows.runs.get("r1").orThrow())?.id).toBe("r1");
    expect(await workflows.runs.get("nope").orThrow()).toBeUndefined();
    expect(
      (await workflows.runs.requestCancel("r1").orThrow())?.cancelRequestedAt,
    ).toBeDefined();
    expect(
      await workflows.runs
        .record({
          engine: "workflow-sdk",
          externalId: "wrun_1",
          definition: "onboard",
          status: "completed",
          completedAt: before,
        })
        .orThrow(),
    ).toBe("r1");
    expect(calls.at(-1)?.args).toMatchObject({
      external_id: "wrun_1",
      completed_at: "2026-02-01T00:00:00Z",
    });
    expect(
      await workflows.runs.purge({ olderThan: 60, batch: 5 }).orThrow(),
    ).toBe(3);
    expect(calls.at(-1)?.args).toMatchObject({
      older_than: "60 seconds",
      batch: 5,
    });
    await workflows.runs.purge().orThrow();
    expect(calls.at(-1)?.args["older_than"]).toBeUndefined();
  });

  it("creates, lists, pauses and removes schedules", async () => {
    const { transport, calls } = fake({
      create_workflow_schedule: () => SCHEDULE,
      workflow_schedules_list: () => [SCHEDULE],
      pause_workflow_schedule: () => true,
      remove_workflow_schedule: () => false,
    });
    const workflows = createWorkflows({ transport });
    const schedule = await workflows.schedules
      .create({
        name: "digest",
        workflow: "digest",
        cron: "0 9 * * 1",
        timezone: "Europe/Amsterdam",
        input: ["weekly"],
        tenant: "t1",
      })
      .orThrow();
    expect(schedule).toMatchObject({ id: "s1", input: ["weekly"] });
    expect(calls[0]?.args).toMatchObject({
      payload: { input: ["weekly"] },
      timezone: "Europe/Amsterdam",
    });
    await workflows.schedules
      .create({ name: "n", workflow: "w", cron: "@daily" })
      .orThrow();
    expect(calls[1]?.args).toMatchObject({
      payload: { input: [] },
      timezone: "UTC",
    });
    expect(() =>
      workflows.schedules.create({ name: "n", workflow: "w", cron: "bad" }),
    ).toThrow('Invalid cron "bad"');
    expect(await workflows.schedules.list("t1").orThrow()).toHaveLength(1);
    expect(await workflows.schedules.pause("s1").orThrow()).toBe(true);
    expect(calls.at(-1)?.args).toEqual({ schedule: "s1", paused: true });
    expect(await workflows.schedules.remove("s1").orThrow()).toBe(false);
  });

  it("ticks due schedules with an idempotency key and keeps failures", async () => {
    const fireAt = "2026-01-05T08:00:00Z";
    const { transport, calls } = fake({
      claim_due_workflow_schedules: () => [
        { ...SCHEDULE, fireAt },
        { ...SCHEDULE, id: "s2", fireAt },
      ],
      advance_workflow_schedule: () => true,
    });
    const workflows = createWorkflows({ transport });
    const start = vi.fn(async (call: { idempotencyKey: string }) => {
      if (call.idempotencyKey.startsWith("schedule:s2:"))
        throw new Error("down");
      return "wrun_9";
    });
    const result = await workflows.schedules
      .tick({ start, lease: 30, batch: 2 })
      .orThrow();
    expect(result).toEqual({
      started: 1,
      failed: [{ id: "s2", error: "down" }],
    });
    expect(start.mock.calls[0]?.[0]).toEqual({
      workflow: "digest",
      input: ["weekly"],
      tenant: "t1",
      actor: "u1",
      idempotencyKey: `schedule:s1:${fireAt}`,
    });
    expect(calls[0]?.args).toEqual({ lease: 30, batch: 2 });
    const advance = calls.find(
      (entry) => entry.fn === "advance_workflow_schedule",
    );
    expect(advance?.args).toMatchObject({ schedule: "s1", fired: fireAt });
  });

  it("stops a tick when settling a start fails", async () => {
    const { transport } = fake({
      claim_workflow_start_requests: () => [
        { id: "q1", workflow: "w", input: [1], tenant: null, actor: "u1" },
      ],
      mark_workflow_start_request: () => {
        throw Object.assign(new Error("gone"), { code: "P0001" });
      },
    });
    const workflows = createWorkflows({ transport });
    const result = await workflows.admission.tick({
      start: async () => "wrun_1",
    });
    expect(result.ok).toBe(false);
  });

  it("takes and releases semaphores and admits starts", async () => {
    const { transport, calls } = fake({
      acquire_workflow_semaphore: () => true,
      release_workflow_semaphore: () => true,
      request_workflow_start: (args) =>
        args["singleton"] === true
          ? { id: null, status: "dropped" }
          : { id: "q1", status: "pending" },
      claim_workflow_start_requests: () => [
        { id: "q1", workflow: "w", input: [1], tenant: "t1", actor: null },
      ],
      mark_workflow_start_request: () => true,
    });
    const workflows = createWorkflows({ transport });
    expect(
      await workflows.semaphores.acquire("k", "h", { max: 2 }).orThrow(),
    ).toBe(true);
    expect(calls[0]?.args).toEqual({
      key: "k",
      holder: "h",
      max: 2,
      ttl: "300 seconds",
    });
    expect(await workflows.semaphores.release("k", "h").orThrow()).toBe(true);
    expect(
      await workflows.admission
        .request({ key: "k", workflow: "w", debounce: 5 })
        .orThrow(),
    ).toEqual({ id: "q1", status: "pending" });
    expect(calls.at(-1)?.args).toMatchObject({
      payload: { input: [] },
      debounce: "5 seconds",
    });
    expect(
      await workflows.admission
        .request({ key: "k", workflow: "w", singleton: true, input: [1] })
        .orThrow(),
    ).toEqual({ id: undefined, status: "dropped" });
    const start = vi.fn(async () => "wrun_2");
    expect(await workflows.admission.tick({ start }).orThrow()).toEqual({
      started: 1,
      failed: [],
    });
    expect(start).toHaveBeenCalledWith({
      workflow: "w",
      input: [1],
      tenant: "t1",
      actor: undefined,
      idempotencyKey: "admission:q1",
    });
  });
});
