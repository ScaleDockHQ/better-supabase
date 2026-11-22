import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createTasks } from "../../../src/blocks/tasks/index.ts";
import { DbException, dbError } from "../../../src/core/errors.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const ROW = {
  id: "w1",
  tenant_id: "o",
  number: 1,
  identifier: "TASK-1",
  title: "Plan",
  state: "started",
  locked: false,
  rank: "V",
  created_at: "2026-10-14T09:00:00Z",
  updated_at: "2026-10-14T09:00:00Z",
  assignees: [],
};

const CLAIM = {
  holderId: "u1",
  epoch: 3,
  claimedAt: "2026-10-14T09:00:00Z",
  expiresAt: "2026-10-14T09:05:00Z",
};

describe("task coordination", () => {
  it("claims with a profile and reads the live claim on the task", async () => {
    const t = transport({
      claim_task: () => ({
        task: { ...ROW, claim: { ...CLAIM, profile: { kind: "agent" } } },
        claim: {
          ...CLAIM,
          token: "tok",
          profile: { kind: "agent", name: "Ada" },
        },
      }),
    });

    const claimed = await createTasks({ transport: t })
      .claim({ taskId: "w1", profile: { kind: "agent", name: "Ada" } })
      .orThrow();

    expect(t.calls[0]).toEqual([
      "claim_task",
      { task: "w1", lease: null, profile: { kind: "agent", name: "Ada" } },
    ]);
    expect(claimed.claim).toMatchObject({
      holderId: "u1",
      epoch: 3,
      token: "tok",
      profile: { kind: "agent", name: "Ada" },
    });
    expect(claimed.claim.expiresAt.toString()).toBe("2026-10-14T09:05:00Z");
    expect(claimed.task.claim?.profile).toEqual({ kind: "agent" });
  });

  it("drops an empty or missing profile", async () => {
    const t = transport({
      renew_task_claim: (args) => ({
        ...CLAIM,
        profile: args["lease"] === 60 ? { kind: null } : "agent",
      }),
    });

    const tasks = createTasks({ transport: t });

    const renewed = await tasks
      .renew({ taskId: "w1", token: "tok", lease: 60 })
      .orThrow();

    const plain = await tasks.renew({ taskId: "w1", token: "tok" }).orThrow();

    expect(renewed.profile).toBeUndefined();
    expect(plain.profile).toBeUndefined();
    expect(t.calls.map((each) => each[1]["lease"])).toEqual([60, null]);
  });

  it("claims the next ready task, or nothing when none is ready", async () => {
    let ready = true;

    const t = transport({
      claim_next_task: () => {
        if (ready) {
          return { task: ROW, claim: { ...CLAIM, token: "tok" } };
        }

        throw new DbException(
          dbError("conflict", "nothing ready", { hint: "TASK_NOTHING_READY" }),
        );
      },
    });

    const tasks = createTasks({ transport: t });

    const next = await tasks
      .claimNext({ organizationId: "o", filter: { teamId: "t1" }, lease: 30 })
      .orThrow();

    expect(next?.task.id).toBe("w1");
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      filter: { teamId: "t1" },
      lease: 30,
      profile: null,
    });

    ready = false;

    expect(
      await tasks.claimNext({ organizationId: "o" }).orThrow(),
    ).toBeUndefined();
    expect(t.calls[1]?.[1]).toMatchObject({ filter: null, lease: null });
  });

  it("passes any other claimNext error through", async () => {
    const t = transport({
      claim_next_task: () => {
        throw new DbException(
          dbError("forbidden", "no", { hint: "TASK_FORBIDDEN" }),
        );
      },
    });

    const result = await createTasks({ transport: t }).claimNext({
      organizationId: "o",
    });

    expect(!result.ok && result.error.hint).toBe("TASK_FORBIDDEN");
  });

  it("creates a plan with assignees and returns tasks with their keys", async () => {
    const t = transport({
      create_tasks: () => ({
        tasks: [ROW, { ...ROW, id: "w2" }],
        keys: { spec: "w1", build: "w2" },
      }),
    });

    const plan = await createTasks({ transport: t })
      .createPlan({
        organizationId: "o",
        plan: [
          { key: "spec", title: "Spec", assigneeIds: ["u1"] },
          { key: "build", title: "Build", needs: [{ key: "spec" }] },
        ],
      })
      .orThrow();

    expect(plan.tasks.map((task) => task.id)).toEqual(["w1", "w2"]);
    expect(plan.keys).toEqual({ spec: "w1", build: "w2" });
    expect(t.calls[0]?.[1]).toMatchObject({
      tenant: "o",
      items: [
        { key: "spec", title: "Spec", assignees: ["u1"] },
        { key: "build", title: "Build", needs: [{ key: "spec" }] },
      ],
    });
  });

  it("reads a plan without keys", async () => {
    const t = transport({ create_tasks: () => ({ tasks: [ROW] }) });

    const plan = await createTasks({ transport: t })
      .createPlan({ organizationId: "o", plan: [{ title: "Spec" }] })
      .orThrow();

    expect(plan.keys).toEqual({});
  });

  it("returns the error when the plan is refused", async () => {
    const t = transport({
      create_tasks: () => {
        throw new DbException(
          dbError("invalid_input", "too large", {
            hint: "TASK_PLAN_TOO_LARGE",
          }),
        );
      },
    });

    const result = await createTasks({ transport: t }).createPlan({
      organizationId: "o",
      plan: [{ title: "Spec" }],
    });

    expect(!result.ok && result.error.hint).toBe("TASK_PLAN_TOO_LARGE");
  });

  it("checks plan fields before the first write", async () => {
    const t = transport({});

    const result = await createTasks({
      transport: t,
      fields: v.object({ size: v.optional(v.number()) }),
    }).createPlan({
      organizationId: "o",
      // SAFETY: a value the schema refuses, to prove the plan is checked.
      plan: [
        {
          title: "Spec",
          fields: { size: "big" } as unknown as { size: number },
        },
      ],
    });

    expect(result.ok).toBe(false);
    expect(t.calls).toEqual([]);
  });

  it("refuses an idempotency key without the idempotency option", async () => {
    const t = transport({});

    const result = await createTasks({ transport: t }).createPlan({
      organizationId: "o",
      plan: [{ title: "Spec" }],
      idempotencyKey: "k1",
    });

    expect(!result.ok && result.error.hint).toBe("IDEMPOTENCY_NOT_CONFIGURED");
    expect(t.calls).toEqual([]);
  });

  it("sends needs, release, delegate, hold, release hold and fail", async () => {
    const t = transport({
      set_task_needs: () => ROW,
      release_task_claim: () => null,
      delegate_task: () => ROW,
      hold_task: () => ROW,
      release_task_hold: () => ROW,
      close_task: () => null,
    });

    const tasks = createTasks({ transport: t });

    await tasks.setNeeds({ taskId: "w1", needs: ["w0"] }).orThrow();
    expect(await tasks.release({ taskId: "w1", token: "tok" }).orThrow()).toBe(
      true,
    );
    await tasks
      .release({ taskId: "w1", token: "tok", note: "done for now" })
      .orThrow();
    await tasks.delegate({ taskId: "w1", toUserId: "u2" }).orThrow();
    await tasks.hold({ taskId: "w1", kind: "question" }).orThrow();
    await tasks
      .hold({ taskId: "w1", kind: "question", note: "?", askUserIds: ["u3"] })
      .orThrow();
    await tasks.releaseHold({ taskId: "w1" }).orThrow();
    expect(await tasks.fail({ taskId: "w1" }).orThrow()).toBe(true);
    await tasks.fail({ taskId: "w1", stageId: "s9", note: "broken" }).orThrow();

    expect(t.calls).toEqual([
      ["set_task_needs", { task: "w1", ids: ["w0"] }],
      ["release_task_claim", { task: "w1", token: "tok", note: null }],
      [
        "release_task_claim",
        { task: "w1", token: "tok", note: "done for now" },
      ],
      ["delegate_task", { task: "w1", to_user: "u2", profile: null }],
      [
        "hold_task",
        { task: "w1", kind: "question", note: null, ask_user_ids: null },
      ],
      [
        "hold_task",
        { task: "w1", kind: "question", note: "?", ask_user_ids: ["u3"] },
      ],
      ["release_task_hold", { task: "w1" }],
      [
        "close_task",
        { task: "w1", outcome: "failed", note: null, stage: null },
      ],
      [
        "close_task",
        { task: "w1", outcome: "failed", note: "broken", stage: "s9" },
      ],
    ]);
  });

  it("moves many tasks and lists the refused ones", async () => {
    const t = transport({
      move_tasks: () => ({
        accepted: [{ taskId: "w1" }],
        rejected: [
          { taskId: "w2", hint: "TASK_LOCKED", reason: "locked" },
          { taskId: "w3", reason: "gone" },
        ],
      }),
    });

    const moved = await createTasks({ transport: t })
      .moveMany({
        moves: [
          { taskId: "w1", stageId: "s2", afterId: "w0" },
          { taskId: "w2", beforeId: "w1" },
        ],
      })
      .orThrow();

    expect(moved).toEqual({
      accepted: [{ taskId: "w1" }],
      rejected: [
        { taskId: "w2", hint: "TASK_LOCKED", reason: "locked" },
        { taskId: "w3", reason: "gone" },
      ],
    });
    expect(t.calls[0]?.[1]).toEqual({
      moves: [
        { taskId: "w1", stageId: "s2", afterId: "w0" },
        { taskId: "w2", beforeId: "w1" },
      ],
    });
  });

  it("reads stage times with an open and a closed stage", async () => {
    const t = transport({
      task_stage_times: () => [
        {
          stageId: "s1",
          stageName: "Todo",
          category: "unstarted",
          enteredAt: "2026-10-14T09:00:00Z",
          exitedAt: "2026-10-14T10:00:00Z",
          seconds: 3600,
        },
        { stageId: "s2", enteredAt: "2026-10-14T10:00:00Z", seconds: "12" },
      ],
    });

    const times = await createTasks({ transport: t })
      .stageTimes("w1")
      .orThrow();

    expect(times[0]).toMatchObject({
      stageId: "s1",
      stageName: "Todo",
      category: "unstarted",
      seconds: 3600,
    });
    expect(times[0]?.exitedAt?.toString()).toBe("2026-10-14T10:00:00Z");
    expect(times[1]).toEqual({
      stageId: "s2",
      enteredAt: Temporal.Instant.from("2026-10-14T10:00:00Z"),
      seconds: 12,
    });
  });
});

