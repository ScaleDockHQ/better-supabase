import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  CountOptions,
  FacetOptions,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { RunState } from "../../core/run-state.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { Notifier } from "../ports.ts";
import type { JobHandler } from "../queue/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import {
  allWithFields,
  blockFields,
  extraOf,
  withFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { assertCron, nextCronRun } from "../../core/cron.ts";
import {
  entityList,
  foundOrNotFound,
  tenantOrOption,
} from "../../core/entity-list.ts";
import { DbException, dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { runStateOf } from "../../core/run-state.ts";
import { nowInstant } from "../../core/temporal.ts";
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
  instantOf,
  injectableOf,
} from "../shared.ts";
import { taskListSurface } from "./lists.ts";

/** A task run's state, in the words ai-chat and workflow runs share. */
export type AiTaskRunStatus = Extract<
  RunState,
  "queued" | "running" | "completed" | "failed"
>;

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
  /**
   * The scheduler that runs the task. Unset or `ai-schedules` means this block
   * runs it; any other value is a mirror (see `mirror`).
   */
  readonly source?: string;
  /** The task's id in its source scheduler, for a mirror. */
  readonly externalId?: string;
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

/** Names a task in another scheduler. */
export interface MirroredAiTask {
  readonly organizationId: string;
  readonly source: string;
  readonly externalId: string;
}

export interface MirrorAiTask extends MirroredAiTask {
  /** The task's user, who is notified and owns its runs. */
  readonly userId: string;
  readonly task: NewAiTask & { readonly enabled?: boolean };
  readonly nextRunAt?: Temporal.Instant;
}

export interface RecordAiTaskRun extends MirroredAiTask {
  readonly scheduledFor: Temporal.Instant;
  readonly status: AiTaskRunStatus;
  readonly error?: string;
  readonly chatId?: string;
}

/**
 * Runs one occurrence of a task, as the task's user: sends the prompt to the
 * assistant and returns the chat it wrote to. A throw fails the run.
 */
export type AiTaskRunner = ((
  task: AiTask,
  run: AiTaskRun,
  signal: AbortSignal,
) => Promise<{ readonly chatId?: string } | void>) & {
  /** The runner contract version. Omitted means 1. */
  readonly apiVersion?: 1;
};

export interface AiTaskOutcome {
  readonly task: AiTask;
  readonly run: AiTaskRun;
  readonly ok: boolean;
  readonly error?: string;
  readonly chatId?: string;
}

export interface AiSchedulesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * A Standard Schema for the task columns the app adds (the columns your
   * schema files add), keyed by column name. It types and parses them on
   * `create`, `update`, `pause`, `resume` and `list`, and validates them on
   * `create` and `update`, which return a `validation` error for a bad value.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<AiSchedules<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /** Calls as the service role, for `tick`, `execute` and `runJob`. */
  readonly service?: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  readonly run?: AiTaskRunner;
  /**
   * Called after each run finishes, to notify the task's user. Defaults to
   * `notification` through `notifier`.
   */
  readonly notify?: (outcome: AiTaskOutcome) => unknown;
  /** The `notifier` port: the `notifications` block, from `createBlocks`. */
  readonly notifier?: Notifier;
  /**
   * The notification type `notifier` sends the task's user after each run. Its
   * data is `{ taskId, runId, ok, error?, chatId? }`.
   */
  readonly notification?: string;
  /** The clock, for tests. */
  readonly now?: () => Temporal.Instant;
}

