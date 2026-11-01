import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { DbError } from "./errors.ts";
import type { Result } from "./result.ts";

import { dbError } from "./errors.ts";
import { err } from "./result.ts";

/**
 * A reference to an action (ADR 0046): a kind a registered action handles and
 * its settings, such as `{ kind: "notify", config: { type: "task.assigned" }
 * }`. Automations, workflows and sequences store actions in this shape.
 */
export interface ActionRef {
  /** Such as `notify`, `approvals.request` or `tasks.from_conversation`. */
  readonly kind: string;
  readonly config?: Readonly<Record<string, unknown>>;
}

/** What started an action: an automation, a workflow step or a sequence step. */
export interface ActionOrigin {
  readonly type: "automation" | "workflow" | "sequence";
  /** The automation, workflow run or sequence enrollment id. */
  readonly id: string;
  /** Its name, for messages and notification data. */
  readonly name: string;
  /** The outbox event type that started it, when one did. */
  readonly trigger?: string;
}

/** The record an action works on, and the event it runs for. */
export interface ActionContext {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The event's payload or the record, such as the expense row. */
  readonly payload?: Readonly<Record<string, unknown>>;
  /** The outbox event the action runs for; it keys retries of the action. */
  readonly eventId?: string;
}

/** What an action's `run` receives. */
export interface ActionCall {
  readonly action: ActionRef;
  readonly origin: ActionOrigin;
  readonly context: ActionContext;
  /**
   * The same for every retry of this action for this event, such as
   * `rule:<automation id>:notify:<event id>`. Pass it on as an idempotency
   * key.
   */
  readonly key: string;
}

/** Runs one action. Return a `Result`; a throw becomes an `unexpected` error. */
export type ActionHandler = (
  call: ActionCall,
) => Result<unknown> | PromiseLike<Result<unknown>>;

/** What `defineAction` takes. */
export interface ActionSpec {
  /** Unique in a registry, such as `notify` or `tasks.from_conversation`. */
  readonly kind: string;
  /** A short label for the automation editor. */
  readonly title: string;
  readonly description?: string;
  /**
   * Checks `config` before `run`: a failing config is a `validation` error and
   * `run` doesn't run.
   */
  readonly config?: StandardSchemaV1;
  readonly run: ActionHandler;
}

/** An action from `defineAction` (`apiVersion: 1`). */
export interface Action extends ActionSpec {
  readonly apiVersion: 1;
}

/** What a registry lists for the automation editor. */
export interface ActionInfo {
  readonly kind: string;
  readonly title: string;
  readonly description?: string;
}

/**
 * A block's catalog entry for an action it ships (`defineBlock({ actions })`):
 * the kind and its label. The block's TypeScript side exports the factory that
 * builds the runnable action.
 */
export type ActionDescriptor = ActionInfo;

/**
 * Declares an action the action registry runs for automations, workflow steps
 * and sequence steps.
 */
export function defineAction(spec: ActionSpec): Action {
  return { ...spec, apiVersion: 1 };
}

/** The actions automations, workflows and sequences run, by kind. */
export interface ActionRegistry {
  /** The registered actions, for the automation editor. */
  kinds(): readonly ActionInfo[];
  has(kind: string): boolean;
  /**
   * Runs the action the call names. A kind with no action is an
   * `invalid_request` error with the hint `ACTION_UNKNOWN`.
   */
  run(call: ActionCall): Promise<Result<unknown>>;
}

function errorText(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause);
}

function configError(
  kind: string,
  issues: readonly StandardSchemaV1.Issue[],
): DbError {
  return dbError("validation", `The ${kind} action's config is invalid`, {
    hint: "ACTION_CONFIG_INVALID",
    issues: issues.map((issue) => ({
      message: issue.message,
      ...(issue.path === undefined
        ? {}
        : {
            path: issue.path.map((part) =>
              typeof part === "object" ? part.key : part,
            ),
          }),
    })),
  });
}

/**
 * One registry over the actions of every installed block, for the automation
 * dispatcher, the workflow editor's action steps and sequence action steps.
 *
 * ```ts
 * const actions = createActionRegistry([
 *   notifyAction(blocks.notifications),
 *   taskFromConversationAction({ clients }),
 * ]);
 * ```
 */
export function createActionRegistry(
  actions: readonly Action[],
): ActionRegistry {
  const byKind = new Map<string, Action>();

  for (const action of actions) {
    const version: number = action.apiVersion;

    if (version !== 1) {
      throw new TypeError(
        `The ${action.kind} action has apiVersion ${String(version)}; this release reads 1`,
      );
    }

    if (byKind.has(action.kind)) {
      throw new TypeError(`Two actions handle the kind ${action.kind}`);
    }

    byKind.set(action.kind, action);
  }

  return {
    kinds: () =>
      [...byKind.values()].map((action) => ({
        kind: action.kind,
        title: action.title,
        ...(action.description === undefined
          ? {}
          : { description: action.description }),
      })),
    has: (kind) => byKind.has(kind),
    run: async (call) => {
      const action = byKind.get(call.action.kind);

      if (action === undefined) {
        return err(
          dbError(
            "invalid_request",
            `No action handles the kind "${call.action.kind}"`,
            { hint: "ACTION_UNKNOWN" },
          ),
        );
      }

      try {
        if (action.config !== undefined) {
          const checked = await action.config["~standard"].validate(
            call.action.config ?? {},
          );

          if (checked.issues !== undefined) {
            return err(configError(action.kind, checked.issues));
          }
        }

        return await action.run(call);
      } catch (cause) {
        return err(dbError("unexpected", errorText(cause)));
      }
    },
  };
}

/**
 * An automation a block ships (`defineBlock({ automations })`). Its SQL module
 * writes the row to `automation_defaults`, and every organization gets its own
 * copy the first time its rules run or are listed, which it may turn off or
 * edit.
 */
export interface DefaultAutomation {
  /** Unique across blocks, such as `inbox.conversation_to_task`. */
  readonly key: string;
  readonly name: string;
  readonly description?: string;
  /** The outbox event type that starts it, with the default names. */
  readonly trigger: string;
  /** The record type the trigger event is about, with the default names. */
  readonly subjectType: string;
  readonly actions: readonly ActionRef[];
  /** Default true. An automation that needs app code ships turned off. */
  readonly enabled?: boolean;
  /** Blocks that must be installed for the block to ship it. */
  readonly requires?: readonly string[];
}

/**
 * A timer a block runs on the queue (`defineBlock({ schedules })`): the queue
 * block's `blockSchedules` enqueues a `block_ticks` job at each `cron` time,
 * and the handler the app registers for `<block>.<name>` does the due work,
 * such as `sla.check()` or `sequences.runDue()`.
 */
export interface BlockSchedule {
  /** Unique within the block, such as `check`. */
  readonly name: string;
  /** Five cron fields, a macro such as `@hourly` or an interval (`1 minute`). */
  readonly cron: string;
  /** The client method the handler calls, for the checklist and the docs. */
  readonly runs: string;
  readonly description: string;
}

/**
 * A key for one action of one origin for one event, the same on every retry of
 * the event.
 */
export function actionKey(
  origin: ActionOrigin,
  kind: string,
  context: ActionContext,
): string {
  return `${origin.type === "automation" ? "rule" : origin.type}:${origin.id}:${kind}:${context.eventId ?? `${context.subjectType}/${context.subjectId}`}`;
}
