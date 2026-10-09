import type { AsyncResult } from "../../core/result.ts";
import type { JobHandler } from "../jobs/queue.ts";
import type { AiChatOptions, AiToolApproval } from "./ai-chat.ts";

import {
  applyTemporal,
  blockCall,
  errorText,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
  oneOf,
  pageOf,
} from "../shared.ts";
import { approvalOf } from "./rows.ts";

/** Where a run is: written by `runs.claim`, `release` and `stop`. */
export type AiRunState =
  | "queued"
  | "running"
  | "cancel_requested"
  | "done"
  | "error"
  | "stopped";

/** One generation of a chat, as `ai_runs` stores it. */
export interface AiRun {
  readonly id: string;
  readonly chatId: string;
  readonly ownerId: string;
  readonly assistantMessageId: string | undefined;
  readonly streamId: string | undefined;
  /** `ai-sdk` for a request-bound answer, `workflow` for a durable one. */
  readonly engine: string;
  /** The durable engine's own run id, such as a Workflow SDK run. */
  readonly externalRunId: string | undefined;
  readonly model: string | undefined;
  readonly status: AiRunState;
  readonly usage: Readonly<Record<string, unknown>>;
  readonly costMicroUsd: number | undefined;
  readonly error: string | undefined;
  readonly startedAt: Temporal.Instant;
  readonly endedAt: Temporal.Instant | undefined;
}

export interface AiRunQuery {
  /** One chat's runs; without it, the caller's own. */
  readonly chatId?: string;
  /** `true` keeps unfinished runs, `false` finished ones. */
  readonly active?: boolean;
  /** At most 200; defaults to 50. */
  readonly limit?: number;
  /** @deprecated Use `limit`. Removed in 0.8. */
  readonly size?: number;
}

export type AiRunStepStatus = "running" | "done" | "error" | "skipped";

/** One step of a long run's progress, as `ai_run_steps` stores it. */
export interface AiRunStep {
  readonly id: string;
  readonly runId: string;
  readonly chatId: string;
  /** The idempotency key: recording the same key again updates the step. */
  readonly key: string;
  readonly label: string;
  readonly status: AiRunStepStatus;
  readonly detail: Readonly<Record<string, unknown>>;
  readonly startedAt: Temporal.Instant;
  readonly endedAt: Temporal.Instant | undefined;
}

export interface AiRunStepInput {
  readonly key: string;
  /** Defaults to the key on the first record, then keeps the stored label. */
  readonly label?: string;
  /** Defaults to `running`. */
  readonly status?: AiRunStepStatus;
  /** Merged into the stored detail. */
  readonly detail?: Readonly<Record<string, unknown>>;
}

/** An undecided approval in the caller's inbox, with its chat's title. */
export interface AiPendingApproval extends AiToolApproval {
  readonly chatTitle: string;
}

export interface AiRuns {
  get(runId: string): AsyncResult<AiRun>;
  list(query?: AiRunQuery): AsyncResult<readonly AiRun[]>;
  /** Records the durable engine's run id on a claimed run (service role). */
  attach(runId: string, externalRunId: string): AsyncResult<boolean>;
  readonly steps: {
    /** Records or updates one step by its key (service role). */
    record(runId: string, step: AiRunStepInput): AsyncResult<AiRunStep>;
    list(runId: string): AsyncResult<readonly AiRunStep[]>;
  };
  /** The caller's undecided approvals across chats, newest first. */
  pendingApprovals(size?: number): AsyncResult<readonly AiPendingApproval[]>;
}

const RUN_STATES: readonly AiRunState[] = [
  "queued",
  "running",
  "cancel_requested",
  "done",
  "error",
  "stopped",
];

const STEP_STATES: readonly AiRunStepStatus[] = [
  "running",
  "done",
  "error",
  "skipped",
];

const HARNESS_STATES: readonly AiHarnessStatus[] = [
  "active",
  "idle",
  "stopped",
  "error",
];

const object = (value: unknown): Readonly<Record<string, unknown>> =>
  isRecord(value) ? value : {};