describe("task closing, cloning and moving", () => {
  it("closes with a note through close_task, clones and moves between neighbours", async () => {
    const t = transport({
      close_task: () => null,
      clone_task: () => ({ ...ROW, id: "w2" }),
      move_task: () => null,
    });

    const tasks = createTasks({ transport: t });

    expect(
      await tasks.complete({ taskId: "w1", note: "shipped" }).orThrow(),
    ).toBe(true);
    await tasks
      .cancel({ taskId: "w1", stageId: "s9", note: "dropped" })
      .orThrow();

    const copy = await tasks
      .clone({ sourceId: "w1", overrides: { title: "Copy" } })
      .orThrow();

    await tasks.clone({ sourceId: "w1" }).orThrow();
    expect(
      await tasks
        .move({ taskId: "w1", stageId: "s2", beforeId: "w3" })
        .orThrow(),
    ).toBe(true);
    await tasks.move({ taskId: "w1", stageId: "s2", afterId: "w4" }).orThrow();

    expect(copy.id).toBe("w2");
    expect(t.calls).toEqual([
      [
        "close_task",
        { task: "w1", outcome: "completed", note: "shipped", stage: null },
      ],
      [
        "close_task",
        { task: "w1", outcome: "canceled", note: "dropped", stage: "s9" },
      ],
      ["clone_task", { source: "w1", overrides: { title: "Copy" } }],
      ["clone_task", { source: "w1", overrides: null }],
      ["move_task", { task: "w1", stage: "s2", before: "w3", after: null }],
      ["move_task", { task: "w1", stage: "s2", before: null, after: "w4" }],
    ]);
  });

  it("refuses to assign a task that is not found", async () => {
    const t = transport({ get_task: () => null });

    const result = await createTasks({ transport: t }).assignToMe({
      taskId: "w9",
      userId: "u1",
    });

    expect(!result.ok && result.error.kind).toBe("not_found");
  });
});
