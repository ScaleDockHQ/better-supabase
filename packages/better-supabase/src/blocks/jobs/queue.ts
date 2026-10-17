import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BlockTransport } from "../../core/block-transport.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type {
  ClaimOptions,
  DrainResult,
  DrainRouteResult,
  EnqueueOptions,
  FailOptions,
  Job,
  JobHandler,
  Jobs,
  JobsOptions,
  QueueSchemas,
  RunSchedulesOptions,
  ScheduleOptions,
  WorkOptions,
} from "./types.ts";

import {
  blockCall,
  budget,
  leaseHeartbeat,
  type Budget,
} from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { tenantFrom, tenantPathsFor } from "../../core/claims.ts";
import { cronRoute } from "../../core/cron-route.ts";
import {
  dbError,
  type DbError,
  DbException,
  type ErrorMapper,
} from "../../core/errors.ts";
import { allTenantsContext } from "../../core/plugin.ts";
import {
  AsyncResult,
  err,
  ok,
  toDbError,
  type Result,
} from "../../core/result.ts";
import { validate } from "../../core/standard.ts";
import { temporal } from "../../core/temporal-required.ts";
import { nowInstant } from "../../core/temporal.ts";
import {
  applyTemporal,
  errorText,
  pageOf,
  run,
  seconds,
  sleep,
  toInstant,
} from "../shared.ts";
import {
  millis,
  pgmqPublicBackend,
  sqlOnly,
  sqlQueueBackend,
  transportQueueBackend,
  type QueueBackend,
  type QueueMessageRow,
  type QueueRpcClient,
  type QueueStats,
} from "./backends.ts";
import { nextCronRun } from "./cron.ts";
import { unwrap, wrapPayload } from "./envelope.ts";

/** Transient claim errors in a row a lane retries, with backoff, before the loop throws. */
const CLAIM_RETRIES = 3;

const TRANSIENT: ReadonlySet<DbError["kind"]> = new Set([
  "network",
  "timeout",
  "serialization",
  "rate_limited",
]);

function toJob(queue: string, row: QueueMessageRow): Job {
  const message = row.message ?? {};
  const { payload, context } = unwrap(message.payload);

  return {
    id: Number(row.id),
    queue,
    payload,
    context,
    attempts: row.attempts,
    maxAttempts: message.max_attempts ?? 5,
    enqueuedAt: toInstant(row.enqueued_at),
    visibleUntil: toInstant(row.visible_until),
    lastError: message.last_error ?? null,
  };
}

const QUEUE_NAME = /^[a-z_][a-z0-9_]{0,46}$/;

/** What `createJobs` stores jobs through. */
export type JobsSource =
  | SqlClient
  | QueueRpcClient
  | BlockTransport
  | QueueBackend;

/**
 * `transport` with every call made through `blockCall`, so a rejection is
 * mapped to a `DbError` (with the app's `mappers` first), as in every block.
 */
function mappedTransport(
  transport: BlockTransport,
  mappers: readonly ErrorMapper[] | undefined,
): BlockTransport {
  return {
    async call(schema, fn, args) {
      const result = await blockCall(transport, schema, mappers)(
        fn,
        args,
        (value) => value,
      );

      if (!result.ok) {
        throw new DbException(result.error);
      }

      return result.data;
    },
  };
}

function backendOf(
  options: Pick<
    JobsOptions,
    "backend" | "sql" | "client" | "transport" | "schema" | "mappers"
  >,
  now: () => Temporal.Instant,
): QueueBackend {
  if (options.backend) {
    return options.backend;
  }

  if (options.sql) {
    return sqlQueueBackend(options.sql, now);
  }

  if (options.client) {
    return pgmqPublicBackend(options.client);
  }

  if (options.transport) {
    return transportQueueBackend(
      mappedTransport(options.transport, options.mappers),
      { now, ...(options.schema ? { schema: options.schema } : {}) },
    );
  }

  throw new TypeError(
    "createJobs needs a backend, sql, client or transport to store jobs",
  );
}

const later = (a: Temporal.Instant, b: Temporal.Instant): Temporal.Instant =>
  temporal().Instant.compare(a, b) >= 0 ? a : b;

/**
 * Typed jobs on Supabase Queues (pgmq), over the `jobs` SQL module.
 *
 * Pass a service SQL connection (`postgres.admin`, `ctx.sql`) for the full
 * feature set, a service-role `rpcTransport` over the wrappers
 * `blocks.jobs.api` writes for the same features over the Data API, a
 * service-role Supabase client to go through the `pgmq_public` RPCs, or any
 * `QueueBackend`. Queue names are lowercase letters, digits and underscores.
 */