function runOf(value: unknown): AiRun {
  const row = recordOf(value, "ai_run");
  return {
    id: textOf(row["id"]),
    chatId: textOf(row["chat_id"]),
    ownerId: textOf(row["owner_id"]),
    assistantMessageId: optionalText(row["assistant_message_id"]),
    streamId: optionalText(row["stream_id"]),
    engine: textOf(row["engine"]),
    externalRunId: optionalText(row["external_run_id"]),
    model: optionalText(row["model"]),
    status: oneOf(row["status"], RUN_STATES, "running"),
    usage: object(row["usage"]),
    costMicroUsd:
      row["cost_micro_usd"] === null || row["cost_micro_usd"] === undefined
        ? undefined
        : Number(row["cost_micro_usd"]),
    error: optionalText(row["error"]),
    startedAt: toInstant(textOf(row["started_at"])),
    endedAt: optionalInstant(row["ended_at"]),
  };
}

function stepOf(value: unknown): AiRunStep {
  const row = recordOf(value, "ai_run_step");
  return {
    id: textOf(row["id"]),
    runId: textOf(row["run_id"]),
    chatId: textOf(row["chat_id"]),
    key: textOf(row["step_key"]),
    label: textOf(row["label"]),
    status: oneOf(row["status"], STEP_STATES, "running"),
    detail: object(row["detail"]),
    startedAt: toInstant(textOf(row["started_at"])),
    endedAt: optionalInstant(row["ended_at"]),
  };
}

/**
 * Run lookups, run steps and the approval inbox of the `ai-chat` block: what
 * a durable chat needs to stop or resume a run, and what an activity console
 * shows. Engine-neutral, like `createAiChat`.
 */
export function createAiRuns(options: AiChatOptions): AiRuns {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  return {
    get: (runId) => call("get_ai_run", { run: runId }, runOf),
    list: (query = {}) =>
      call(
        "list_ai_runs",
        { chat: query.chatId, active: query.active, size: pageOf(query).limit },
        (value) => recordsOf(value, "list_ai_runs").map(runOf),
      ),
    attach: (runId, externalRunId) =>
      service(
        "attach_ai_run",
        { run: runId, external_run_id: externalRunId },
        (value) => value === true,
      ),
    steps: {
      record: (runId, step) =>
        service(
          "record_ai_run_step",
          {
            run: runId,
            step: {
              key: step.key,
              ...(step.label === undefined ? {} : { label: step.label }),
              ...(step.status === undefined ? {} : { status: step.status }),
              ...(step.detail === undefined ? {} : { detail: step.detail }),
            },
          },
          stepOf,
        ),
      list: (runId) =>
        call("list_ai_run_steps", { run: runId }, (value) =>
          recordsOf(value, "list_ai_run_steps").map(stepOf),
        ),
    },
    pendingApprovals: (size) =>
      call("list_pending_ai_tool_approvals", { size }, (value) =>
        recordsOf(value, "list_pending_ai_tool_approvals").map((row) => ({
          ...approvalOf(row),
          chatTitle: textOf(row["chat_title"] ?? ""),
        })),
      ),
  };
}

export type AiHarnessStatus = "active" | "idle" | "stopped" | "error";

/**
 * What a coding-agent harness keeps per chat to pick the conversation up
 * again. The states are the harness's own JSON; nothing here reads them.
 */
