import { describe, expect, it, vi } from "vitest";

import type {
  AiHarnessSession,
  BlockTransport,
} from "../../../src/blocks/ai-chat/index.ts";
import type { Job } from "../../../src/blocks/jobs/queue.ts";

import {
  createAiRuns,
  createHarnessSessions,
  idleSandboxStop,
} from "../../../src/blocks/ai-chat/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { err, ok } from "../../../src/core/result.ts";

const AT = "2026-01-01T00:00:00Z";

const runRow = {
  id: "r1",
  chat_id: "c1",
  owner_id: "u1",
  assistant_message_id: "m2",
  stream_id: "s1",
  engine: "workflow",
  external_run_id: "wrun_1",
  model: "openai/gpt-5",
  status: "running",
  usage: { inputTokens: 3 },
  cost_micro_usd: "120",
  error: null,
  started_at: AT,
  ended_at: null,
};

const stepRow = {
  id: "st1",
  run_id: "r1",
  chat_id: "c1",
  step_key: "search",
  label: "Search the web",
  status: "done",
  detail: { sources: 4 },
  started_at: AT,
  ended_at: AT,
};

const approvalRow = {
  approval_id: "approval-t1",
  chat_id: "c1",
  run_id: "r1",
  message_id: "m2",
  tool: "sendEmail",
  tool_call_id: "t1",
  input: { to: "a@b.c" },
  decision: null,
  reason: null,
  signature: null,
  decided_by: null,
  decided_at: null,
  created_at: AT,
  chat_title: "Launch",
};

const sessionRow = {
  chat_id: "c1",
  harness_id: "claude-code",
  owner_id: "u1",
  resume_state: { session: "abc" },
  continue_state: null,
  sandbox_id: "sbx_1",
  status: "active",
  lock_holder: null,
  locked_until: null,
  last_active_at: AT,
  created_at: AT,
  updated_at: AT,
};

const ANSWERS: Record<string, unknown> = {
  get_ai_run: runRow,
  list_ai_runs: [
    runRow,
    { ...runRow, id: "r2", status: "weird", cost_micro_usd: null },
  ],
  attach_ai_run: true,
  record_ai_run_step: stepRow,
  list_ai_run_steps: [stepRow],
  list_pending_ai_tool_approvals: [approvalRow],
  load_ai_harness_session: sessionRow,
  save_ai_harness_session: sessionRow,
  lock_ai_harness_session: true,
  unlock_ai_harness_session: false,
  idle_ai_harness_sessions: [sessionRow],
};

function fake(answers: Record<string, unknown> = ANSWERS) {
  const user = vi.fn(
    async (_schema: string, fn: string, _args: Record<string, unknown>) =>
      answers[fn],
  );
  const server = vi.fn(
    async (_schema: string, fn: string, _args: Record<string, unknown>) =>
      answers[fn],
  );
  const transport: BlockTransport = { call: user };
  const service: BlockTransport = { call: server };
  return {
    user,
    server,
    runs: createAiRuns({ transport, service }),
    sessions: createHarnessSessions({ transport, service }),
  };
}

const lastArgs = (mock: ReturnType<typeof vi.fn>): unknown =>
  mock.mock.calls.at(-1)?.[2];

