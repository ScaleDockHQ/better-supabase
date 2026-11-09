import type { ExtraFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { RunState } from "../../core/run-state.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";

import { blockFields, extraFieldsArg } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { assertCron, nextCronRun } from "../../core/cron.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  errorText,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  seconds,
  textOf,
  pageOf,
} from "../shared.ts";

/** A workflow run's state, in the words ai-chat and ai-schedules runs share. */
export type WorkflowRunStatus = Exclude<RunState, "cancel_requested">;

/**
 * The record a run belongs to: a subject type from `config.subjects` and its
 * id.
 */
export interface WorkflowSubject {
  readonly type: string;
  readonly id: string;
}

/** Who a run's steps act as. */
export type WorkflowPrincipalKind =
  | "user"
  | "service_principal"
  | "system"
  | "external";

export interface WorkflowPrincipal {
  readonly kind: WorkflowPrincipalKind;
  /** The user's or service principal's id; absent for `system`. */
  readonly id: string | undefined;
}

/** `test` runs come from the builder's test button: no outbox events, no alerts. */
export type WorkflowRunMode = "live" | "test";

/** A run of any engine, as the `workflows` module records it. */
/** `F` is the extra run columns `options.fields` describes. */
export interface WorkflowRun<F extends object = Record<never, never>> {
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
  /** The record it was started on. */
  readonly subject: WorkflowSubject | undefined;
  /** Who its steps act as, when the engine reported it. */
  readonly principal: WorkflowPrincipal | undefined;
  readonly mode: WorkflowRunMode;
  /** The trigger node it started from, in a graph with several. */
  readonly triggerNode: string | undefined;
  /** The key a start claimed for the tenant; one run holds a key. */
  readonly idempotencyKey: string | undefined;
  /** Until when a process holds the run's dispatch lease. */
  readonly dispatchUntil: Temporal.Instant | undefined;
  /**
   * The extra columns the columns the app's schema files add adds, by database
   * name.
   */
  readonly fields: ExtraFields<F>;
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

export interface WorkflowRunsQuery extends CursorPageOptions<Temporal.Instant> {
  readonly tenant?: string;
  readonly definition?: string;
  readonly status?: WorkflowRunStatus;
  /** One record's runs. */
  readonly subject?: WorkflowSubject;
  /** `live` (the default), `test`, or `all`. */
  readonly mode?: WorkflowRunMode | "all";
  /** At most this many runs, newest first (default 50, at most 500). */
  readonly limit?: number;
  /** Runs created before this instant, for the next page. */
  readonly cursor?: Temporal.Instant;
}

/** What an engine reports about a run (service role). */
export interface WorkflowRunRecord<F extends object = Record<never, never>> {
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
  /** Kept from the first report that names one. */
  readonly subject?: WorkflowSubject;
  /** Kept from the first report that names one. */
  readonly principal?: WorkflowPrincipal;
  /** Set by the first report (default `live`). */
  readonly mode?: WorkflowRunMode;
  readonly triggerNode?: string;
  /**
   * One run per tenant and key: a second report with a key another run holds
   * returns that run's id and records nothing.
   */
  readonly idempotencyKey?: string;
  /** Values for the extra run columns, validated by `options.fields`. */
  readonly fields?: Readonly<Record<string, unknown>> & Partial<F>;
}

export interface WorkflowScheduleInput {
  /** Unique per tenant: creating it again replaces it. */
  readonly name: string;
  readonly workflow: string;
  /**
   * Five cron fields, a macro such as `@daily`, or an interval such as `30
   * seconds`.
   */
  readonly cron: string;
  /** IANA time zone the cron fields are read in (default `UTC`). */
  readonly timezone?: string;
  /** The workflow's arguments. */
  readonly input?: unknown;
  readonly tenant?: string;
}

/** One start the tick asks the engine for. */
export interface WorkflowStartCall {
  /** A due schedule or a queued admission request. */
  readonly source: "schedule" | "admission";
  readonly workflow: string;
  readonly input: unknown;
  readonly tenant: string | undefined;
  /**
   * The schedule's creator or the request's actor. For a schedule it is the
   * trigger, recorded for audit; the run needs a `runAs` publisher.
   */
  readonly actor: string | undefined;
  /** The record a queued request named. */
  readonly subject?: WorkflowSubject;
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
  /** The record the run belongs to. */
  readonly subject?: WorkflowSubject;
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

export interface WorkflowsOptions<
  S extends StandardSchemaV1 | undefined = StandardSchemaV1 | undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * `withBlockHooks` hooks around the methods of each group, such as a rule on
   * who may create a schedule: `{ schedules: { create: { before } } }`.
   */
  readonly hooks?: NoInfer<WorkflowsHooks<FieldsOf<S>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /**
   * A Standard Schema for the extra run columns `record` sets. A write the
   * schema rejects is a `validation` error and sends nothing.
   */
  readonly fields?: S;
}

/** Hooks for the methods of each group of `Workflows`. */
export interface WorkflowsHooks<F extends object = Record<never, never>> {
  readonly runs?: BlockHooks<Workflows<F>["runs"]>;
  readonly schedules?: BlockHooks<Workflows<F>["schedules"]>;
  readonly semaphores?: BlockHooks<Workflows<F>["semaphores"]>;
  readonly admission?: BlockHooks<Workflows<F>["admission"]>;
}

/** `F` is the extra run columns `options.fields` describes. */
export interface Workflows<F extends object = Record<never, never>> {
  readonly runs: {
    /** The runs the caller may read, newest first. */
    list(query?: WorkflowRunsQuery): AsyncResult<readonly WorkflowRun<F>[]>;
    /** A run by its id or its engine's id. */
    get(run: string): AsyncResult<WorkflowRun<F> | undefined>;
    /**
     * Marks a run for cancellation: the actor, `workflows.manage` in its
     * tenant, or the service role. The engine does the cancelling.
     */
    requestCancel(run: string): AsyncResult<WorkflowRun<F> | undefined>;
    /** Creates or updates a run (service role; engines call it). */
    record(run: WorkflowRunRecord<F>): AsyncResult<string>;
    /**
     * Leases a queued run that has no engine run yet for `lease` seconds
     * (default 60; service role). Resolves `undefined` when the run is gone,
     * already started, or leased by another caller.
     */
    claimForDispatch(input: {
      readonly run: string;
      readonly lease?: number;
    }): AsyncResult<WorkflowRun<F> | undefined>;
    /**
     * Records the engine's run id on a queued run and ends its lease (service
     * role). When the engine already reported the run, that row keeps its id
     * and takes the key.
     */
    setEngine(input: {
      readonly run: string;
      readonly engine: string;
      readonly externalId: string;
    }): AsyncResult<WorkflowRun<F> | undefined>;
    /** Deletes finished runs older than `olderThan` seconds (default 30 days). */
    purge(options?: {
      readonly olderThan?: number;
      readonly batch?: number;
    }): AsyncResult<number>;
  };
  readonly schedules: {
    /**
     * Creates or replaces a schedule: the service role, or `workflows.manage`
     * in its tenant.
     */
    create(input: WorkflowScheduleInput): AsyncResult<WorkflowSchedule>;
    list(
      tenant?: string,
      options?: { readonly limit?: number },
    ): AsyncResult<readonly WorkflowSchedule[]>;
    pause(input: {
      id: string;
      paused?: boolean | undefined;
    }): AsyncResult<boolean>;
    remove(id: string): AsyncResult<boolean>;
    /**
     * Starts every due schedule once (service role), with the idempotency key
     * `schedule:<id>:<fire time>`, then moves it to its next cron time after
     * now. Call it from a cron route or a job.
     */
    tick(options: WorkflowTickOptions): AsyncResult<WorkflowTickResult>;
  };
  readonly semaphores: {
    /**
     * Takes one of `max` slots of `key` for `holder`, for `ttl` seconds
     * (default 300).
     */
    acquire(input: {
      key: string;
      holder: string;
      options: { readonly max: number; readonly ttl?: number };
    }): AsyncResult<boolean>;
    release(input: { key: string; holder: string }): AsyncResult<boolean>;
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

function isStatus(text: string): text is WorkflowRunStatus {
  return STATUSES.has(text);
}

/**
 * An engine may add statuses: an unknown one reads as `running`, never as
 * finished.
 */
function statusOf(value: unknown): WorkflowRunStatus {
  const text = textOf(value);

  return isStatus(text) ? text : "running";
}

const PRINCIPAL_KINDS: ReadonlySet<string> = new Set<WorkflowPrincipalKind>([
  "user",
  "service_principal",
  "system",
  "external",
]);

function isPrincipalKind(text: string): text is WorkflowPrincipalKind {
  return PRINCIPAL_KINDS.has(text);
}

/** The subject in `subjectType` and `subjectId`, when both are set. */
function workflowSubjectOf(
  row: Record<string, unknown>,
): WorkflowSubject | undefined {
  const type = optionalText(row["subjectType"]);
  const id = optionalText(row["subjectId"]);

  return type === undefined || id === undefined ? undefined : { type, id };
}

function principalOf(
  row: Record<string, unknown>,
): WorkflowPrincipal | undefined {
  const kind = textOf(row["principalKind"]);

  return isPrincipalKind(kind)
    ? { kind, id: optionalText(row["principalId"]) }
    : undefined;
}

/** A run from the jsonb the module returns, with its extra columns unparsed. */
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
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    startedAt: optionalInstant(row["startedAt"]),
    completedAt: optionalInstant(row["completedAt"]),
    cancelRequestedAt: optionalInstant(row["cancelRequestedAt"]),
    subject: workflowSubjectOf(row),
    principal: principalOf(row),
    mode: row["mode"] === "test" ? "test" : "live",
    triggerNode: optionalText(row["triggerNode"]),
    idempotencyKey: optionalText(row["idempotencyKey"]),
    dispatchUntil: optionalInstant(row["dispatchUntil"]),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
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
    nextRunAt: requiredInstant(row["nextRunAt"], "nextRunAt"),
    lastRunAt: optionalInstant(row["lastRunAt"]),
    paused: row["paused"] === true,
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

const subjectField = (
  subject: WorkflowSubject | undefined,
): { readonly subject?: WorkflowSubject } =>
  subject === undefined ? {} : { subject };

/**
 * The `workflows` module's runs, schedules, semaphores and start admission, for
 * any engine. Run with the user's transport to read what RLS allows; the ticks
 * and `record` need the service role.
 *
 * ```ts
 * const workflows = createWorkflows({ transport: rpcTransport(supabase) });
 * const runs = await workflows.runs.list({ tenant: orgId }).orThrow();
 * ```
 */
export function createWorkflows<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: WorkflowsOptions<S>): Workflows<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const now = (): Temporal.Instant => temporal().Now.instant();
  const fields = blockFields<F>(options.fields, "workflow run fields");