/** `F` is the extra task fields `options.fields` describes. */
export interface AiSchedules<F extends object = Record<never, never>> {
  /** Keys besides the task's own are its extra columns. */
  create(input: {
    organizationId: string;
    task: NewAiTask & Partial<F>;
  }): AsyncResult<AiTask & F>;
  update(input: {
    organizationId: string;
    taskId: string;
    fields: AiTaskFields & Partial<F>;
  }): AsyncResult<AiTask & F>;
  pause(input: {
    organizationId: string;
    taskId: string;
  }): AsyncResult<AiTask & F>;
  /** Enables a task again; it runs at its next occurrence. */
  resume(input: {
    organizationId: string;
    taskId: string;
  }): AsyncResult<AiTask & F>;
  remove(taskId: string): AsyncResult<boolean>;
  /**
   * One keyset page of the caller's tasks, newest first. `filters` takes
   * `enabled` as a list and `all` (`["true"]` reads every task the caller can
   * see in the tenant); `q` searches the title and the prompt.
   */
  page(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<AiTask & F>>;
  /** The values of the `enabled` facet and how many tasks hold each. */
  facets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many tasks match the page's filters. */
  count(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
  /** One task by id with its last run, or a `not_found` error. */
  get(taskId: string): AsyncResult<AiTask & F>;
  /**
   * The caller's tasks, or every task in the tenant with `all` and
   * `ai_schedules.manage`.
   *
   * @deprecated Use `page`, which pages by keyset and takes `q`, sorts, array
   * filters and a count (ADR 1077).
   */
  list(
    input: { organizationId: string } & {
      readonly all?: boolean;
      readonly limit?: number;
    },
  ): AsyncResult<readonly (AiTask & F)[]>;
  runs(
    input: { taskId: string } & { readonly limit?: number },
  ): AsyncResult<readonly AiTaskRun[]>;
  /**
   * Claims due tasks (service role): queues a run for each, which the
   * `ai_task_run` queue picks up when jobs is installed, and computes the next
   * occurrence of every task that needs one. Returns the queued runs.
   */
  tick(options?: {
    readonly batch?: number;
  }): AsyncResult<readonly AiTaskRun[]>;
  /**
   * Starts, runs and finishes a queued run (service role). `false` when another
   * worker has it.
   */
  execute(
    input: { runId: string } & { readonly signal?: AbortSignal },
  ): AsyncResult<boolean>;
  /**
   * Stores a task that another scheduler runs, such as an eve schedule (service
   * role). It is keyed by `source` and `externalId`, and `tick` never claims
   * it, so this block does not run it twice. `source` may not be
   * `ai-schedules`. `nextRunAt` is the source's next occurrence.
   */
  mirror(input: MirrorAiTask): AsyncResult<AiTask>;
  /** Removes a mirrored task and its runs (service role). */
  unmirror(input: MirroredAiTask): AsyncResult<boolean>;
  /**
   * Records one occurrence of a mirrored task (service role). Calls with the
   * same `scheduledFor` update one run. A `not_found` error means the task is
   * not mirrored.
   */
  recordRun(input: RecordAiTaskRun): AsyncResult<AiTaskRun>;
  /** The handler for the `ai_task_run` queue. */
  runJob(): JobHandler<{ readonly run_id: string }>;
  /**
   * `tick` then `execute` each run in turn, without a queue. Returns how many
   * ran. A failed run does not stop the others; when any failed, the result is
   * the first error, with every failed run listed in `details`.
   */
  drain(options?: {
    readonly batch?: number;
    readonly signal?: AbortSignal;
  }): AsyncResult<number>;
}

const STATUSES: readonly AiTaskRunStatus[] = [
  "queued",
  "running",
  "completed",
  "failed",
];

function runOf(value: unknown): AiTaskRun {
  const row = recordOf(value, "ai_task_runs");

  return {
    id: textOf(row["id"]),
    taskId: textOf(row["task_id"]),
    organizationId: textOf(row["tenant_id"]),
    userId: textOf(row["user_id"]),
    status: runStateOf(row["status"], STATUSES, "failed"),
    scheduledFor: instantOf(row["scheduled_at"]),
    chatId: optionalText(row["chat_id"]),
    error: optionalText(row["error"]),
    startedAt: optionalInstant(row["started_at"]),
    finishedAt: optionalInstant(row["finished_at"]),
    createdAt: instantOf(row["created_at"]),
  };
}

function taskOf(value: unknown): AiTask {
  const row = recordOf(value, "ai_scheduled_tasks");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
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
    ...(typeof row["source"] === "string" ? { source: row["source"] } : {}),
    ...(typeof row["external_id"] === "string"
      ? { externalId: row["external_id"] }
      : {}),
    lastRun: isRecord(row["last_run"]) ? runOf(row["last_run"]) : undefined,
    createdAt: instantOf(row["created_at"]),
    updatedAt: instantOf(row["updated_at"]),
  };
}

const invalid = (message: string): DbError =>
  dbError("invalid_input", message, { hint: "AI_TASK_INVALID" });

const TASK_FIELDS: ReadonlySet<string> = new Set([
  "title",
  "prompt",
  "cron",
  "timezone",
  "chatId",
  "agentId",
  "enabled",
]);

function fieldsArg(fields: AiTaskFields): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  if (fields.title !== undefined) {
    out["title"] = fields.title;
  }