describe("createAiRuns", () => {
  it("reads a run with its durable engine id", async () => {
    const { runs, user } = fake();
    const run = await runs.get("r1").orThrow();
    expect(run).toMatchObject({
      id: "r1",
      engine: "workflow",
      externalRunId: "wrun_1",
      status: "running",
      costMicroUsd: 120,
      usage: { inputTokens: 3 },
      endedAt: undefined,
    });
    expect(run.startedAt.toString()).toBe("2026-01-01T00:00:00Z");
    expect(user).toHaveBeenCalledWith("better_supabase", "get_ai_run", {
      run: "r1",
    });
  });

  it("lists runs and falls back on unknown states", async () => {
    const { runs, user } = fake();
    const list = await runs
      .list({ chatId: "c1", active: true, limit: 5 })
      .orThrow();
    expect(list.map((run) => run.status)).toEqual(["running", "running"]);
    expect(list[1]?.costMicroUsd).toBeUndefined();
    expect(lastArgs(user)).toEqual({ chat: "c1", active: true, size: 5 });
    await runs.list().orThrow();
    expect(lastArgs(user)).toEqual({
      chat: undefined,
      active: undefined,
      size: undefined,
    });
  });

  it("attaches the external run id on the service transport", async () => {
    const { runs, server } = fake();
    expect(await runs.attach("r1", "wrun_1").orThrow()).toBe(true);
    expect(server).toHaveBeenCalledWith("better_supabase", "attach_ai_run", {
      run: "r1",
      external_run_id: "wrun_1",
    });
  });

  it("records steps by key and lists them", async () => {
    const { runs, server, user } = fake();
    const step = await runs.steps
      .record("r1", {
        key: "search",
        label: "Search the web",
        status: "done",
        detail: { sources: 4 },
      })
      .orThrow();
    expect(step).toMatchObject({ key: "search", status: "done" });
    expect(step.endedAt?.toString()).toBe("2026-01-01T00:00:00Z");
    expect(lastArgs(server)).toEqual({
      run: "r1",
      step: {
        key: "search",
        label: "Search the web",
        status: "done",
        detail: { sources: 4 },
      },
    });
    await runs.steps.record("r1", { key: "plan" }).orThrow();
    expect(lastArgs(server)).toEqual({ run: "r1", step: { key: "plan" } });
    expect(await runs.steps.list("r1").orThrow()).toHaveLength(1);
    expect(lastArgs(user)).toEqual({ run: "r1" });
  });

  it("reads the approval inbox with chat titles", async () => {
    const { runs, user } = fake();
    const [approval] = await runs.pendingApprovals(10).orThrow();
    expect(approval).toMatchObject({
      approvalId: "approval-t1",
      decision: "pending",
      chatTitle: "Launch",
    });
    expect(lastArgs(user)).toEqual({ size: 10 });
    const untitled = fake({
      list_pending_ai_tool_approvals: [{ ...approvalRow, chat_title: null }],
    });
    const [row] = await untitled.runs.pendingApprovals().orThrow();
    expect(row?.chatTitle).toBe("");
  });
});

describe("createHarnessSessions", () => {
  it("loads a session or nothing", async () => {
    const { sessions, server } = fake();
    const session = await sessions.load("c1", "claude-code").orThrow();
    expect(session).toMatchObject({
      harnessId: "claude-code",
      resumeState: { session: "abc" },
      continueState: undefined,
      sandboxId: "sbx_1",
      status: "active",
    });
    expect(lastArgs(server)).toEqual({ chat: "c1", harness: "claude-code" });
    const none = fake({ load_ai_harness_session: null });
    expect(await none.sessions.load("c1", "x").orThrow()).toBeUndefined();
  });

  it("saves only the fields it is given", async () => {
    const { sessions, server } = fake();
    await sessions
      .save(
        "c1",
        "claude-code",
        { resumeState: { session: "b" }, sandboxId: null, status: "idle" },
        { holder: "turn-1" },
      )
      .orThrow();
    expect(lastArgs(server)).toEqual({
      chat: "c1",
      harness: "claude-code",
      fields: {
        resume_state: { session: "b" },
        sandbox_id: null,
        status: "idle",
      },
      holder: "turn-1",
    });
    await sessions
      .save("c1", "claude-code", { continueState: undefined })
      .orThrow();
    expect(lastArgs(server)).toMatchObject({
      fields: { continue_state: null },
      holder: undefined,
    });
  });

  it("locks and unlocks by holder", async () => {
    const { sessions, server } = fake();
    expect(
      await sessions
        .lock("c1", "claude-code", "turn-1", { ttlSeconds: 60 })
        .orThrow(),
    ).toBe(true);
    expect(lastArgs(server)).toEqual({
      chat: "c1",
      harness: "claude-code",
      holder: "turn-1",
      ttl_seconds: 60,
    });
    expect(await sessions.unlock("c1", "claude-code", "turn-1").orThrow()).toBe(
      false,
    );
  });

  it("lists idle sessions", async () => {
    const { sessions, server } = fake();
    const idle = await sessions.idle({ idleSeconds: 60, size: 5 }).orThrow();
    expect(idle).toHaveLength(1);
    expect(lastArgs(server)).toEqual({ idle_seconds: 60, size: 5 });
  });
});

