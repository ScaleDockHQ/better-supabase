import type {
  RunCompletedHookParams,
  RunFailedHookParams,
  WorkflowLifecycleHooks,
} from "workflow/api";

import { registerLifecycleHooks } from "workflow/api";

import type { Outbox } from "../blocks/outbox/outbox.ts";
import type { Events } from "../core/event-map.ts";
import type { EventHub } from "../core/events.ts";
import type { Logger } from "../core/logger.ts";

import { emitBlockEvent } from "../core/block-events.ts";
import { defineEvents, event } from "../core/event-map.ts";
import { consoleLogger } from "../core/logger.ts";

/** The data of `workflow_sdk.run_completed` and `workflow_sdk.run_failed`. */
export interface WorkflowSdkRunEventData {
  readonly runId: string;
  /**
   * The machine-readable id, such as
   * `workflow//./src/workflows/order//processOrder`.
   */
  readonly workflowName: string;
  /** `run_failed`: the runtime's classification, such as `USER_ERROR`. */
  readonly errorCode?: string;
  /** `run_failed`: the thrown value's `name`. */
  readonly errorName?: string;
  /** `run_failed`: the thrown value's message, cut to 500 characters. */
  readonly errorMessage?: string;
}

/**
 * The events `registerWorkflowLifecycle` writes: type to data. They carry the
 * `workflow_sdk.` prefix because the workflows block already owns
 * `workflow_run.*`.
 */
export type WorkflowSdkEvents = {
  readonly "workflow_sdk.run_completed": WorkflowSdkRunEventData;
  readonly "workflow_sdk.run_failed": WorkflowSdkRunEventData;
};

/** The lifecycle event types, for `onBlockEvent` and outbox consumers. */
export const workflowSdkEvents: Events<WorkflowSdkEvents> = defineEvents({
  "workflow_sdk.run_completed": event<WorkflowSdkRunEventData>(),
  "workflow_sdk.run_failed": event<WorkflowSdkRunEventData>(),
});

export interface WorkflowLifecycleOptions {
  /**
   * Writes each transition as an outbox event, keyed on the run id and the
   * transition so a repeated delivery of the hook writes it once. Build it with
   * a service transport: the hooks run outside any request.
   */
  readonly outbox?: Pick<Outbox, "emit">;
  /** Emits each transition as a block event too, for `traceBlockEvents`. */
  readonly events?: EventHub;
  /** Only report workflows this returns `true` for. Defaults to all. */
  readonly workflows?: (workflowName: string) => boolean;
  /** CloudEvents `source` stored with the outbox row. */
  readonly source?: string;
  /** Receives write failures. Defaults to the events logger, then `console`. */
  readonly logger?: Logger;
  /**
   * `registerLifecycleHooks` from `workflow/api`; set it to test, or to use the
   * app's own copy of the SDK.
   */
  readonly register?: (hooks: WorkflowLifecycleHooks) => () => void;
}

const MAX_MESSAGE = 500;

function failure(params: RunFailedHookParams): {
  readonly errorName?: string;
  readonly errorMessage?: string;
} {
  const cause: unknown = params.error.cause;

  const source =
    cause instanceof Error
      ? cause
      : typeof cause === "object" && cause !== null
        ? cause
        : params.error;

  const name = "name" in source ? source.name : undefined;
  const message = "message" in source ? source.message : undefined;

  return {
    ...(typeof name === "string" ? { errorName: name } : {}),
    ...(typeof message === "string"
      ? { errorMessage: message.slice(0, MAX_MESSAGE) }
      : {}),
  };
}

/**
 * Writes every workflow run that completes or fails on this compute to the
 * outbox (and, with `events`, to the block event stream). Call it from
 * `instrumentation.ts` inside the Node.js guard, once per process; it returns
 * the function that unregisters the hooks.
 *
 * The Workflow SDK reports only terminal transitions, so there is no
 * run-started or step event, and a run cancelled from the CLI or the dashboard
 * is not reported by this process. The hooks are fire-and-forget: nothing here
 * can delay or change a run's outcome, and a failed write is logged and dropped
 * (invariant 5). Treat the events as best effort: the SDK's event log stays the
 * system of record.
 *
 * ```ts
 * export async function register() {
 *   if (process.env.NEXT_RUNTIME === "nodejs") {
 *     const { registerWorkflowLifecycle } =
 *       await import("better-supabase/workflow-sdk");
 *     const { outbox, betterSupabase } =
 *       await import("./lib/supabase/server");
 *
 *     registerWorkflowLifecycle({ outbox, events: betterSupabase.events });
 *   }
 * }
 * ```
 */
export function registerWorkflowLifecycle(
  options: WorkflowLifecycleOptions,
): () => void {
  if (!options.outbox && !options.events) {
    throw new TypeError(
      "better-supabase: registerWorkflowLifecycle needs an outbox, events or both",
    );
  }

  const register = options.register ?? registerLifecycleHooks;
  const logger = options.logger ?? options.events?.logger ?? consoleLogger;
  const source = options.source ?? "better-supabase/workflow-sdk";

  const report = async (
    transition: "run_completed" | "run_failed",
    data: WorkflowSdkRunEventData,
  ): Promise<void> => {
    if (options.workflows && !options.workflows(data.workflowName)) {
      return;
    }

    const type = `workflow_sdk.${transition}` as const;
    const subject = `workflow_runs/${data.runId}`;

    if (options.events) {
      try {
        emitBlockEvent<WorkflowSdkEvents>(options.events, type, data, {
          subject,
        });
      } catch (cause) {
        logger.error(`${type} block event threw`, { cause });
      }
    }

    if (!options.outbox) {
      return;
    }

    try {
      const result = await options.outbox.emit({
        type,
        payload: data,
        subject,
        key: `${data.runId}:${transition}`,
        source,
      });

      if (!result.ok) {
        logger.error(`${type} outbox write failed`, { cause: result.error });
      }
    } catch (cause) {
      logger.error(`${type} outbox write threw`, { cause });
    }
  };

  return register({
    onRunCompleted: (params: RunCompletedHookParams) =>
      report("run_completed", {
        runId: params.run.runId,
        workflowName: params.workflowName,
      }),
    onRunFailed: (params: RunFailedHookParams) =>
      report("run_failed", {
        runId: params.run.runId,
        workflowName: params.workflowName,
        ...(params.error.errorCode === undefined
          ? {}
          : { errorCode: params.error.errorCode }),
        ...failure(params),
      }),
  });
}