  if (fields.prompt !== undefined) {
    out["prompt"] = fields.prompt;
  }

  if (fields.cron !== undefined) {
    out["cron"] = fields.cron;
  }

  if (fields.timezone !== undefined) {
    out["timezone"] = fields.timezone;
  }

  if (fields.chatId !== undefined) {
    out["chat_id"] = fields.chatId;
  }

  if (fields.agentId !== undefined) {
    out["agent_id"] = fields.agentId;
  }

  return out;
}

/** Sends `notification` through `notifier` for each finished run. */
function notifyThrough(
  options: Pick<AiSchedulesOptions, "notifier" | "notification">,
): ((outcome: AiTaskOutcome) => unknown) | undefined {
  const { notifier, notification } = options;

  if (notifier === undefined || notification === undefined) {
    return undefined;
  }

  return (outcome) =>
    notifier.send({
      type: notification,
      input: {
        recipients: [outcome.task.userId],
        tenant: outcome.task.organizationId,
        key: `ai-task-run:${outcome.run.id}`,
        data: {
          taskId: outcome.task.id,
          runId: outcome.run.id,
          ok: outcome.ok,
          ...(outcome.error === undefined ? {} : { error: outcome.error }),
          ...(outcome.chatId === undefined ? {} : { chatId: outcome.chatId }),
        },
      },
    });
}

