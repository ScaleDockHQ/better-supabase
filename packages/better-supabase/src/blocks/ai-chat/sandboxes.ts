import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { JobHandler } from "../jobs/queue.ts";

import { errorText } from "../../core/block-helpers.ts";
import { AsyncResult as Result, ok } from "../../core/result.ts";
import { recordsOf } from "../shared.ts";
import { sandboxOf } from "./sandbox-rows.ts";

export type AiSandboxStatus = "running" | "stopping" | "stopped";

export interface AiSandbox {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string | undefined;
  readonly chatId: string | undefined;
  /** The harness session the sandbox belongs to, when a harness started it. */
  readonly harnessId: string | undefined;
  /** Who runs it, such as `vercel` or `anthropic`; `harness` for a harness session's sandbox saved without one. */
  readonly provider: string;
  readonly sandboxId: string;
  /** A provider container id, such as Anthropic's code execution container. */
  readonly containerId: string | undefined;
  readonly status: AiSandboxStatus;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly idleSeconds: number;
  readonly error: string | undefined;
  readonly lastUsedAt: Temporal.Instant;
  readonly expiresAt: Temporal.Instant | undefined;
  readonly stoppedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface NewAiSandbox {
  readonly provider: string;
  readonly sandboxId: string;
  readonly userId?: string;
  readonly chatId?: string;
  readonly harnessId?: string;
  readonly containerId?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  /** Seconds without use before the idle-stop claim takes it; ai-chat's `sandboxIdleAfter` by default. */
  readonly idleSeconds?: number;
  readonly expiresAt?: Temporal.Instant;
}

/** Stops one sandbox at its provider. A throw keeps it running for the next try. */
export type AiSandboxStopper = (sandbox: AiSandbox) => Promise<unknown>;

/**
 * The sandboxes chats and harness sessions started, in `ai_sandboxes`, with
 * one idle-stop claim for all of them.
 */
export interface AiSandboxes {
  /** Records a sandbox, or marks a known one running and used (service role). */
  register(
    organizationId: string,
    sandbox: NewAiSandbox,
  ): AsyncResult<AiSandbox>;
  /** Marks a sandbox used now (service role). `false` when it is not running. */
  touch(sandboxId: string): AsyncResult<boolean>;
  /** The chat's running sandbox at a provider, to reuse it (service role). */
  forChat(chatId: string, provider: string): AsyncResult<AiSandbox | undefined>;
  list(
    organizationId: string,
    options?: { readonly chatId?: string },
  ): AsyncResult<readonly AiSandbox[]>;
  /**
   * Claims idle and expired sandboxes to stop (service role). A sandbox
   * whose harness session is locked by a turn is skipped.
   */
  idle(options?: {
    readonly batch?: number;
    readonly leaseSeconds?: number;
  }): AsyncResult<readonly AiSandbox[]>;
  /**
   * Records a claimed stop. A stopped harness sandbox stops its session too;
   * `false` when a turn used the sandbox again since the claim.
   */
  finishStop(
    sandboxId: string,
    stopped: boolean,
    error?: string,
  ): AsyncResult<boolean>;
  /** Claims idle sandboxes, stops each with `stop`, and records the outcome. Returns how many stopped. */
  stopIdle(
    stop: AiSandboxStopper,
    options?: { readonly batch?: number },
  ): AsyncResult<number>;
  /** A job handler that runs `stopIdle`; schedule it every few minutes. */
  idleStopJob(
    stop: AiSandboxStopper,
    options?: { readonly batch?: number },
  ): JobHandler<unknown>;
}

function sandboxFields(sandbox: NewAiSandbox): Record<string, unknown> {
  return {
    ...(sandbox.userId === undefined ? {} : { user_id: sandbox.userId }),
    ...(sandbox.chatId === undefined ? {} : { chat_id: sandbox.chatId }),
    ...(sandbox.harnessId === undefined
      ? {}
      : { harness_id: sandbox.harnessId }),
    ...(sandbox.containerId === undefined
      ? {}
      : { container_id: sandbox.containerId }),
    ...(sandbox.metadata === undefined ? {} : { metadata: sandbox.metadata }),
    ...(sandbox.idleSeconds === undefined
      ? {}
      : { idle_seconds: Math.max(1, Math.round(sandbox.idleSeconds)) }),
    ...(sandbox.expiresAt === undefined
      ? {}
      : { expires_at: sandbox.expiresAt.toString() }),
  };
}

/** The sandbox registry over the chat block's user and service calls. */
export function aiSandboxes(call: BlockCall, service: BlockCall): AiSandboxes {
  const idle: AiSandboxes["idle"] = (idleOptions = {}) =>
    service(
      "idle_ai_sandboxes",
      { batch: idleOptions.batch, lease_seconds: idleOptions.leaseSeconds },
      (value) => recordsOf(value, "idle_ai_sandboxes").map(sandboxOf),
    );

  const finishStop: AiSandboxes["finishStop"] = (sandboxId, stopped, error) =>
    service(
      "finish_ai_sandbox_stop",
      { id: sandboxId, stopped, error },
      (value) => value === true,
    );

  const stopIdle: AiSandboxes["stopIdle"] = (stop, stopOptions = {}) =>
    idle(stopOptions).andThen((claimed) =>
      Result.from(async () => {
        let stopped = 0;
        for (const sandbox of claimed) {
          let error: string | undefined;
          try {
            await stop(sandbox);
          } catch (cause) {
            error = errorText(cause);
          }
          const finished = await finishStop(
            sandbox.id,
            error === undefined,
            error,
          );
          if (!finished.ok) return finished;
          if (error === undefined) stopped += 1;
        }
        return ok(stopped);
      }),
    );

  return {
    register: (organizationId, sandbox) =>
      service(
        "register_ai_sandbox",
        {
          tenant: organizationId,
          provider: sandbox.provider,
          sandbox_id: sandbox.sandboxId,
          fields: sandboxFields(sandbox),
        },
        sandboxOf,
      ),
    touch: (sandboxId) =>
      service("touch_ai_sandbox", { id: sandboxId }, (value) => value === true),
    forChat: (chatId, provider) =>
      service("ai_sandbox_for", { chat_id: chatId, provider }, (value) =>
        value === null || value === undefined ? undefined : sandboxOf(value),
      ),
    list: (organizationId, listOptions = {}) =>
      call(
        "list_ai_sandboxes",
        { tenant: organizationId, chat_id: listOptions.chatId },
        (value) => recordsOf(value, "list_ai_sandboxes").map(sandboxOf),
      ),
    idle,
    finishStop,
    stopIdle,
    idleStopJob: (stop, jobOptions) => async () =>
      stopIdle(stop, jobOptions).orThrow(),
  };
}
