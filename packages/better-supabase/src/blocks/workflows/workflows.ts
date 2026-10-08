import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";

import { type AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { assertCron, nextCronRun } from "../jobs/cron.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  errorText,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  seconds,
  textOf,
} from "../shared.ts";

export type WorkflowRunStatus =
  | "queued"
  | "running"
  | "waiting"
  | "completed"
  | "failed"
  | "cancelled";

/** A run of any engine, as the `workflows` module records it. */
export interface WorkflowRun {
  readonly id: string;
  /** The engine that runs it, e.g. `workflow-sdk`. */
  readonly engine: string;
  /** The engine's id for the run. */
  readonly externalId: string;
  /** The workflow it runs. */
  readonly definition: string;
  readonly tenant: string | undefined;
  readonly actor: string | undefined;
  readonly status: WorkflowRunStatus;
  readonly attributes: Readonly<Record<string, unknown>>;
  readonly error: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly startedAt: Temporal.Instant | undefined;
  readonly completedAt: Temporal.Instant | undefined;
  readonly cancelRequestedAt: Temporal.Instant | undefined;
}

export interface WorkflowSchedule {
  readonly id: string;
  readonly tenant: string | undefined;
  readonly name: string;
  readonly workflow: string;
  readonly input: unknown;
  readonly cron: string;
  readonly timezone: string;
  readonly nextRunAt: Temporal.Instant;
  readonly lastRunAt: Temporal.Instant | undefined;
  readonly paused: boolean;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface WorkflowRunsQuery {
  readonly tenant?: string;
  readonly definition?: string;
  readonly status?: WorkflowRunStatus;
  /** At most this many runs, newest first (default 50, at most 500). */
  readonly limit?: number;
  /** Runs created before this instant, for the next page. */
  readonly before?: Temporal.Instant;
}

/** What an engine reports about a run (service role). */
export interface WorkflowRunRecord {
  readonly engine: string;
  readonly externalId: string;
  readonly definition: string;
  readonly status: WorkflowRunStatus;
  readonly tenant?: string;
  readonly actor?: string;
  readonly attributes?: Readonly<Record<string, unknown>>;
  readonly error?: string;
  readonly startedAt?: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
}

export interface WorkflowScheduleInput {
  /** Unique per tenant: creating it again replaces it. */
  readonly name: string;
  readonly workflow: string;
  /** Five cron fields, a macro such as `@daily`, or an interval such as `30 seconds`. */
  readonly cron: string;
  /** IANA time zone the cron fields are read in (default `UTC`). */
  readonly timezone?: string;
  /** The workflow's arguments. */
  readonly input?: unknown;
  readonly tenant?: string;
}

/** One start the tick asks the engine for. */
export interface WorkflowStartCall {
  readonly workflow: string;
  readonly input: unknown;
  readonly tenant: string | undefined;
  readonly actor: string | undefined;
  /** Pass to the engine so a repeated tick doesn't start the run twice. */
  readonly idempotencyKey: string;
}

/** Starts a run and returns the engine's run id. */
export type WorkflowStarter = (call: WorkflowStartCall) => Promise<string>;

export interface WorkflowTickOptions {
  readonly start: WorkflowStarter;
  /** Seconds a claimed row stays leased (default 60). */
  readonly lease?: number;
  readonly batch?: number;
}

export interface WorkflowTickResult {
  readonly started: number;
  /** The rows whose start threw; they run again once their lease ends. */
  readonly failed: readonly { readonly id: string; readonly error: string }[];
}

export interface WorkflowStartRequest {
  /** The admission key: runs with the same key share the limits below. */
  readonly key: string;
  readonly workflow: string;
  readonly input?: unknown;
  readonly tenant?: string;
  readonly actor?: string;
  /** At most this many runs with the key at once. */
  readonly concurrency?: number;
  /** Waits this many seconds and replaces a request with the key still waiting. */
  readonly debounce?: number;
  /** Drops the request while a run with the key is waiting or active. */
  readonly singleton?: boolean;
}

export interface WorkflowStartTicket {
  readonly id: string | undefined;
  readonly status: "pending" | "dropped";
}

export interface WorkflowsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.workflows.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Workflows {
  readonly runs: {
    /** The runs the caller may read, newest first. */
    list(query?: WorkflowRunsQuery): AsyncResult<readonly WorkflowRun[]>;
    /** A run by its id or its engine's id. */
    get(run: string): AsyncResult<WorkflowRun | undefined>;
    /**
     * Marks a run for cancellation: the actor, `workflow.admin` in its
     * tenant, or the service role. The engine does the cancelling.
     */
    requestCancel(run: string): AsyncResult<WorkflowRun | undefined>;
    /** Creates or updates a run (service role; engines call it). */
    record(run: WorkflowRunRecord): AsyncResult<string>;
    /** Deletes finished runs older than `olderThan` seconds (default 30 days). */
    purge(options?: {
      readonly olderThan?: number;
      readonly batch?: number;
    }): AsyncResult<number>;
  };
  readonly schedules: {
    /** Creates or replaces a schedule: the service role, or `workflow.admin` in its tenant. */
    create(input: WorkflowScheduleInput): AsyncResult<WorkflowSchedule>;
    list(tenant?: string): AsyncResult<readonly WorkflowSchedule[]>;
    pause(id: string, paused?: boolean): AsyncResult<boolean>;
    remove(id: string): AsyncResult<boolean>;
    /**
     * Starts every due schedule once (service role), with the idempotency
     * key `schedule:<id>:<fire time>`, then moves it to its next cron time
     * after now. Call it from a cron route or a job.
     */
    tick(options: WorkflowTickOptions): AsyncResult<WorkflowTickResult>;
  };
  readonly semaphores: {
    /** Takes one of `max` slots of `key` for `holder`, for `ttl` seconds (default 300). */
    acquire(
      key: string,
      holder: string,
      options: { readonly max: number; readonly ttl?: number },
    ): AsyncResult<boolean>;
    release(key: string, holder: string): AsyncResult<boolean>;
  };
  readonly admission: {
    /** Queues a start under its key's concurrency, debounce and singleton rules. */
    request(input: WorkflowStartRequest): AsyncResult<WorkflowStartTicket>;
    /** Starts the queued requests whose key has room (service role). */
    tick(options: WorkflowTickOptions): AsyncResult<WorkflowTickResult>;
  };
}

const STATUSES: ReadonlySet<string> = new Set<WorkflowRunStatus>([
  "queued",
  "running",
  "waiting",
  "completed",
  "failed",
  "cancelled",
]);

function statusOf(value: unknown): WorkflowRunStatus {
  const text = textOf(value);
  if (!STATUSES.has(text)) {
    throw new TypeError(`workflows: unknown run status "${text}"`);
  }
  // SAFETY: STATUSES holds exactly the WorkflowRunStatus members.
  return text as WorkflowRunStatus;
}

function instantOf(value: unknown, field: string): Temporal.Instant {
  const instant = optionalInstant(value);
  if (instant === undefined) {
    throw new TypeError(`workflows: ${field} is missing`);
  }
  return instant;
}

/** A run from the jsonb the module returns. */
export function workflowRunOf(row: Record<string, unknown>): WorkflowRun {
  const attributes = row["attributes"];
  return {
    id: textOf(row["id"]),
    engine: textOf(row["engine"]),
    externalId: textOf(row["externalId"]),
    definition: textOf(row["definition"]),
    tenant: optionalText(row["tenant"]),
    actor: optionalText(row["actor"]),
    status: statusOf(row["status"]),
    attributes: isRecord(attributes) ? attributes : {},
    error: optionalText(row["error"]),
    createdAt: instantOf(row["createdAt"], "createdAt"),
    updatedAt: instantOf(row["updatedAt"], "updatedAt"),
    startedAt: optionalInstant(row["startedAt"]),
    completedAt: optionalInstant(row["completedAt"]),
    cancelRequestedAt: optionalInstant(row["cancelRequestedAt"]),
  };
}

function scheduleOf(row: Record<string, unknown>): WorkflowSchedule {
  return {
    id: textOf(row["id"]),
    tenant: optionalText(row["tenant"]),
    name: textOf(row["name"]),
    workflow: textOf(row["workflow"]),
    input: row["input"],
    cron: textOf(row["cron"]),
    timezone: textOf(row["timezone"]),
    nextRunAt: instantOf(row["nextRunAt"], "nextRunAt"),
    lastRunAt: optionalInstant(row["lastRunAt"]),
    paused: row["paused"] === true,
    createdBy: optionalText(row["createdBy"]),
    createdAt: instantOf(row["createdAt"], "createdAt"),
  };
}

const optionalRun = (value: unknown): WorkflowRun | undefined =>
  isRecord(value) ? workflowRunOf(value) : undefined;

/**
 * The `workflows` module's runs, schedules, semaphores and start admission,
 * for any engine. Run with the user's transport to read what RLS allows;
 * the ticks and `record` need the service role.
 *
 * ```ts
 * const workflows = createWorkflows({ transport: rpcTransport(supabase) });
 * const runs = await workflows.runs.list({ tenant: orgId }).orThrow();
 * ```
 */
export function createWorkflows(options: WorkflowsOptions): Workflows {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const now = (): Temporal.Instant => temporal().Now.instant();

  const tick = (
    claimFn: string,
    options: WorkflowTickOptions,
    each: (row: Record<string, unknown>) => {
      readonly call: WorkflowStartCall;
      readonly done: (run: string) => AsyncResult<unknown>;
    },
  ): AsyncResult<WorkflowTickResult> =>
    call(
      claimFn,
      { lease: options.lease ?? 60, batch: options.batch ?? 50 },
      (value) => recordsOf(value, claimFn),
    ).andThen(async (rows) => {
      let started = 0;
      const failed: { id: string; error: string }[] = [];
      for (const row of rows) {
        const id = textOf(row["id"]);
        const step = each(row);
        try {
          const run = await options.start(step.call);
          const done = await step.done(run);
          if (!done.ok) return err(done.error);
          started += 1;
        } catch (cause) {
          failed.push({ id, error: errorText(cause) });
        }
      }
      return ok({ started, failed });
    });

  return {
    runs: {
      list: (query = {}) =>
        call(
          "workflow_runs_list",
          {
            tenant: query.tenant,
            definition: query.definition,
            status: query.status,
            max: query.limit,
            before: instantArg(query.before),
          },
          (value) => recordsOf(value, "workflow_runs_list").map(workflowRunOf),
        ),
      get: (run) => call("workflow_run_get", { run }, optionalRun),
      requestCancel: (run) =>
        call("request_workflow_cancel", { run }, optionalRun),
      record: (run) =>
        call(
          "record_workflow_run",
          {
            engine: run.engine,
            external_id: run.externalId,
            definition: run.definition,
            status: run.status,
            tenant: run.tenant,
            actor: run.actor,
            attributes: run.attributes,
            error: run.error,
            started_at: instantArg(run.startedAt),
            completed_at: instantArg(run.completedAt),
          },
          textOf,
        ),
      purge: (purge = {}) =>
        call(
          "purge_workflow_runs",
          {
            older_than:
              purge.olderThan === undefined
                ? undefined
                : seconds(purge.olderThan),
            batch: purge.batch,
          },
          Number,
        ),
    },
    schedules: {
      create: (input) => {
        const timezone = input.timezone ?? "UTC";
        assertCron(input.cron);
        return call(
          "create_workflow_schedule",
          {
            name: input.name,
            workflow: input.workflow,
            cron: input.cron,
            next_run: nextCronRun(input.cron, timezone, now()).toString(),
            payload: { input: input.input ?? [] },
            timezone,
            tenant: input.tenant,
          },
          (value) => scheduleOf(recordOf(value, "create_workflow_schedule")),
        );
      },
      list: (tenant) =>
        call("workflow_schedules_list", { tenant }, (value) =>
          recordsOf(value, "workflow_schedules_list").map(scheduleOf),
        ),
      pause: (id, paused = true) =>
        call(
          "pause_workflow_schedule",
          { schedule: id, paused },
          (value) => value === true,
        ),
      remove: (id) =>
        call(
          "remove_workflow_schedule",
          { schedule: id },
          (value) => value === true,
        ),
      tick: (tickOptions) =>
        tick("claim_due_workflow_schedules", tickOptions, (row) => {
          const schedule = scheduleOf(row);
          const fireAt = instantOf(row["fireAt"], "fireAt");
          const after =
            temporal().Instant.compare(fireAt, now()) > 0 ? fireAt : now();
          return {
            call: {
              workflow: schedule.workflow,
              input: schedule.input,
              tenant: schedule.tenant,
              actor: schedule.createdBy,
              idempotencyKey: `schedule:${schedule.id}:${fireAt.toString()}`,
            },
            done: () =>
              call(
                "advance_workflow_schedule",
                {
                  schedule: schedule.id,
                  fired: fireAt.toString(),
                  next_run: nextCronRun(
                    schedule.cron,
                    schedule.timezone,
                    after,
                  ).toString(),
                },
                (value) => value === true,
              ),
          };
        }),
    },
    semaphores: {
      acquire: (key, holder, semaphore) =>
        call(
          "acquire_workflow_semaphore",
          {
            key,
            holder,
            max: semaphore.max,
            ttl: seconds(semaphore.ttl ?? 300),
          },
          (value) => value === true,
        ),
      release: (key, holder) =>
        call(
          "release_workflow_semaphore",
          { key, holder },
          (value) => value === true,
        ),
    },
    admission: {
      request: (input) =>
        call(
          "request_workflow_start",
          {
            key: input.key,
            workflow: input.workflow,
            payload: { input: input.input ?? [] },
            tenant: input.tenant,
            actor: input.actor,
            concurrency: input.concurrency,
            debounce:
              input.debounce === undefined
                ? undefined
                : seconds(input.debounce),
            singleton: input.singleton,
          },
          (value) => {
            const row = recordOf(value, "request_workflow_start");
            return {
              id: optionalText(row["id"]),
              status: row["status"] === "dropped" ? "dropped" : "pending",
            };
          },
        ),
      tick: (tickOptions) =>
        tick("claim_workflow_start_requests", tickOptions, (row) => {
          const id = textOf(row["id"]);
          return {
            call: {
              workflow: textOf(row["workflow"]),
              input: row["input"],
              tenant: optionalText(row["tenant"]),
              actor: optionalText(row["actor"]),
              idempotencyKey: `admission:${id}`,
            },
            done: (run) =>
              call(
                "mark_workflow_start_request",
                { request: id, run },
                (value) => value === true,
              ),
          };
        }),
    },
  };
}