/** Prompts users schedule on a cron, and the scheduler that runs them. */
export function createAiSchedules<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: AiSchedulesOptions<S>): AiSchedules<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const fields: BlockFields<F> = blockFields(options.fields, "task fields");
  injectableOf("ai-schedules runner", options.run);
  const notify = options.notify ?? notifyThrough(options);
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
    task: AiTaskFields & { readonly enabled?: boolean },
    nextRunAt: Temporal.Instant | undefined,
  ): AsyncResult<AiTask & F> =>
    AsyncResult.from(() => fields.write(extraOf(task, TASK_FIELDS)))
      .andThen((extra) => {
        const args: Record<string, unknown> = { ...extra, ...fieldsArg(task) };

        if (task.enabled !== undefined) {
          args["enabled"] = task.enabled;
        }

        return call(
          "upsert_ai_task",
          {
            tenant: organizationId,
            id: taskId,
            fields: args,
            next_run_at: nextRunAt?.toString(),
          },
          (value) => value,
        );
      })
      .andThen((value) => withFields(fields, value, taskOf(value)))
      .andThen((saved) => scheduleNow(saved));

  // upsert_ai_task ignores next_run_at from users; with a service transport the
  // next occurrence is set right away instead of on the next tick.
  const scheduleNow = <T extends AiTask>(task: T): AsyncResult<T> => {
    if (
      options.service === undefined ||
      !task.enabled ||
      task.nextRunAt !== undefined
    ) {
      return AsyncResult.ok(task);
    }

    const upcoming = next(task.cron, task.timezone);

    if (!upcoming.ok) {
      return AsyncResult.ok(task);
    }

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

  const execute = ({
    runId,
    ...executeOptions
  }: { runId: string } & {
    readonly signal?: AbortSignal;
  }): AsyncResult<boolean> =>
    service("start_ai_task_run", { id: runId }, (value) => value).andThen(
      (value) =>
        AsyncResult.from(async () => {
          if (!isRecord(value)) {
            return ok(false);
          }

          const run = runOf(value);
          const task = taskOf(value["task"]);
          const runner = options.run;
          let outcome: AiTaskOutcome;

          if (runner === undefined) {
            outcome = {
              task,
              run,
              ok: false,
              error: "createAiSchedules has no run",
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

          if (!finished.ok) {
            return finished;
          }

          await notify?.(outcome);

          return ok(true);
        }),
    );

  const taskPages = entityList<
    readonly [unknown, AiTask],
    RequiredTenantOption
  >({
    entity: "ai_scheduled_task",
    surface: taskListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_ai_tasks",
    rowOf: (row) => [row, taskOf(row)] as const,
  });

  const client: AiSchedules<F> = {
    page: (pageOptions) =>
      taskPages
        .page(pageOptions)
        .andThen((page) =>
          AsyncResult.from(() => allWithFields(fields, page.items)).map(
            (items) => ({ ...page, items }),
          ),
        ),
    facets: taskPages.facets,
    count: taskPages.count,
    get: (taskId) =>
      call("get_ai_task", { id: taskId }, (value) => value ?? undefined)
        .andThen((row) => foundOrNotFound("ai_scheduled_task", row, taskId))
        .andThen((row) =>
          AsyncResult.from(() => withFields(fields, row, taskOf(row))),
        ),
    create: ({ organizationId, task }) =>
      schedule(task, task.timezone).andThen((nextRunAt) =>
        save(organizationId, undefined, task, nextRunAt),
      ),
    update: ({ organizationId, taskId, fields }) =>
      schedule(fields, fields.timezone).andThen((nextRunAt) =>
        save(organizationId, taskId, fields, nextRunAt),
      ),
    pause: ({ organizationId, taskId }) =>
      save(organizationId, taskId, { enabled: false }, undefined),
    resume: ({ organizationId, taskId }) =>
      save(organizationId, taskId, { enabled: true }, undefined),
    remove: (taskId) =>
      call("delete_ai_task", { id: taskId }, (value) => value === true),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
    list: ({ organizationId, limit, ...listOptions }) =>
      call(
        "list_ai_tasks",
        { tenant: organizationId, mine: listOptions.all !== true },
        (value) =>
          recordsOf(value, "list_ai_tasks").map(
            (raw) => [raw, taskOf(raw)] as const,
          ),
      )
        .andThen((rows) => allWithFields(fields, rows))
        .map((rows) => (limit === undefined ? rows : rows.slice(0, limit))),
    runs: ({ taskId, ...runsOptions }) =>
      call(
        "list_ai_task_runs",
        { task_id: taskId, max_rows: runsOptions.limit },
        (value) => recordsOf(value, "list_ai_task_runs").map(runOf),
      ),
    mirror: ({ organizationId, userId, source, externalId, task, nextRunAt }) =>
      service(
        "mirror_ai_task",
        {
          tenant: organizationId,
          user_id: userId,
          source,
          external_id: externalId,
          fields: { ...fieldsArg(task), enabled: task.enabled ?? true },
          next_run_at: nextRunAt?.toString(),
        },
        taskOf,
      ),
    unmirror: ({ organizationId, source, externalId }) =>
      service(
        "delete_mirrored_ai_task",
        { tenant: organizationId, source, external_id: externalId },
        (value) => value === true,
      ),
    recordRun: ({
      organizationId,
      source,
      externalId,
      scheduledFor,
      status,
      error,
      chatId,
    }) =>
      service(
        "record_ai_task_run",
        {
          tenant: organizationId,
          source,
          external_id: externalId,
          scheduled_for: scheduledFor.toString(),
          status,
          error,
          chat_id: chatId,
        },
        (value) => value ?? undefined,
      ).andThen((row) =>
        foundOrNotFound(
          "ai_scheduled_task",
          row === undefined ? undefined : runOf(row),
          externalId,
        ),
      ),
    tick,
    execute,
    runJob: () => async (payload, _job, signal) => {
      const result = await execute({ runId: payload.run_id, signal });

      if (!result.ok) {
        throw new DbException(result.error);
      }
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
            if (drainOptions.signal?.aborted) {
              break;
            }

            const result = await execute({ runId: run.id, ...drainOptions });

            if (!result.ok) {
              failures.push({ runId: run.id, error: result.error });
            } else if (result.data) {
              done += 1;
            }
          }

          const [first] = failures;

          if (first === undefined) {
            return ok(done);
          }

          return err({
            ...first.error,
            details: `${failures.length} of ${runs.length} runs failed: ${failures
              .map((failure) => `${failure.runId} (${failure.error.message})`)
              .join(", ")}`,
          });
        }),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "ai-schedules",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
