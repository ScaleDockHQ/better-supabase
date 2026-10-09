import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { JobHandler } from "../jobs/queue.ts";

import { DbException, dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { nowInstant } from "../../core/temporal.ts";
import { assertCron, nextCronRun } from "../jobs/cron.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  errorText,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
} from "../shared.ts";

export type AiTaskRunStatus = "queued" | "running" | "succeeded" | "failed";

export interface AiTaskRun {
  readonly id: string;
  readonly taskId: string;
  readonly organizationId: string;
  readonly userId: string;
  readonly status: AiTaskRunStatus;
  readonly scheduledFor: Temporal.Instant;
  readonly chatId: string | undefined;
  readonly error: string | undefined;
  readonly startedAt: Temporal.Instant | undefined;
  readonly finishedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface AiTask {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string;
  /** The chat each run writes to; the first run's chat when unset. */
  readonly chatId: string | undefined;
  readonly agentId: string | undefined;
  readonly title: string;
  readonly prompt: string;
  /** Five-field cron or an interval such as `30 minutes`. */
  readonly cron: string;
  /** An IANA time zone the cron runs in. */
  readonly timezone: string;
  readonly enabled: boolean;
  readonly nextRunAt: Temporal.Instant | undefined;
  readonly lastRunAt: Temporal.Instant | undefined;
  /** Only `list` sets it. */
  readonly lastRun: AiTaskRun | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AiTaskFields {
  readonly title?: string;
  readonly prompt?: string;
  readonly cron?: string;
  readonly timezone?: string;
  readonly chatId?: string | null;
  readonly agentId?: string | null;
}

export type NewAiTask = AiTaskFields & {
  readonly title: string;
  readonly prompt: string;
  readonly cron: string;
};

/**
 * Runs one occurrence of a task, as the task's user: sends the prompt to the
 * assistant and returns the chat it wrote to. A throw fails the run.
 */
export type AiTaskRunner = (
  task: AiTask,
  run: AiTaskRun,
  signal: AbortSignal,
) => Promise<{ readonly chatId?: string } | void>;

export interface AiTaskOutcome {
  readonly task: AiTask;
  readonly run: AiTaskRun;
  readonly ok: boolean;
  readonly error?: string;
  readonly chatId?: string;
}

export interface AiTasksOptions extends BlockTemporalOptions {
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /** Calls as the service role, for `tick`, `execute` and `runJob`. */
  readonly service?: BlockTransport;
  /** The module schema (`sql.modules.ai-tasks.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  readonly run?: AiTaskRunner;
  /** Called after each run finishes, to notify the task's user. */
  readonly notify?: (outcome: AiTaskOutcome) => unknown;
  /** The clock, for tests. */
  readonly now?: () => Temporal.Instant;
}

export interface AiTasks {
  create(organizationId: string, task: NewAiTask): AsyncResult<AiTask>;
  update(
    organizationId: string,
    taskId: string,
    fields: AiTaskFields,
  ): AsyncResult<AiTask>;
  pause(organizationId: string, taskId: string): AsyncResult<AiTask>;
  /** Enables a task again; it runs at its next occurrence. */
  resume(organizationId: string, taskId: string): AsyncResult<AiTask>;
  remove(taskId: string): AsyncResult<boolean>;
  /** The caller's tasks, or every task in the tenant with `all` and `ai_chat.admin`. */
  list(
    organizationId: string,
    options?: { readonly all?: boolean },
  ): AsyncResult<readonly AiTask[]>;
  runs(
    taskId: string,
    options?: { readonly limit?: number },
  ): AsyncResult<readonly AiTaskRun[]>;
  /**
   * Claims due tasks (service role): queues a run for each, which the
   * `ai_task_run` queue picks up when jobs is installed, and computes the
   * next occurrence of every task that needs one. Returns the queued runs.
   */
  tick(options?: {
    readonly batch?: number;
  }): AsyncResult<readonly AiTaskRun[]>;
  /** Starts, runs and finishes a queued run (service role). `false` when another worker has it. */
  execute(
    runId: string,
    options?: { readonly signal?: AbortSignal },
  ): AsyncResult<boolean>;
  /** The handler for the `ai_task_run` queue. */
  runJob(): JobHandler<{ readonly run_id: string }>;
  /**
   * `tick` then `execute` each run in turn, without a queue. Returns how many
   * ran. A failed run does not stop the others; when any failed, the result
   * is the first error, with every failed run listed in `details`.
   */
  drain(options?: {
    readonly batch?: number;
    readonly signal?: AbortSignal;
  }): AsyncResult<number>;
}

const STATUSES: ReadonlySet<string> = new Set([
  "queued",
  "running",
  "succeeded",
  "failed",
]);

const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

function runOf(value: unknown): AiTaskRun {
  const row = recordOf(value, "ai_task_runs");
  const status = textOf(row["status"]);
  return {
    id: textOf(row["id"]),
    taskId: textOf(row["task_id"]),
    organizationId: textOf(row["organization_id"]),
    userId: textOf(row["user_id"]),
    // SAFETY: STATUSES holds exactly the AiTaskRunStatus members.
    status: STATUSES.has(status) ? (status as AiTaskRunStatus) : "failed",
    scheduledFor: instant(row["scheduled_for"]),
    chatId: optionalText(row["chat_id"]),
    error: optionalText(row["error"]),
    startedAt: optionalInstant(row["started_at"]),
    finishedAt: optionalInstant(row["finished_at"]),
    createdAt: instant(row["created_at"]),
  };
}

function taskOf(value: unknown): AiTask {
  const row = recordOf(value, "ai_scheduled_tasks");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    userId: textOf(row["user_id"]),
    chatId: optionalText(row["chat_id"]),
    agentId: optionalText(row["agent_id"]),
    title: textOf(row["title"]),
    prompt: textOf(row["prompt"]),
    cron: textOf(row["cron"]),
    timezone: textOf(row["timezone"]),
    enabled: row["enabled"] !== false,
    nextRunAt: optionalInstant(row["next_run_at"]),
    lastRunAt: optionalInstant(row["last_run_at"]),
    lastRun: isRecord(row["last_run"]) ? runOf(row["last_run"]) : undefined,
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

const invalid = (message: string): DbError =>
  dbError("invalid_input", message, { hint: "AI_TASK_INVALID" });

function fieldsArg(fields: AiTaskFields): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (fields.title !== undefined) out["title"] = fields.title;
  if (fields.prompt !== undefined) out["prompt"] = fields.prompt;
  if (fields.cron !== undefined) out["cron"] = fields.cron;
  if (fields.timezone !== undefined) out["timezone"] = fields.timezone;
  if (fields.chatId !== undefined) out["chat_id"] = fields.chatId;
  if (fields.agentId !== undefined) out["agent_id"] = fields.agentId;
  return out;
}

/** Prompts users schedule on a cron, and the scheduler that runs them. */
export function createAiTasks(options: AiTasksOptions): AiTasks {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const now = options.now ?? nowInstant;

  /** The next occurrence, or an `invalid_input` error for a bad cron or zone. */
  const next = (cron: string, timezone: string): Result<Temporal.Instant> => {
    try {
      assertCron(cron);
      return ok(nextCronRun(cron, timezone, now()));
    } catch (cause) {
      return err(invalid(errorText(cause)));
    }
  };

  const save = (
    organizationId: string,
    taskId: string | undefined,
    fields: AiTaskFields & { readonly enabled?: boolean },
    nextRunAt: Temporal.Instant | undefined,
  ): AsyncResult<AiTask> => {
    const args: Record<string, unknown> = fieldsArg(fields);
    if (fields.enabled !== undefined) args["enabled"] = fields.enabled;
    return call(
      "save_ai_task",
      {
        tenant: organizationId,
        id: taskId,
        fields: args,
        next_run_at: nextRunAt?.toString(),
      },
      taskOf,
    ).andThen((task) => scheduleNow(task));
  };

  // save_ai_task ignores next_run_at from users; with a service transport the
  // next occurrence is set right away instead of on the next tick.
  const scheduleNow = (task: AiTask): AsyncResult<AiTask> => {
    if (
      options.service === undefined ||
      !task.enabled ||
      task.nextRunAt !== undefined
    ) {
      return AsyncResult.ok(task);
    }
    const upcoming = next(task.cron, task.timezone);
    if (!upcoming.ok) return AsyncResult.ok(task);
    return service(
      "schedule_ai_tasks",
      {
        items: {
          items: [{ id: task.id, next_run_at: upcoming.data.toString() }],
        },
      },
      (count) => (count === 1 ? { ...task, nextRunAt: upcoming.data } : task),
    );
  };

  const schedule = (
    fields: AiTaskFields,
    fallbackZone: string | undefined,
  ): AsyncResult<Temporal.Instant | undefined> => {
    if (fields.cron === undefined && fields.timezone === undefined) {
      return AsyncResult.ok(undefined);
    }
    if (fields.cron === undefined) {
      return AsyncResult.err(invalid("change cron together with timezone"));
    }
    const result = next(fields.cron, fields.timezone ?? fallbackZone ?? "UTC");
    return result.ok
      ? AsyncResult.ok(result.data)
      : AsyncResult.err(result.error);
  };

  const tick = (
    tickOptions: { readonly batch?: number } = {},
  ): AsyncResult<readonly AiTaskRun[]> =>
    service("claim_due_ai_tasks", { batch: tickOptions.batch }, (value) =>
      recordOf(value, "claim_due_ai_tasks"),
    ).andThen((claimed) => {
      const runs = recordsOf(claimed["runs"], "claim_due_ai_tasks").map(runOf);
      const items = recordsOf(claimed["unscheduled"], "claim_due_ai_tasks").map(
        (row) => {
          const result = next(textOf(row["cron"]), textOf(row["timezone"]));
          return {
            id: textOf(row["id"]),
            // A task whose cron no longer parses waits a day instead of looping.
            next_run_at: (result.ok
              ? result.data
              : now().add({ hours: 24 })
            ).toString(),
          };
        },
      );
      return items.length === 0
        ? AsyncResult.ok(runs)
        : service("schedule_ai_tasks", { items: { items } }, () => runs);
    });

  const execute = (
    runId: string,
    executeOptions: { readonly signal?: AbortSignal } = {},
  ): AsyncResult<boolean> =>
    service("start_ai_task_run", { id: runId }, (value) => value).andThen(
      (value) =>
        AsyncResult.from(async () => {
          if (!isRecord(value)) return ok(false);
          const run = runOf(value);
          const task = taskOf(value["task"]);
          const runner = options.run;
          let outcome: AiTaskOutcome;
          if (runner === undefined) {
            outcome = {
              task,
              run,
              ok: false,
              error: "createAiTasks has no run",
            };
          } else {
            try {
              const result = await runner(
                task,
                run,
                executeOptions.signal ?? new AbortController().signal,
              );
              outcome =
                result?.chatId === undefined
                  ? { task, run, ok: true }
                  : { task, run, ok: true, chatId: result.chatId };
            } catch (cause) {
              outcome = { task, run, ok: false, error: errorText(cause) };
            }
          }
          const finished = await service(
            "finish_ai_task_run",
            {
              id: run.id,
              succeeded: outcome.ok,
              error: outcome.error,
              chat_id: outcome.chatId,
            },
            (done) => done === true,
          );
          if (!finished.ok) return finished;
          await options.notify?.(outcome);
          return ok(true);
        }),
    );

  return {
    create: (organizationId, task) =>
      schedule(task, task.timezone).andThen((nextRunAt) =>
        save(organizationId, undefined, task, nextRunAt),
      ),
    update: (organizationId, taskId, fields) =>
      schedule(fields, fields.timezone).andThen((nextRunAt) =>
        save(organizationId, taskId, fields, nextRunAt),
      ),
    pause: (organizationId, taskId) =>
      save(organizationId, taskId, { enabled: false }, undefined),
    resume: (organizationId, taskId) =>
      save(organizationId, taskId, { enabled: true }, undefined),
    remove: (taskId) =>
      call("delete_ai_task", { id: taskId }, (value) => value === true),
    list: (organizationId, listOptions = {}) =>
      call(
        "list_ai_tasks",
        { tenant: organizationId, mine: listOptions.all !== true },
        (value) => recordsOf(value, "list_ai_tasks").map(taskOf),
      ),
    runs: (taskId, runsOptions = {}) =>
      call(
        "list_ai_task_runs",
        { task_id: taskId, max_rows: runsOptions.limit },
        (value) => recordsOf(value, "list_ai_task_runs").map(runOf),
      ),
    tick,
    execute,
    runJob: () => async (payload, _job, signal) => {
      const result = await execute(payload.run_id, { signal });
      if (!result.ok) throw new DbException(result.error);
    },
    drain: (drainOptions = {}) =>
      tick(drainOptions).andThen((runs) =>
        AsyncResult.from(async (): Promise<Result<number>> => {
          let done = 0;
          const failures: {
            readonly runId: string;
            readonly error: DbError;
          }[] = [];
          for (const run of runs) {
            if (drainOptions.signal?.aborted) break;
            const result = await execute(run.id, drainOptions);
            if (!result.ok)
              failures.push({ runId: run.id, error: result.error });
            else if (result.data) done += 1;
          }
          const [first] = failures;
          if (first === undefined) return ok(done);
          return err({
            ...first.error,
            details: `${failures.length} of ${runs.length} runs failed: ${failures
              .map((failure) => `${failure.runId} (${failure.error.message})`)
              .join(", ")}`,
          });
        }),
      ),
  };
}