export interface AiHarnessSession {
  readonly chatId: string;
  readonly harnessId: string;
  readonly ownerId: string;
  readonly resumeState: unknown;
  readonly continueState: unknown;
  readonly sandboxId: string | undefined;
  readonly status: AiHarnessStatus;
  readonly lockHolder: string | undefined;
  readonly lockedUntil: Temporal.Instant | undefined;
  readonly lastActiveAt: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** The fields to change; a field that is absent keeps its value. */
export interface AiHarnessSessionPatch {
  readonly resumeState?: unknown;
  readonly continueState?: unknown;
  /** `null` forgets the sandbox. */
  readonly sandboxId?: string | null;
  readonly status?: AiHarnessStatus;
}

/**
 * The experimental harness session store, on the service role: `lock` keeps
 * two turns from driving one sandbox, `save` refuses a session another holder
 * locked (`AI_HARNESS_LOCKED`).
 */
export interface AiHarnessSessions {
  load(
    chatId: string,
    harnessId: string,
  ): AsyncResult<AiHarnessSession | undefined>;
  save(
    chatId: string,
    harnessId: string,
    patch: AiHarnessSessionPatch,
    options?: { readonly holder?: string },
  ): AsyncResult<AiHarnessSession>;
  /** `true` when `holder` holds the lock for `ttlSeconds` (default 300). */
  lock(
    chatId: string,
    harnessId: string,
    holder: string,
    options?: { readonly ttlSeconds?: number },
  ): AsyncResult<boolean>;
  unlock(
    chatId: string,
    harnessId: string,
    holder: string,
  ): AsyncResult<boolean>;
  /**
   * Marks sessions whose sandbox sat unused for `idleSeconds` (default 900)
   * as idle and returns them.
   */
  idle(options?: {
    readonly idleSeconds?: number;
    readonly size?: number;
  }): AsyncResult<readonly AiHarnessSession[]>;
}

function harnessOf(value: unknown): AiHarnessSession {
  const row = recordOf(value, "ai_harness_session");
  return {
    chatId: textOf(row["chat_id"]),
    harnessId: textOf(row["harness_id"]),
    ownerId: textOf(row["owner_id"]),
    resumeState: row["resume_state"] ?? undefined,
    continueState: row["continue_state"] ?? undefined,
    sandboxId: optionalText(row["sandbox_id"]),
    status: oneOf(row["status"], HARNESS_STATES, "active"),
    lockHolder: optionalText(row["lock_holder"]),
    lockedUntil: optionalInstant(row["locked_until"]),
    lastActiveAt: toInstant(textOf(row["last_active_at"])),
    createdAt: toInstant(textOf(row["created_at"])),
    updatedAt: toInstant(textOf(row["updated_at"])),
  };
}

function patchFields(patch: AiHarnessSessionPatch): Record<string, unknown> {
  return {
    ...("resumeState" in patch
      ? { resume_state: patch.resumeState ?? null }
      : {}),
    ...("continueState" in patch
      ? { continue_state: patch.continueState ?? null }
      : {}),
    ...("sandboxId" in patch ? { sandbox_id: patch.sandboxId ?? null } : {}),
    ...(patch.status === undefined ? {} : { status: patch.status }),
  };
}

/**
 * The harness session store of the `ai-chat` block (experimental). It takes
 * a service transport: harness state stays on the server.
 */
export function createHarnessSessions(
  options: AiChatOptions,
): AiHarnessSessions {
  applyTemporal(options);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const isTrue = (value: unknown): boolean => value === true;
  return {
    load: (chatId, harnessId) =>
      service(
        "load_ai_harness_session",
        { chat: chatId, harness: harnessId },
        (value) => (value === null ? undefined : harnessOf(value)),
      ),
    save: (chatId, harnessId, patch, saveOptions = {}) =>
      service(
        "save_ai_harness_session",
        {
          chat: chatId,
          harness: harnessId,
          fields: patchFields(patch),
          holder: saveOptions.holder,
        },
        harnessOf,
      ),
    lock: (chatId, harnessId, holder, lockOptions = {}) =>
      service(
        "lock_ai_harness_session",
        {
          chat: chatId,
          harness: harnessId,
          holder,
          ttl_seconds: lockOptions.ttlSeconds,
        },
        isTrue,
      ),
    unlock: (chatId, harnessId, holder) =>
      service(
        "unlock_ai_harness_session",
        { chat: chatId, harness: harnessId, holder },
        isTrue,
      ),
    idle: (idleOptions = {}) =>
      service(
        "idle_ai_harness_sessions",
        { idle_seconds: idleOptions.idleSeconds, size: idleOptions.size },
        (value) => recordsOf(value, "idle_ai_harness_sessions").map(harnessOf),
      ),
  };
}

export interface IdleSandboxStopOptions {
  readonly sessions: Pick<
    AiHarnessSessions,
    "idle" | "load" | "save" | "lock" | "unlock"
  >;
  /** Stops one sandbox, such as `Sandbox.get({ sandboxId }).stop()`. */
  readonly stop: (session: AiHarnessSession) => Promise<unknown>;
  /** Seconds a sandbox may sit unused. Defaults to 900. */
  readonly idleSeconds?: number;
  /** Sessions per run. Defaults to 100. */
  readonly size?: number;
  /** How long the stop holds each session's lock. Defaults to 120. */
  readonly lockSeconds?: number;
}

/** What one idle-sandbox run did. */
export interface IdleSandboxStopResult {
  readonly stopped: number;
  readonly failed: number;
  /** Sessions a turn locked or used since `idle` listed them; left running. */
  readonly skipped: number;
  /** Why each failed sandbox did not stop. */
  readonly errors: readonly string[];
}

type StopOutcome = "stopped" | "skipped" | { readonly error: string };

/**
 * A job handler for a schedule that stops idle harness sandboxes. Each
 * session idle for `idleSeconds` is locked first, so a turn that starts
 * meanwhile keeps its sandbox; a session that is locked, or was used since
 * `idle` listed it, is skipped. A stopped session turns `stopped` without a
 * sandbox, or `error` when `stop` threw.
 */
export function idleSandboxStop(
  options: IdleSandboxStopOptions,
): JobHandler<unknown> {
  const { sessions } = options;
  const lockOptions = { ttlSeconds: options.lockSeconds ?? 120 };

  const stopOne = async (
    listed: AiHarnessSession,
    holder: string,
  ): Promise<StopOutcome> => {
    const { chatId, harnessId } = listed;
    const locked = await sessions.lock(chatId, harnessId, holder, lockOptions);
    if (!locked.ok) return { error: locked.error.message };
    if (!locked.data) return "skipped";
    try {
      const current = await sessions.load(chatId, harnessId);
      if (!current.ok) return { error: current.error.message };
      const session = current.data;
      if (session === undefined) return "skipped";
      if (
        session.status !== "idle" ||
        session.sandboxId !== listed.sandboxId ||
        !session.lastActiveAt.equals(listed.lastActiveAt)
      ) {
        // idle() marked it idle; a session used since then goes back to
        // active so a later run can still find its sandbox.
        if (session.status === "idle" && session.sandboxId !== undefined) {
          await sessions.save(
            chatId,
            harnessId,
            { status: "active" },
            { holder },
          );
        }
        return "skipped";
      }
      try {
        await options.stop(session);
      } catch (cause) {
        const marked = await sessions.save(
          chatId,
          harnessId,
          { status: "error" },
          { holder },
        );
        return {
          error: marked.ok
            ? errorText(cause)
            : `${errorText(cause)} (marking it failed: ${marked.error.message})`,
        };
      }
      const saved = await sessions.save(
        chatId,
        harnessId,
        { status: "stopped", sandboxId: null },
        { holder },
      );
      return saved.ok ? "stopped" : { error: saved.error.message };
    } finally {
      await sessions.unlock(chatId, harnessId, holder);
    }
  };

  return async (): Promise<IdleSandboxStopResult> => {
    const listed = await sessions
      .idle({
        ...(options.idleSeconds === undefined
          ? {}
          : { idleSeconds: options.idleSeconds }),
        ...(options.size === undefined ? {} : { size: options.size }),
      })
      .orThrow();
    const holder = `idle-sandbox-stop:${crypto.randomUUID()}`;
    let stopped = 0;
    let skipped = 0;
    const errors: string[] = [];
    for (const session of listed) {
      let outcome: StopOutcome;
      try {
        outcome = await stopOne(session, holder);
      } catch (cause) {
        outcome = { error: errorText(cause) };
      }
      if (outcome === "stopped") stopped += 1;
      else if (outcome === "skipped") skipped += 1;
      else
        errors.push(
          `${session.sandboxId ?? session.harnessId}: ${outcome.error}`,
        );
    }
    return { stopped, failed: errors.length, skipped, errors };
  };
}