describe("idleSandboxStop", () => {
  const session = (sandboxId: string | undefined): AiHarnessSession => ({
    chatId: "c1",
    harnessId: sandboxId ?? "h",
    ownerId: "u1",
    resumeState: undefined,
    continueState: undefined,
    sandboxId,
    status: "idle",
    lockHolder: undefined,
    lockedUntil: undefined,
    lastActiveAt: Temporal.Instant.from(AT),
    createdAt: Temporal.Instant.from(AT),
    updatedAt: Temporal.Instant.from(AT),
  });
  const job = {} as Job;

  const sessionsOf = (
    listed: readonly AiHarnessSession[],
    current: (s: AiHarnessSession) => AiHarnessSession | undefined = (s) => s,
  ) => {
    const byHarness = new Map(listed.map((s) => [s.harnessId, s]));
    return {
      idle: vi.fn(() => AsyncResult.from(async () => ok(listed))),
      load: vi.fn((_chat: string, harness: string) =>
        AsyncResult.from(async () => {
          const found = byHarness.get(harness);
          return ok(found === undefined ? undefined : current(found));
        }),
      ),
      save: vi.fn((_chat: string, harness: string) =>
        AsyncResult.from(async () =>
          harness === "sbx_bad"
            ? err(dbError("raised", "locked", { hint: "AI_HARNESS_LOCKED" }))
            : ok(session("x")),
        ),
      ),
      lock: vi.fn(
        (
          _chat: string,
          harness: string,
          _holder: string,
          _options?: { readonly ttlSeconds?: number },
        ) => AsyncResult.from(async () => ok(harness !== "sbx_busy")),
      ),
      unlock: vi.fn(() => AsyncResult.from(async () => ok(true))),
    };
  };

  it("locks each idle sandbox, stops it and marks failures", async () => {
    const sessions = sessionsOf([session("sbx_1"), session(undefined)]);
    const stop = vi.fn(async (s: AiHarnessSession) => {
      if (s.sandboxId === undefined) throw new Error("gone");
    });
    const handler = idleSandboxStop({
      sessions,
      stop,
      idleSeconds: 60,
      size: 10,
      lockSeconds: 30,
    });
    const result = await handler(undefined, job, new AbortController().signal);
    expect(result).toEqual({
      stopped: 1,
      failed: 1,
      skipped: 0,
      errors: ["h: gone"],
    });
    expect(sessions.idle).toHaveBeenCalledWith({ idleSeconds: 60, size: 10 });
    const holder = sessions.lock.mock.calls[0]?.[2];
    expect(holder).toMatch(/^idle-sandbox-stop:/);
    expect(sessions.lock).toHaveBeenCalledWith("c1", "sbx_1", holder, {
      ttlSeconds: 30,
    });
    expect(sessions.save).toHaveBeenCalledWith(
      "c1",
      "sbx_1",
      { status: "stopped", sandboxId: null },
      { holder },
    );
    expect(sessions.save).toHaveBeenCalledWith(
      "c1",
      "h",
      { status: "error" },
      { holder },
    );
    expect(sessions.unlock).toHaveBeenCalledTimes(2);
  });

  it("skips sessions a turn holds or used, and reports failed saves", async () => {
    const used = session("sbx_used");
    const sessions = sessionsOf(
      [session("sbx_busy"), used, session("sbx_bad")],
      (s) =>
        s === used
          ? {
              ...s,
              lastActiveAt: Temporal.Instant.from("2026-01-02T00:00:00Z"),
            }
          : s,
    );
    const stop = vi.fn(async () => {});
    const result = await idleSandboxStop({ sessions, stop })(
      undefined,
      job,
      new AbortController().signal,
    );
    expect(result).toEqual({
      stopped: 0,
      failed: 1,
      skipped: 2,
      errors: ["sbx_bad: locked"],
    });
    expect(stop).toHaveBeenCalledTimes(1);
    expect(sessions.lock.mock.calls[0]?.[3]).toEqual({ ttlSeconds: 120 });
    expect(sessions.save).toHaveBeenCalledWith(
      "c1",
      "sbx_used",
      { status: "active" },
      expect.anything(),
    );
    expect(sessions.unlock).toHaveBeenCalledTimes(2);
  });

  it("throws when the idle sessions can't be read", async () => {
    const idle = vi.fn(() =>
      AsyncResult.from<readonly AiHarnessSession[]>(async () =>
        err(dbError("unexpected", "down")),
      ),
    );
    const handler = idleSandboxStop({
      sessions: { ...sessionsOf([]), idle },
      stop: vi.fn(),
    });
    await expect(
      handler(undefined, job, new AbortController().signal),
    ).rejects.toThrow("down");
    expect(idle).toHaveBeenCalledWith({});
  });
});