export function createJobs<const Q extends QueueSchemas>(
  options: JobsOptions<Q>,
): Jobs<Q> {
  applyTemporal(options);
  // SAFETY: without `queues` Q is the default, which `{}` satisfies.
  const queues = options.queues ?? ({} as Q);
  const now = options.now ?? nowInstant;

  for (const name of Object.keys(queues)) {
    if (!QUEUE_NAME.test(name)) {
      throw new TypeError(
        `Queue "${name}": pgmq queue names are lowercase letters, digits and underscores (at most 47)`,
      );
    }
  }

  const transport = backendOf(options, now);

  const schemaOf = (queue: string): StandardSchemaV1 => {
    const schema = queues[queue];

    if (!schema) {
      throw new TypeError(
        `Unknown queue "${queue}". Queues: ${Object.keys(queues).join(", ")}`,
      );
    }

    return schema;
  };

  const complete = (job: Job): AsyncResult<boolean> =>
    run(() => transport.complete(job));

  const fail = (
    job: Job,
    error: unknown,
    failOptions: FailOptions = {},
  ): AsyncResult<"queued" | "dead" | null> =>
    run(() => transport.fail(job, errorText(error), failOptions.retryIn));

  const claim = (
    queue: string,
    claimOptions: ClaimOptions = {},
  ): AsyncResult<Job[]> =>
    run(async () => {
      schemaOf(queue);

      const rows = await transport.read(
        queue,
        claimOptions.lease ?? 300,
        claimOptions.batch ?? 1,
      );

      return rows.map((row) => toJob(queue, row));
    });

  /**
   * Extends the lease of every job in `held` at half the lease, so jobs
   * waiting their turn in a claimed batch don't expire before they run.
   */
  const heartbeat = (
    held: ReadonlySet<Job>,
    lease: number,
  ): (() => void) | undefined =>
    transport.leases
      ? leaseHeartbeat(lease, () => {
          for (const job of held) {
            void run(() => transport.extend(job, lease));
          }
        })
      : undefined;

  const handle = async (
    job: Job,
    handler: JobHandler<unknown>,
    workOptions: WorkOptions,
  ): Promise<boolean> => {
    const controller = new AbortController();

    try {
      const payload = await validate(
        schemaOf(job.queue),
        job.payload,
        "payload",
      );

      if (!payload.ok) {
        await fail(job, payload.error.message);
        workOptions.onError?.(payload.error, job);

        return false;
      }

      const context =
        workOptions.allTenants && job.context.tenant === undefined
          ? allTenantsContext(job.context)
          : job.context;

      const outcome: unknown = await handler(
        payload.data,
        { ...job, payload: payload.data, context },
        controller.signal,
      );

      if (
        typeof outcome === "object" &&
        outcome !== null &&
        "ok" in outcome &&
        outcome.ok === false &&
        "error" in outcome
      ) {
        // SAFETY: the in check above proves outcome has an error field.
        throw (outcome as { error: unknown }).error;
      }

      await complete(job);

      return true;
    } catch (cause) {
      controller.abort();
      await fail(job, cause);
      // SAFETY: repositories only reject with DbError objects, which carry a kind field.
      workOptions.onError?.(
        typeof cause === "object" && cause !== null && "kind" in cause
          ? (cause as DbError)
          : toDbError(cause),
        job,
      );

      return false;
    }
  };

  const loop = async (
    queue: string,
    handler: JobHandler<unknown>,
    workOptions: WorkOptions,
    forever: boolean,
    spent: Budget = budget(undefined),
  ): Promise<DrainResult> => {
    const concurrency = Math.max(1, workOptions.concurrency ?? 1);
    const lease = workOptions.lease ?? 300;
    const firstWait = workOptions.pollInterval ?? 1000;
    const maxWait = Math.max(firstWait, workOptions.maxPollInterval ?? 30_000);
    let succeeded = 0;
    let failed = 0;
    // One lane's fatal claim error stops the others before the loop throws.
    const stop = new AbortController();

    const signal = workOptions.signal
      ? AbortSignal.any([workOptions.signal, stop.signal])
      : stop.signal;

    const lanes = Array.from({ length: concurrency }, async () => {
      let wait = firstWait;
      let misses = 0;

      while (!signal.aborted) {
        if (spent.expired()) {
          return;
        }

        const claimed = await claim(queue, {
          ...workOptions,
          batch: workOptions.batch ?? 1,
        });

        if (!claimed.ok) {
          misses += 1;

          if (misses > CLAIM_RETRIES || !TRANSIENT.has(claimed.error.kind)) {
            stop.abort();
            throw new TypeError(claimed.error.message, {
              cause: claimed.error,
            });
          }

          await sleep(
            Math.min(firstWait * 2 ** (misses - 1), spent.remaining()),
            signal,
          );
          continue;
        }

        misses = 0;

        if (claimed.data.length === 0) {
          if (!forever) {
            return;
          }

          await sleep(wait, signal);
          wait = Math.min(maxWait, wait * 2);
          continue;
        }

        wait = firstWait;
        const held = new Set(claimed.data);
        const stopHeartbeat = heartbeat(held, lease);

        try {
          for (const job of claimed.data) {
            if (await handle(job, handler, workOptions)) {
              succeeded += 1;
            } else {
              failed += 1;
            }

            held.delete(job);
          }
        } finally {
          stopHeartbeat?.();
        }
      }
    });

    const settled = await Promise.allSettled(lanes);

    for (const lane of settled) {
      if (lane.status === "rejected") {
        throw lane.reason;
      }
    }

    return { succeeded, failed };
  };

  const runSchedules = async (
    scheduleOptions: RunSchedulesOptions,
  ): Promise<number> => {
    if (!transport.dueSchedules || !transport.advanceSchedule) {
      return 0;
    }

    const due = await transport.dueSchedules(
      scheduleOptions.lease ?? 60,
      scheduleOptions.batch ?? 100,
    );

    let ran = 0;

    for (const schedule of due) {
      await transport.send(
        schedule.queue,
        schedule.payload,
        0,
        5,
        `schedule:${schedule.name}:${schedule.nextRun.toString()}`,
      );

      const next = millis(
        nextCronRun(
          schedule.cron,
          schedule.timeZone,
          later(now(), schedule.nextRun),
        ),
      );

      if (
        await transport.advanceSchedule(schedule.name, schedule.nextRun, next)
      ) {
        ran += 1;
      }
    }

    return ran;
  };

  interface PreparedSchedule {
    readonly name: string;
    readonly cron: string;
    readonly queue: string;
    readonly payload: unknown;
    readonly timeZone: string;
    readonly tenant: string | undefined;
  }

  const prepare = async (
    name: string,
    cron: string,
    queue: string,
    payload: unknown,
    scheduleOptions: ScheduleOptions,
    tenantDefault?: string,
  ): Promise<Result<PreparedSchedule>> => {
    const valid = await validate(schemaOf(queue), payload, "payload");

    if (!valid.ok) {
      return valid;
    }

    const timeZone = scheduleOptions.timeZone ?? "UTC";

    try {
      nextCronRun(cron, timeZone, now());
    } catch (cause) {
      return err(
        dbError("validation", errorText(cause), {
          issues: [{ message: errorText(cause), path: [name, "cron"] }],
        }),
      );
    }

    const wrapped = wrapPayload(valid.data, scheduleOptions.context);

    if (!wrapped.ok) {
      return wrapped;
    }

    return ok({
      name,
      cron,
      queue,
      payload: wrapped.data,
      timeZone,
      tenant:
        scheduleOptions.tenant ??
        (scheduleOptions.context
          ? tenantFrom(scheduleOptions.context, tenantPathsFor(undefined))
          : undefined) ??
        tenantDefault,
    });
  };

  const write = (prepared: PreparedSchedule): Promise<void> =>
    transport.schedule(
      prepared.name,
      prepared.cron,
      prepared.queue,
      prepared.payload,
      prepared.timeZone,
      millis(nextCronRun(prepared.cron, prepared.timeZone, now())),
      prepared.tenant,
    );

  const purge: Jobs<Q>["purge"] = (purgeOptions = {}) =>
    run(async () => {
      if (!transport.purge) {
        sqlOnly("purge");
      }

      const backendPurge = transport.purge.bind(transport);

      const interval = (value: number | string | undefined) =>
        value === undefined ? undefined : seconds(value);

      const counts = await Promise.all(
        (purgeOptions.queues ?? Object.keys(queues)).map((queue) => {
          schemaOf(queue);

          return backendPurge(queue, {
            olderThan: interval(purgeOptions.olderThan),
            deadOlderThan: interval(purgeOptions.deadOlderThan),
            batch: purgeOptions.batch,
          });
        }),
      );

      return counts.reduce((sum, count) => sum + count, 0);
    });

  const delayOf = (enqueueOptions: EnqueueOptions): Result<number> => {
    const delay = enqueueOptions.delay;

    if (delay !== undefined && (!Number.isInteger(delay) || delay < 0)) {
      return err(
        dbError("validation", "delay is a whole number of seconds", {
          issues: [
            { message: "Expected a non-negative integer", path: ["delay"] },
          ],
        }),
      );
    }

    return ok(
      delay ??
        (enqueueOptions.runAt
          ? Math.max(
              0,
              Math.ceil(
                (enqueueOptions.runAt.epochMilliseconds -
                  now().epochMilliseconds) /
                  1000,
              ),
            )
          : 0),
    );
  };

  /** The validated payload in its envelope, and the delay, for `enqueue` and `enqueueOnce`. */
  const prepareSend = async (
    queue: string,
    payload: unknown,
    enqueueOptions: EnqueueOptions,
  ): Promise<Result<{ message: unknown; delay: number }>> => {
    const valid = await validate(schemaOf(queue), payload, "payload");

    if (!valid.ok) {
      return valid;
    }

    const delay = delayOf(enqueueOptions);

    if (!delay.ok) {
      return delay;
    }

    const message = wrapPayload(valid.data, enqueueOptions.context, {
      ...(enqueueOptions.ticket === undefined
        ? {}
        : { ticket: enqueueOptions.ticket }),
    });

    if (!message.ok) {
      return message;
    }

    return ok({ message: message.data, delay: delay.data });
  };

  const client: Jobs<Q> = {
    enqueue(queue, payload, enqueueOptions = {}) {
      return AsyncResult.from(async () => {
        const prepared = await prepareSend(queue, payload, enqueueOptions);

        if (!prepared.ok) {
          return prepared;
        }

        const { message, delay } = prepared.data;

        return run(() =>
          transport.send(
            queue,
            message,
            delay,
            enqueueOptions.maxAttempts ?? 5,
            enqueueOptions.dedupeKey,
            enqueueOptions.dedupe,
          ),
        );
      });
    },
    enqueueOnce(queue, payload, enqueueOptions) {
      return AsyncResult.from(async () => {
        const prepared = await prepareSend(queue, payload, enqueueOptions);

        if (!prepared.ok) {
          return prepared;
        }

        const { message, delay } = prepared.data;

        return run(() => {
          if (!transport.sendOnce) {
            sqlOnly("enqueueOnce");
          }

          return transport.sendOnce(
            queue,
            message,
            delay,
            enqueueOptions.maxAttempts ?? 5,
            enqueueOptions.dedupeKey,
          );
        });
      });
    },
    claim,
    complete,
    fail,
    extend: (job, lease) => run(() => transport.extend(job, lease)),
    stats: (names) =>
      run(async () => {
        const stats = (queue: string): Promise<QueueStats> =>
          transport.stats?.(queue) ?? sqlOnly("stats");

        const list = names ?? Object.keys(queues);

        const entries = await Promise.all(
          list.map(async (queue) => {
            schemaOf(queue);

            return [queue, await stats(queue)] as const;
          }),
        );

        // SAFETY: the entries are exactly the requested queue names.
        return Object.fromEntries(entries) as Record<
          (typeof list)[number],
          QueueStats
        >;
      }),
    listDead: (queue, listOptions = {}) =>
      run(async () => {
        if (!transport.listDead) {
          sqlOnly("listDead");
        }

        schemaOf(queue);

        const rows = await transport.listDead(
          queue,
          listOptions.limit ?? 100,
          pageOf(listOptions).cursor,
        );

        return rows.map((row) => {
          const message = row.message ?? {};
          const { payload, context } = unwrap(message.payload);

          return {
            id: Number(row.id),
            queue,
            // SAFETY: the payload was validated with this queue's schema at enqueue.
            payload: payload as never,
            context,
            attempts: row.attempts,
            maxAttempts: message.max_attempts ?? 5,
            lastError: message.last_error ?? null,
            enqueuedAt: toInstant(row.enqueued_at),
            diedAt: row.died_at === null ? null : toInstant(row.died_at),
          };
        });
      }),
    retryDead: (queue, retryOptions = {}) =>
      run(async () => {
        if (!transport.retryDead) {
          sqlOnly("retryDead");
        }

        schemaOf(queue);

        return transport.retryDead(
          queue,
          retryOptions.ids,
          retryOptions.limit ?? 1000,
        );
      }),
    purge,
    purgeJob: (purgeOptions) => async () => purge(purgeOptions).orThrow(),
    replay: (queue, id) =>
      run(() => {
        if (!transport.replay) {
          sqlOnly("replay");
        }

        return transport.replay(queue, id);
      }),
    schedule(name, cron, queue, payload, scheduleOptions = {}) {
      return AsyncResult.from(async () => {
        const prepared = await prepare(
          name,
          cron,
          queue,
          payload,
          scheduleOptions,
        );

        if (!prepared.ok) {
          return prepared;
        }

        return run(() => write(prepared.data));
      });
    },
    unschedule: (name) => run(() => transport.unschedule(name)),
    ensureSchedules(definitions, ensureOptions) {
      return AsyncResult.from(async () => {
        const { prefix, tenant } = ensureOptions;

        if (prefix.length === 0) {
          return err(
            dbError(
              "invalid_request",
              "ensureSchedules needs a non-empty prefix",
            ),
          );
        }

        const names = new Set<string>();
        const prepared: PreparedSchedule[] = [];

        for (const definition of definitions) {
          if (
            !definition.name.startsWith(prefix) ||
            names.has(definition.name)
          ) {
            return err(
              dbError(
                "invalid_request",
                names.has(definition.name)
                  ? `Schedule "${definition.name}" is defined twice`
                  : `Schedule "${definition.name}" does not start with "${prefix}"`,
              ),
            );
          }

          names.add(definition.name);

          const ready = await prepare(
            definition.name,
            definition.cron,
            definition.queue,
            definition.payload,
            definition,
            tenant,
          );

          if (!ready.ok) {
            return ready;
          }

          prepared.push(ready.data);
        }

        return run(async () => {
          if (!transport.listSchedules) {
            sqlOnly("ensureSchedules");
          }

          const existing = await transport.listSchedules({
            prefix,
            ...(tenant === undefined ? {} : { tenant }),
          });

          for (const schedule of prepared) {
            await write(schedule);
          }

          const removed: string[] = [];

          for (const schedule of existing) {
            if (names.has(schedule.name)) {
              continue;
            }

            if (await transport.unschedule(schedule.name)) {
              removed.push(schedule.name);
            }
          }

          return { scheduled: [...names], removed };
        });
      });
    },
    listSchedules: (filter = {}) =>
      run(async () => {
        if (!transport.listSchedules) {
          sqlOnly("listSchedules");
        }

        return [...(await transport.listSchedules(filter))];
      }),
    unscheduleAll: (filter) =>
      run(() => {
        if (!transport.unscheduleTenant) {
          sqlOnly("unscheduleAll");
        }

        return transport.unscheduleTenant(filter.tenant);
      }),
    runSchedules: (scheduleOptions = {}) =>
      run(() => runSchedules(scheduleOptions)),
    drain: (queue, handler, drainOptions = {}) =>
      loop(queue, handler, drainOptions, false, budget(drainOptions.budgetMs)),
    work: (queue, handler, workOptions = {}) =>
      loop(queue, handler, workOptions, true),
    drainRoute(routeOptions) {
      for (const queue of Object.keys(routeOptions.handlers)) {
        schemaOf(queue);
      }

      return cronRoute(
        {
          name: "drain",
          secret: routeOptions.secret,
          problem: routeOptions.problem,
        },
        async (request) => {
          const spent = budget(routeOptions.budgetMs ?? 50_000);
          const monitor = routeOptions.monitor;
          let errors = 0;

          const report = (cause: unknown): void => {
            errors += 1;
            routeOptions.onError?.(toDbError(cause));
          };

          const watch = async (fn: () => unknown): Promise<unknown> => {
            try {
              return await fn();
            } catch (cause) {
              routeOptions.onError?.(toDbError(cause));

              return undefined;
            }
          };

          const started = monitor?.onStart
            ? await watch(() => monitor.onStart?.(request))
            : undefined;

          let scheduled = 0;

          if (routeOptions.schedules ?? true) {
            const ran = await run(() => runSchedules({}));

            if (ran.ok) {
              scheduled = ran.data;
            } else {
              errors += 1;
              routeOptions.onError?.(ran.error);
            }
          }

          const results: Record<string, DrainResult> = {};

          for (const [queue, handler] of Object.entries(
            routeOptions.handlers,
          )) {
            if (handler === undefined) {
              continue;
            }

            if (spent.expired()) {
              break;
            }

            try {
              results[queue] = await loop(
                queue,
                // SAFETY: handlers maps each queue name to the handler for its
                // payload; loop validates the payload with that queue's schema.
                handler as JobHandler<unknown>,
                routeOptions,
                false,
                spent,
              );
            } catch (cause) {
              report(cause);
              results[queue] = { succeeded: 0, failed: 0 };
            }
          }

          const result: DrainRouteResult = {
            schedules: scheduled,
            queues: results,
            budgetExhausted: spent.expired(),
            errors,
          };

          if (monitor?.onFinish) {
            await watch(() => monitor.onFinish?.(result, started));
          }

          return Response.json(result);
        },
      );
    },
  };

  return withBlockHooks(client, options.hooks, {
    block: "jobs",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