  const parsedRun = async (raw: Record<string, unknown>) => {
    const run = workflowRunOf(raw);
    const parsed = await fields.read(run.fields);

    if (!parsed.ok) {
      return parsed;
    }

    return ok<WorkflowRun<F>>({
      ...run,
      fields: { ...run.fields, ...parsed.data },
    });
  };

  const rawValue = (value: unknown): unknown => value;

  const optionalRun = (
    value: unknown,
  ): Promise<Result<WorkflowRun<F> | undefined>> =>
    isRecord(value) ? parsedRun(value) : Promise.resolve(ok(undefined));

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

          if (!done.ok) {
            return err(done.error);
          }

          started += 1;
        } catch (cause) {
          failed.push({ id, error: errorText(cause) });
        }
      }

      return ok({ started, failed });
    });

  const client: Workflows<F> = {
    runs: {
      list: (query = {}) =>
        call(
          "workflow_runs_list",
          {
            tenant: query.tenant,
            definition: query.definition,
            status: query.status,
            max: query.limit,
            before: instantArg(pageOf(query).cursor),
            subject_type: query.subject?.type,
            subject_id: query.subject?.id,
            mode: query.mode === "all" ? null : (query.mode ?? "live"),
          },
          (value) => recordsOf(value, "workflow_runs_list"),
        ).andThen(async (rows) => {
          const runs: WorkflowRun<F>[] = [];

          for (const row of rows) {
            const parsed = await parsedRun(row);

            if (!parsed.ok) {
              return parsed;
            }

            runs.push(parsed.data);
          }

          return ok(runs);
        }),
      get: (run) =>
        call("workflow_run_get", { run }, rawValue).andThen(optionalRun),
      requestCancel: (run) =>
        call("request_workflow_cancel", { run }, rawValue).andThen(optionalRun),
      claimForDispatch: ({ run, lease = 60 }) =>
        call("claim_workflow_run_dispatch", { run, lease }, rawValue).andThen(
          optionalRun,
        ),
      setEngine: ({ run, engine, externalId }) =>
        call(
          "set_workflow_run_engine",
          { run, engine, external_id: externalId },
          rawValue,
        ).andThen(optionalRun),
      record: (run) =>
        AsyncResult.from(() =>
          extraFieldsArg(fields, run.fields ?? {}),
        ).andThen((more) =>
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
              subject_type: run.subject?.type,
              subject_id: run.subject?.id,
              principal_kind: run.principal?.kind,
              principal_id: run.principal?.id,
              mode: run.mode,
              trigger_node: run.triggerNode,
              idempotency_key: run.idempotencyKey,
              ...more,
            },
            textOf,
          ),
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
      list: (tenant, options) =>
        call("workflow_schedules_list", { tenant }, (value) => {
          const rows = recordsOf(value, "workflow_schedules_list").map(
            scheduleOf,
          );

          return options?.limit === undefined
            ? rows
            : rows.slice(0, options.limit);
        }),
      pause: ({ id, paused = true }) =>
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
          const fireAt = requiredInstant(row["fireAt"], "fireAt");

          const after =
            temporal().Instant.compare(fireAt, now()) > 0 ? fireAt : now();

          return {
            call: {
              source: "schedule",
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
      acquire: ({ key, holder, options: semaphore }) =>
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
      release: ({ key, holder }) =>
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
            subject_type: input.subject?.type,
            subject_id: input.subject?.id,
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
              source: "admission",
              workflow: textOf(row["workflow"]),
              input: row["input"],
              tenant: optionalText(row["tenant"]),
              actor: optionalText(row["actor"]),
              ...subjectField(workflowSubjectOf(row)),
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

  const hooks = options.hooks ?? {};
  const logger = options.logger ? { logger: options.logger } : {};

  return {
    runs: withBlockHooks(client.runs, hooks.runs, {
      block: "workflows.runs",
      ...logger,
    }),
    schedules: withBlockHooks(client.schedules, hooks.schedules, {
      block: "workflows.schedules",
      ...logger,
    }),
    semaphores: withBlockHooks(client.semaphores, hooks.semaphores, {
      block: "workflows.semaphores",
      ...logger,
    }),
    admission: withBlockHooks(client.admission, hooks.admission, {
      block: "workflows.admission",
      ...logger,
    }),
  };
}
