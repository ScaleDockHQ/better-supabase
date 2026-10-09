import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/blocks/ai-chat/index.ts";

import {
  createAiChat,
  createHarnessSessions,
  idleSandboxStop,
  sqlTransport,
} from "../../src/blocks/ai-chat/index.ts";
import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

async function setUp(s: BlockSession) {
  await s.install(["organizations", "outbox", "ai-chat"]);
  const owner = await s.user("owner");
  const member = await s.user("member");
  const outsider = await s.user("outsider");
  const tenant = await s.organization(owner, { member });
  await s.as(owner);
  const chat = await s.value<{ id: string }>(
    "better_supabase.create_ai_chat($1, $2)",
    [tenant, { title: "Research" }],
  );
  return { owner, member, outsider, tenant, chat: chat.id };
}

/** A user transport and a service transport over one session. */
function transports(s: BlockSession, caller: () => TestUser) {
  const user = sqlTransport(s.sql);
  const service: BlockTransport = {
    async call(schema, fn, args) {
      await s.service();
      try {
        return await user.call(schema, fn, args);
      } finally {
        await s.as(caller());
      }
    },
  };
  return { user, service };
}

describe.skipIf(!live)("ai-chat durable runs and harness sessions", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("attaches engine runs, records steps and lists them for readers", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, outsider, chat } = await setUp(s);
      await s.service();
      const claim = await s.value<{ run_id: string }>(
        "better_supabase.claim_ai_chat_stream($1, 's1', null, null, 'workflow', 'wrun_1')",
        [chat],
      );
      expect(
        await s.value("better_supabase.attach_ai_run($1, 'wrun_2')", [
          claim.run_id,
        ]),
      ).toBe(true);
      expect(
        await s.value("better_supabase.attach_ai_run($1, 'x')", [
          crypto.randomUUID(),
        ]),
      ).toBe(false);

      const first = await s.value<{ status: string; ended_at: null }>(
        "better_supabase.record_ai_run_step($1, $2)",
        [claim.run_id, { key: "search", label: "Search the web" }],
      );
      expect(first).toMatchObject({
        status: "running",
        label: "Search the web",
        ended_at: null,
      });
      const done = await s.value<{
        status: string;
        label: string;
        detail: object;
        ended_at: string | null;
      }>("better_supabase.record_ai_run_step($1, $2)", [
        claim.run_id,
        { key: "search", status: "done", detail: { hits: 3 } },
      ]);
      expect(done).toMatchObject({
        status: "done",
        label: "Search the web",
        detail: { hits: 3 },
      });
      expect(done.ended_at).not.toBeNull();
      expect(
        await s.hint("better_supabase.record_ai_run_step($1, $2)", [
          claim.run_id,
          { key: "x", status: "paused" },
        ]),
      ).toBe("AI_RUN_STEP_INVALID");
      expect(
        await s.hint("better_supabase.record_ai_run_step($1, $2)", [
          crypto.randomUUID(),
          { key: "x" },
        ]),
      ).toBe("AI_RUN_NOT_FOUND");

      await s.as(owner);
      expect(
        await s.value<{ engine: string; external_run_id: string }>(
          "better_supabase.get_ai_run($1)",
          [claim.run_id],
        ),
      ).toMatchObject({ engine: "workflow", external_run_id: "wrun_2" });
      expect(
        await s.value<{ step_key: string }[]>(
          "better_supabase.list_ai_run_steps($1)",
          [claim.run_id],
        ),
      ).toEqual([expect.objectContaining({ step_key: "search" })]);
      expect(
        await s.value<unknown[]>("better_supabase.list_ai_runs($1, true)", [
          chat,
        ]),
      ).toHaveLength(1);
      expect(
        await s.value<unknown[]>("better_supabase.list_ai_runs($1, false)", [
          chat,
        ]),
      ).toEqual([]);
      expect(
        await s.value<unknown[]>("better_supabase.list_ai_runs()"),
      ).toHaveLength(1);
      expect(
        await s.hint("better_supabase.attach_ai_run($1, 'x')", [claim.run_id]),
      ).toBe("AI_CHAT_FORBIDDEN");
      expect(
        await s.hint("better_supabase.record_ai_run_step($1, $2)", [
          claim.run_id,
          { key: "x" },
        ]),
      ).toBe("AI_CHAT_FORBIDDEN");

      await s.as(outsider);
      expect(
        await s.hint("better_supabase.get_ai_run($1)", [claim.run_id]),
      ).toBe("AI_RUN_NOT_FOUND");
      expect(
        await s.hint("better_supabase.list_ai_run_steps($1)", [claim.run_id]),
      ).toBe("AI_RUN_NOT_FOUND");
      expect(await s.hint("better_supabase.list_ai_runs($1)", [chat])).toBe(
        "AI_CHAT_NOT_FOUND",
      );
      expect(
        await s.value<unknown[]>("better_supabase.list_ai_runs()"),
      ).toEqual([]);
    } finally {
      await s.close();
    }
  });

  it("drives runs and the approval inbox through the block client", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, outsider, chat } = await setUp(s);
      let caller: TestUser = owner;
      const { user, service } = transports(s, () => caller);
      const ai = createAiChat({ transport: user, service });
      const runs = ai.runs;

      const claim = await ai.runs
        .claim(chat, "stream-1", { model: "openai/gpt-5" })
        .orThrow();
      expect(claim.runId).toBeDefined();
      const runId = claim.runId ?? "";
      expect(await runs.attach(runId, "wrun_9").orThrow()).toBe(true);
      const step = await runs.steps
        .record(runId, { key: "plan", label: "Plan" })
        .orThrow();
      expect(step).toMatchObject({ key: "plan", status: "running" });
      expect(step.endedAt).toBeUndefined();
      await runs.steps
        .record(runId, { key: "plan", status: "done", detail: { n: 1 } })
        .orThrow();

      const run = await runs.get(runId).orThrow();
      expect(run).toMatchObject({
        chatId: chat,
        externalRunId: "wrun_9",
        status: "running",
        model: "openai/gpt-5",
      });
      expect(
        (await runs.list({ chatId: chat, active: true }).orThrow()).map(
          (r) => r.id,
        ),
      ).toEqual([runId]);
      const steps = await runs.steps.list(runId).orThrow();
      expect(steps).toEqual([
        expect.objectContaining({
          key: "plan",
          status: "done",
          detail: { n: 1 },
        }),
      ]);
      expect(steps[0]?.endedAt).toBeDefined();

      await ai.approvals
        .request(chat, {
          approvalId: "ap-1",
          tool: "deleteFile",
          toolCallId: "t1",
          input: { path: "/tmp/x" },
        })
        .orThrow();
      await ai.approvals
        .request(chat, {
          approvalId: "ap-2",
          tool: "deleteFile",
          toolCallId: "t2",
          input: { path: "/tmp/y" },
        })
        .orThrow();
      await ai.approvals.decide("ap-2", true).orThrow();
      const pending = await runs.pendingApprovals().orThrow();
      expect(pending).toEqual([
        expect.objectContaining({
          approvalId: "ap-1",
          chatId: chat,
          chatTitle: "Research",
          tool: "deleteFile",
        }),
      ]);

      caller = outsider;
      await s.as(outsider);
      expect(await runs.pendingApprovals().orThrow()).toEqual([]);
      const hidden = await runs.get(runId);
      expect(hidden.ok ? undefined : hidden.error.kind).toBe("not_found");
      const denied = await createAiChat({ transport: user }).runs.attach(
        runId,
        "x",
      );
      expect(denied.ok ? undefined : denied.error.kind).toBe("forbidden");
    } finally {
      await s.close();
    }
  });

  it("locks harness sessions per holder and saves partial patches", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, chat } = await setUp(s);
      await s.service();
      expect(
        await s.value("better_supabase.load_ai_harness_session($1, 'claude')", [
          chat,
        ]),
      ).toBeNull();
      expect(
        await s.value(
          "better_supabase.lock_ai_harness_session($1, 'claude', 'turn-1', 60)",
          [chat],
        ),
      ).toBe(true);
      expect(
        await s.value(
          "better_supabase.lock_ai_harness_session($1, 'claude', 'turn-2', 60)",
          [chat],
        ),
      ).toBe(false);
      expect(
        await s.value(
          "better_supabase.lock_ai_harness_session($1, 'claude', 'turn-1', 60)",
          [chat],
        ),
      ).toBe(true);
      expect(
        await s.hint(
          "better_supabase.save_ai_harness_session($1, 'claude', $2, 'turn-2')",
          [chat, { sandbox_id: "sbx_1" }],
        ),
      ).toBe("AI_HARNESS_LOCKED");
      expect(
        await s.hint(
          "better_supabase.lock_ai_harness_session($1, 'claude', 'turn-2', 0)",
          [chat],
        ),
      ).toBe("AI_HARNESS_INVALID");
      expect(
        await s.hint("better_supabase.save_ai_harness_session($1, '', $2)", [
          chat,
          {},
        ]),
      ).toBe("AI_HARNESS_INVALID");
      expect(
        await s.hint(
          "better_supabase.save_ai_harness_session($1, 'claude', $2, 'turn-1')",
          [chat, { status: "paused" }],
        ),
      ).toBe("AI_HARNESS_INVALID");
      expect(
        await s.hint(
          "better_supabase.save_ai_harness_session($1, 'claude', $2)",
          [crypto.randomUUID(), {}],
        ),
      ).toBe("AI_CHAT_NOT_FOUND");

      const saved = await s.value<Record<string, unknown>>(
        "better_supabase.save_ai_harness_session($1, 'claude', $2, 'turn-1')",
        [chat, { sandbox_id: "sbx_1", resume_state: { session: "abc" } }],
      );
      expect(saved).toMatchObject({
        owner_id: owner.id,
        sandbox_id: "sbx_1",
        resume_state: { session: "abc" },
        continue_state: null,
        status: "active",
        lock_holder: "turn-1",
      });
      const patched = await s.value<Record<string, unknown>>(
        "better_supabase.save_ai_harness_session($1, 'claude', $2, 'turn-1')",
        [chat, { continue_state: { cursor: 2 } }],
      );
      expect(patched).toMatchObject({
        sandbox_id: "sbx_1",
        resume_state: { session: "abc" },
        continue_state: { cursor: 2 },
      });

      expect(
        await s.value(
          "better_supabase.unlock_ai_harness_session($1, 'claude', 'turn-2')",
          [chat],
        ),
      ).toBe(false);
      expect(
        await s.value(
          "better_supabase.unlock_ai_harness_session($1, 'claude', 'turn-1')",
          [chat],
        ),
      ).toBe(true);
      expect(
        await s.value(
          "better_supabase.lock_ai_harness_session($1, 'claude', 'turn-2', 60)",
          [chat],
        ),
      ).toBe(true);
      await s.rows(
        "update better_supabase.ai_harness_sessions set locked_until = now() - interval '1 second' where chat_id = $1",
        [chat],
      );
      expect(
        await s.value(
          "better_supabase.lock_ai_harness_session($1, 'claude', 'turn-3', 60)",
          [chat],
        ),
      ).toBe(true);

      await s.as(owner);
      for (const call of [
        "better_supabase.load_ai_harness_session($1, 'claude')",
        "better_supabase.save_ai_harness_session($1, 'claude', '{}')",
        "better_supabase.lock_ai_harness_session($1, 'claude', 'me')",
        "better_supabase.unlock_ai_harness_session($1, 'claude', 'me')",
      ])
        expect(await s.hint(call, [chat])).toBe("AI_CHAT_FORBIDDEN");
      expect(await s.hint("better_supabase.idle_ai_harness_sessions()")).toBe(
        "AI_CHAT_FORBIDDEN",
      );

      await s.asRole(owner);
      expect(
        await s.hint(
          "select harness_id from better_supabase.ai_harness_sessions",
        ),
      ).not.toBe("no error");
    } finally {
      await s.close();
    }
  });

  it("stops idle sandboxes through the job handler", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, chat } = await setUp(s);
      const { user, service } = transports(s, () => owner);
      const sessions = createHarnessSessions({ transport: user, service });

      await sessions
        .save(chat, "claude", { sandboxId: "sbx_ok", resumeState: { a: 1 } })
        .orThrow();
      await sessions.save(chat, "codex", { sandboxId: "sbx_bad" }).orThrow();
      await sessions.save(chat, "busy", { sandboxId: "sbx_busy" }).orThrow();
      await sessions.save(chat, "fresh", { sandboxId: "sbx_new" }).orThrow();
      expect(await sessions.lock(chat, "busy", "turn-1").orThrow()).toBe(true);
      await s.service();
      await s.rows(
        "update better_supabase.ai_harness_sessions set last_active_at = now() - interval '1 hour' where chat_id = $1 and harness_id <> 'fresh'",
        [chat],
      );
      await s.as(owner);

      const loaded = await sessions.load(chat, "claude").orThrow();
      expect(loaded).toMatchObject({
        harnessId: "claude",
        sandboxId: "sbx_ok",
        resumeState: { a: 1 },
        status: "active",
      });
      expect(await sessions.load(chat, "none").orThrow()).toBeUndefined();

      const stopped: string[] = [];
      const job = idleSandboxStop({
        sessions,
        idleSeconds: 600,
        stop: async (session) => {
          if (session.sandboxId === "sbx_bad") throw new Error("gone");
          stopped.push(session.sandboxId ?? "");
        },
      });
      const result = await job(
        undefined,
        never(),
        new AbortController().signal,
      );
      expect(result).toEqual({
        stopped: 1,
        failed: 1,
        skipped: 0,
        errors: ["sbx_bad: gone"],
      });
      expect(stopped).toEqual(["sbx_ok"]);

      const after = async (harness: string) =>
        sessions.load(chat, harness).orThrow();
      expect(await after("claude")).toMatchObject({
        status: "stopped",
        sandboxId: undefined,
        resumeState: { a: 1 },
      });
      expect(await after("codex")).toMatchObject({
        status: "error",
        sandboxId: "sbx_bad",
      });
      expect(await after("busy")).toMatchObject({ status: "active" });
      expect(await after("fresh")).toMatchObject({ status: "active" });
      expect(await sessions.idle({ idleSeconds: 600 }).orThrow()).toEqual([]);
    } finally {
      await s.close();
    }
  });

  it("turns an idle session active again when a turn saves it", async () => {
    const s = await BlockSession.open(pool);
    try {
      const { owner, chat } = await setUp(s);
      const { user, service } = transports(s, () => owner);
      const sessions = createHarnessSessions({ transport: user, service });

      await sessions.save(chat, "claude", { sandboxId: "sbx_race" }).orThrow();
      await s.service();
      await s.rows(
        "update better_supabase.ai_harness_sessions set last_active_at = now() - interval '1 hour' where chat_id = $1",
        [chat],
      );
      await s.as(owner);
      expect(
        (await sessions.idle({ idleSeconds: 600 }).orThrow()).map(
          (session) => session.status,
        ),
      ).toEqual(["idle"]);

      expect(await sessions.lock(chat, "claude", "turn-1").orThrow()).toBe(
        true,
      );
      await sessions
        .save(chat, "claude", { resumeState: { b: 2 } }, { holder: "turn-1" })
        .orThrow();
      await sessions.unlock(chat, "claude", "turn-1").orThrow();

      expect(await sessions.load(chat, "claude").orThrow()).toMatchObject({
        status: "active",
        sandboxId: "sbx_race",
      });
    } finally {
      await s.close();
    }
  });
});

function never<T>(): T {
  // SAFETY: the idle-sandbox handler never reads its job argument.
  return undefined as T;
}
