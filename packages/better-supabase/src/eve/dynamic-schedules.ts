import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { Notifier } from "../blocks/ports.ts";
import type { ScheduleProvider } from "../blocks/queue/backends.ts";
import type { EveScheduleMirror } from "./schedule-mirror.ts";
import type {
  EveQueueDrainer,
  EveQueueJob,
  EveScheduleOptions,
  EveSendOptions,
} from "./schedules.ts";
import type { EveSessionAuth } from "./types.ts";

import { isRecord } from "../core/block-helpers.ts";
import { nextCronRun } from "../core/cron.ts";
import { DbException, dbError } from "../core/errors.ts";
import { temporal } from "../core/temporal-required.ts";
import { nowInstant } from "../core/temporal.ts";
import { stableUuid } from "./ids.ts";
import { scheduleMirror } from "./schedule-mirror.ts";

export type { EveScheduleMirror } from "./schedule-mirror.ts";

/** Eve's `ScheduleExpression`: a recurring cron or one local date and time. */
export type EveScheduleExpression =
  | {
      readonly type: "cron";
      readonly cron: string;
      readonly timezone?: string;
      readonly jitter?: number;
    }
  | {
      readonly type: "single";
      /** A `YYYY-MM-DDTHH:mm` local date and time in `timezone`. */
      readonly at: string;
      readonly timezone?: string;
    };

/** Eve's `ScheduleState`. */
export type EveScheduleState = "active" | "inactive" | "completed";

/** Eve's `ScheduleRecord`: what `get` and `list` return, without payload. */
export interface EveScheduleRecord {
  readonly displayName?: string;
  readonly createdAt: number;
  readonly expression: EveScheduleExpression;
  readonly name: string;
  readonly scheduleId: string;
  readonly state: EveScheduleState;
  readonly updatedAt: number;
}

/** Eve's `ScheduleOccurrence`: one firing of a schedule. */
export interface EveScheduleOccurrence {
  readonly executionId: string;
  readonly name: string;
  readonly scheduleId: string;
  readonly scheduledAt: string;
}

/**
 * Eve's `ScheduleProviderContext`, which addresses one collection and
 * namespace.
 */
export interface EveScheduleProviderContext {
  readonly abortSignal: AbortSignal;
  readonly collection: string;
  readonly namespace: string;
  readonly operationId: string;
  readonly target: {
    readonly key: string;
    readonly deliver?: (delivery: {
      readonly payload: unknown;
      readonly occurrence: EveScheduleOccurrence;
    }) => Promise<void>;
  };
}

/**
 * Eve's `ScheduleProvider` from `eve/experimental/schedules`, typed
 * structurally so this entry never imports eve.
 */
export interface EveScheduleProvider {
  readonly kind: string;
  create<TPayload>(
    context: EveScheduleProviderContext,
    schedule: {
      readonly expression: EveScheduleExpression;
      readonly payload: TPayload;
      readonly name: string;
    },
  ): Promise<EveScheduleRecord>;
  list(
    context: EveScheduleProviderContext,
    query: { readonly cursor?: string; readonly limit?: number },
  ): Promise<{
    readonly cursor: string | null;
    readonly data: readonly EveScheduleRecord[];
  }>;
  get(
    context: EveScheduleProviderContext,
    name: string,
  ): Promise<EveScheduleRecord | null>;
  update<TPayload>(
    context: EveScheduleProviderContext,
    name: string,
    patch: {
      readonly expression?: EveScheduleExpression;
      readonly payload?: TPayload;
    },
  ): Promise<EveScheduleRecord>;
  enable(
    context: EveScheduleProviderContext,
    name: string,
  ): Promise<EveScheduleRecord>;
  disable(
    context: EveScheduleProviderContext,
    name: string,
  ): Promise<EveScheduleRecord>;
  invoke(context: EveScheduleProviderContext, name: string): Promise<void>;
  delete(context: EveScheduleProviderContext, name: string): Promise<boolean>;
}

/**
 * One eve dynamic schedule as `queueScheduleProvider` stores it: the payload of
 * a queue block schedule, and of each run the scheduler enqueues.
 */
export interface EveScheduleRun {
  readonly version: 1;
  readonly collection: string;
  readonly namespace: string;
  /** Eve's unique management name. */
  readonly name: string;
  readonly scheduleId: string;
  readonly displayName: string;
  readonly expression: EveScheduleExpression;
  readonly state: EveScheduleState;
  readonly createdAt: number;
  readonly updatedAt: number;
  readonly tenant?: string;
  /** Eve's stored payload: the prepared payload with its creator and scope. */
  readonly payload: unknown;
}

const STATES: ReadonlySet<unknown> = new Set([
  "active",
  "inactive",
  "completed",
]);

const isExpression = (value: unknown): value is EveScheduleExpression =>
  isRecord(value) &&
  ((value["type"] === "cron" && typeof value["cron"] === "string") ||
    (value["type"] === "single" && typeof value["at"] === "string"));

const isRun = (value: unknown): value is EveScheduleRun =>
  isRecord(value) &&
  value["version"] === 1 &&
  typeof value["collection"] === "string" &&
  typeof value["namespace"] === "string" &&
  typeof value["name"] === "string" &&
  typeof value["scheduleId"] === "string" &&
  typeof value["displayName"] === "string" &&
  isExpression(value["expression"]) &&
  STATES.has(value["state"]) &&
  typeof value["createdAt"] === "number" &&
  typeof value["updatedAt"] === "number" &&
  (value["tenant"] === undefined || typeof value["tenant"] === "string") &&
  "payload" in value;

/**
 * The queue schema for `EveScheduleRun`: pass it as the `eve_schedules` queue
 * in `createQueue({ queues })`.
 */
export const eveScheduleRun: StandardSchemaV1<EveScheduleRun> = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate: (value) =>
      isRun(value)
        ? { value }
        : {
            issues: [
              {
                message:
                  "an eve schedule run needs version 1, its collection, namespace, name, timing, state and payload",
              },
            ],
          },
  },
};

/** Options for `queueScheduleProvider`. */
export interface QueueScheduleProviderOptions {
  /**
   * The queue block scheduler that stores and fires the schedules. It must list
   * schedules with their payloads, as `sqlScheduler(sql, { mode: "drain" })`
   * and `transportScheduler` in drain mode do.
   */
  readonly scheduler: ScheduleProvider;
  /** The queue each run is enqueued on. Default: `eve_schedules`. */
  readonly queue?: string;
  /** Prefixes every schedule name. Default: `eve:`. */
  readonly prefix?: string;
  /**
   * The tenant a schedule belongs to, from the scope eve resolved for its
   * creator, so `unscheduleAll({ tenant })` removes it with the tenant.
   */
  readonly tenantOf?: (scope: string | readonly string[]) => string | undefined;
  /**
   * Named scopes, by the first part of the scope eve resolved for the creator
   * (`"user"` for `["user", id]`). When set, a schedule in any other scope is
   * rejected, and each rule can set its tenant, how many schedules one scope
   * (one user, for example) may hold and the shortest cron interval.
   */
  readonly scopes?: Readonly<Record<string, EveScheduleScopeRule>>;
  /** The shortest cron interval for scopes without a rule of their own. */
  readonly minIntervalMs?: number;
  /**
   * Your own check of an expression on create and update, after the built-in
   * ones. Throw to reject it; a thrown `DbException` passes through and any
   * other error becomes a `validation` error.
   */
  readonly mirror?: EveScheduleMirror;
  readonly validateExpression?: (
    expression: EveScheduleExpression,
    context: {
      readonly collection: string;
      readonly scope: string | readonly string[] | undefined;
    },
  ) => void | Promise<void>;
  readonly now?: () => Temporal.Instant;
}

/** One named scope of `queueScheduleProvider({ scopes })`. */
export interface EveScheduleScopeRule {
  /** The tenant from the scope's parts after its name; falls back to `tenantOf`. */
  readonly tenantOf?: (parts: readonly string[]) => string | undefined;
  /** Schedules one scope may hold in a collection. */
  readonly maxSchedules?: number;
  /** The shortest gap between two runs of a cron expression, in ms. */
  readonly minIntervalMs?: number;
}

/** How `queueDynamicSchedules` reads and writes a provider's runs. */
interface RunStore {
  /** The queue the scheduler enqueues runs on. */
  readonly queue: string;
  /** The stored version of a run, or `null` when it was deleted. */
  current(run: EveScheduleRun): Promise<EveScheduleRun | null>;
  /** Writes a run back, such as a completed one-time schedule. */
  save(run: EveScheduleRun): Promise<void>;
  /** Deletes a run's schedule. */
  remove(run: EveScheduleRun): Promise<boolean>;
  /** Records an occurrence in the mirror. Never throws. */
  record(
    run: EveScheduleRun,
    scheduledAt: Temporal.Instant,
    status: "completed" | "failed" | "running",
    error?: string,
  ): Promise<void>;
}

/**
 * Each provider's run store. eve rejects a provider object with keys beyond its
 * contract, so the store can't be a property of the provider.
 */
const STORES = new WeakMap<EveScheduleProvider, RunStore>();

const SINGLE_AT = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/;

const invalid = (message: string): DbException =>
  new DbException(dbError("validation", message, { issues: [{ message }] }));

/** The instant of a `single` expression's local date and time. */
function singleInstant(at: string, timeZone: string): Temporal.Instant {
  if (!SINGLE_AT.test(at)) {
    throw invalid(`"${at}" is not a YYYY-MM-DDTHH:mm local date and time`);
  }

  return temporal()
    .PlainDateTime.from(at)
    .toZonedDateTime(timeZone)
    .toInstant();
}

interface Timing {
  readonly cron: string;
  readonly timeZone: string;
  readonly nextRun: Temporal.Instant;
}

/**
 * The cron, zone and first run the scheduler stores for `expression`. A
 * `single` time becomes a cron for its minute, hour, day and month; the run
 * handler completes it after its first run.
 */
function timingOf(
  expression: EveScheduleExpression,
  now: Temporal.Instant,
): Timing {
  const timeZone = expression.timezone ?? "UTC";

  try {
    if (expression.type === "cron") {
      return {
        cron: expression.cron,
        timeZone,
        nextRun: nextCronRun(expression.cron, timeZone, now),
      };
    }

    const nextRun = singleInstant(expression.at, timeZone);
    const local = temporal().PlainDateTime.from(expression.at);

    return {
      cron: `${String(local.minute)} ${String(local.hour)} ${String(local.day)} ${String(local.month)} *`,
      timeZone,
      nextRun,
    };
  } catch (cause) {
    if (cause instanceof DbException) {
      throw cause;
    }

    throw invalid(cause instanceof Error ? cause.message : String(cause));
  }
}

/** What `validateExpression` checks besides the syntax. */
export interface ValidateExpressionOptions {
  /** The clock; a `single` time must be after it. Default: now. */
  readonly now?: Temporal.Instant;
  /** The shortest gap between two runs of a cron expression. */
  readonly minIntervalMs?: number;
  /** Accept a `single` time that is already past. Default: false. */
  readonly allowPast?: boolean;
}

/**
 * Checks an eve schedule expression and throws a `validation` `DbException`
 * naming what is wrong: a cron that does not parse, a time zone that does not
 * exist, a `single` time that is malformed or already past, a negative jitter,
 * or a cron that runs more often than `minIntervalMs`. `queueScheduleProvider`
 * runs it on every create and update.
 */
export function validateExpression(
  expression: EveScheduleExpression,
  options: ValidateExpressionOptions = {},
): void {
  const now = options.now ?? nowInstant();
  const timing = timingOf(expression, now);

  if (expression.type === "single") {
    if (
      options.allowPast !== true &&
      temporal().Instant.compare(timing.nextRun, now) <= 0
    ) {
      throw invalid(`"${expression.at}" is already past`);
    }

    return;
  }

  if (
    expression.jitter !== undefined &&
    (!Number.isFinite(expression.jitter) || expression.jitter < 0)
  ) {
    throw invalid("jitter must be a number of at least 0");
  }

  if (options.minIntervalMs !== undefined) {
    const second = nextCronRun(
      expression.cron,
      timing.timeZone,
      timing.nextRun,
    );

    if (
      second.epochMilliseconds - timing.nextRun.epochMilliseconds <
      options.minIntervalMs
    ) {
      throw invalid(
        `"${expression.cron}" runs more often than every ${String(options.minIntervalMs)} ms`,
      );
    }
  }
}

const recordOf = (run: EveScheduleRun): EveScheduleRecord => ({
  displayName: run.displayName,
  createdAt: run.createdAt,
  expression: run.expression,
  name: run.name,
  scheduleId: run.scheduleId,
  state: run.state,
  updatedAt: run.updatedAt,
});

/** Eve appends `--<uuid>` to the label to make the unique management name. */
const displayNameOf = (name: string): string =>
  name.replace(
    /--[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    "",
  );

/** The scope eve stored with the payload, for `tenantOf`. */
const scopeOf = (payload: unknown): string | readonly string[] | undefined => {
  const envelope = isRecord(payload) ? payload["envelope"] : undefined;
  const scope = isRecord(envelope) ? envelope["scope"] : undefined;

  return typeof scope === "string" ||
    (Array.isArray(scope) &&
      scope.every((part): part is string => typeof part === "string"))
    ? scope
    : undefined;
};

const notFound = (name: string): DbException =>
  new DbException(
    dbError("not_found", `eve: no schedule "${name}" in this scope`, {
      hint: "EVE_SCHEDULE_NOT_FOUND",
    }),
  );

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

/**
 * An eve `ScheduleProvider` for `defineDynamicSchedules({ provider })` over a
 * queue block scheduler: each eve schedule is one queue block schedule whose
 * payload is the `EveScheduleRun`, so the scheduler both stores it and enqueues
 * a run on `eve_schedules` when it is due. Fire the runs with
 * `queueDynamicSchedules` from a minute schedule. eve's `invoke` delivers
 * through the target eve passes with the call.
 *
 * Throws a `TypeError` for a scheduler that can't list schedules. A scheduler
 * that lists them without payloads (pg_cron, Vercel Schedules) fails each read
 * with an `unsupported` `DbException`.
 */
export function queueScheduleProvider(
  options: QueueScheduleProviderOptions,
): EveScheduleProvider {
  const { scheduler } = options;
  const listSchedules = scheduler.listSchedules?.bind(scheduler);

  if (listSchedules === undefined) {
    throw new TypeError(
      `queueScheduleProvider needs a scheduler that lists schedules with their payloads, such as sqlScheduler(sql, { mode: "drain" }); "${scheduler.name}" can't list them`,
    );
  }

  const queue = options.queue ?? "eve_schedules";
  const prefix = options.prefix ?? "eve:";
  const now = options.now ?? nowInstant;

  const prefixOf = (collection: string, namespace: string): string =>
    `${prefix}${collection}:${namespace}:`;

  const storedName = (run: {
    readonly collection: string;
    readonly namespace: string;
    readonly name: string;
  }): string => `${prefixOf(run.collection, run.namespace)}${run.name}`;

  const listed = async (namePrefix: string): Promise<EveScheduleRun[]> => {
    const runs: EveScheduleRun[] = [];

    for (const schedule of await listSchedules({ prefix: namePrefix })) {
      if (schedule.payload === undefined) {
        throw new DbException(
          dbError(
            "unsupported",
            `eve: the scheduler "${scheduler.name}" lists schedules without their payloads; queueScheduleProvider needs one that keeps them, such as sqlScheduler(sql, { mode: "drain" })`,
            { hint: "EVE_SCHEDULE_PAYLOAD_UNREADABLE" },
          ),
        );
      }

      if (
        isRun(schedule.payload) &&
        storedName(schedule.payload) === schedule.name
      ) {
        runs.push(schedule.payload);
      }
    }

    return runs.toSorted((a, b) => (a.name < b.name ? -1 : 1));
  };

  const find = async (key: {
    readonly collection: string;
    readonly namespace: string;
    readonly name: string;
  }): Promise<EveScheduleRun | null> =>
    (await listed(storedName(key))).find((run) => run.name === key.name) ??
    null;

  const read = (
    context: EveScheduleProviderContext,
    name: string,
  ): Promise<EveScheduleRun | null> =>
    find({
      collection: context.collection,
      namespace: context.namespace,
      name,
    });

  const existing = async (
    context: EveScheduleProviderContext,
    name: string,
  ): Promise<EveScheduleRun> => {
    const run = await read(context, name);

    if (run === null) {
      throw notFound(name);
    }

    return run;
  };

  const mirror = scheduleMirror(options.mirror, {
    name: storedName,
    principalOf: (run) => {
      try {
        return envelopeOf(run.payload).principal.principalId;
      } catch {
        return;
      }
    },
  });

  const save = async (run: EveScheduleRun): Promise<void> => {
    const timing = timingOf(run.expression, now());

    await scheduler.schedule(
      storedName(run),
      timing.cron,
      queue,
      run,
      timing.timeZone,
      timing.nextRun,
      run.tenant,
    );

    await mirror.save(run, timing);
  };

  const unschedule = async (run: EveScheduleRun): Promise<boolean> => {
    const removed = await scheduler.unschedule(storedName(run), run.tenant);

    await mirror.remove(run);

    return removed;
  };

  const record: RunStore["record"] = (run, scheduledAt, status, error) =>
    mirror.record(run, scheduledAt, status, error);

  const write = async (run: EveScheduleRun): Promise<EveScheduleRecord> => {
    await save(run);

    return recordOf(run);
  };

  const ruleOf = (
    scope: string | readonly string[] | undefined,
  ): EveScheduleScopeRule | undefined => {
    if (options.scopes === undefined) {
      return undefined;
    }

    const name = typeof scope === "string" ? scope : scope?.[0];
    const rule = name === undefined ? undefined : options.scopes[name];

    if (rule === undefined) {
      throw invalid(
        `eve: the schedule scope "${name ?? "(none)"}" is not one of ${Object.keys(options.scopes).join(", ")}`,
      );
    }

    return rule;
  };

  const tenantFor = (payload: unknown): { readonly tenant?: string } => {
    const scope = scopeOf(payload);
    const rule = ruleOf(scope);

    const tenant =
      scope === undefined
        ? undefined
        : (rule?.tenantOf?.(typeof scope === "string" ? [] : scope.slice(1)) ??
          options.tenantOf?.(scope));

    return tenant === undefined ? {} : { tenant };
  };

  /** The built-in and custom checks of an expression, for the scope's rule. */
  const checkExpression = async (
    collection: string,
    expression: EveScheduleExpression,
    payload: unknown,
  ): Promise<void> => {
    const scope = scopeOf(payload);

    // A past `single` time is allowed: it fires at its next matching minute.
    validateExpression(expression, {
      now: now(),
      allowPast: true,
      ...((ruleOf(scope)?.minIntervalMs ?? options.minIntervalMs) === undefined
        ? {}
        : {
            minIntervalMs:
              ruleOf(scope)?.minIntervalMs ?? options.minIntervalMs,
          }),
    });

    try {
      await options.validateExpression?.(expression, { collection, scope });
    } catch (cause) {
      throw cause instanceof DbException
        ? cause
        : invalid(cause instanceof Error ? cause.message : String(cause));
    }
  };

  const withState = async (
    context: EveScheduleProviderContext,
    name: string,
    from: EveScheduleState,
    to: EveScheduleState,
  ): Promise<EveScheduleRecord> => {
    const run = await existing(context, name);

    return run.state === from
      ? write({ ...run, state: to, updatedAt: now().epochMilliseconds })
      : recordOf(run);
  };

  const provider: EveScheduleProvider = {
    kind: `better-supabase:${scheduler.name}`,
    async create(context, schedule) {
      const at = now().epochMilliseconds;

      await checkExpression(
        context.collection,
        schedule.expression,
        schedule.payload,
      );

      const max = ruleOf(scopeOf(schedule.payload))?.maxSchedules;

      if (
        max !== undefined &&
        (await listed(prefixOf(context.collection, context.namespace)))
          .length >= max
      ) {
        throw new DbException(
          dbError(
            "conflict",
            `eve: this scope already holds ${String(max)} schedules`,
            { hint: "EVE_SCHEDULE_LIMIT" },
          ),
        );
      }

      return write({
        version: 1,
        collection: context.collection,
        namespace: context.namespace,
        name: schedule.name,
        scheduleId: crypto.randomUUID(),
        displayName: displayNameOf(schedule.name),
        expression: schedule.expression,
        state: "active",
        createdAt: at,
        updatedAt: at,
        ...tenantFor(schedule.payload),
        payload: schedule.payload,
      });
    },
    async list(context, query) {
      const limit = Math.min(
        Math.max(query.limit ?? DEFAULT_LIMIT, 1),
        MAX_LIMIT,
      );

      const after = (
        await listed(prefixOf(context.collection, context.namespace))
      ).filter((run) => query.cursor === undefined || run.name > query.cursor);

      const page = after.slice(0, limit);

      return {
        cursor: after.length > limit ? (page.at(-1)?.name ?? null) : null,
        data: page.map(recordOf),
      };
    },
    async get(context, name) {
      const run = await read(context, name);

      return run === null ? null : recordOf(run);
    },
    async update(context, name, patch) {
      const run = await existing(context, name);

      if (patch.expression !== undefined) {
        await checkExpression(
          run.collection,
          patch.expression,
          patch.payload ?? run.payload,
        );
      }

      const timing = {
        expression: patch.expression ?? run.expression,
        updatedAt: now().epochMilliseconds,
      };

      if (patch.payload === undefined) {
        return write({ ...run, ...timing });
      }

      // A replaced payload has a new creator, so its tenant is read again.
      return write({
        version: 1,
        collection: run.collection,
        namespace: run.namespace,
        name: run.name,
        scheduleId: run.scheduleId,
        displayName: run.displayName,
        state: run.state,
        createdAt: run.createdAt,
        ...timing,
        ...tenantFor(patch.payload),
        payload: patch.payload,
      });
    },
    enable: (context, name) => withState(context, name, "inactive", "active"),
    disable: (context, name) => withState(context, name, "active", "inactive"),
    async invoke(context, name) {
      const run = await existing(context, name);

      if (run.state === "completed") {
        throw new DbException(
          dbError("conflict", `eve: the schedule "${name}" has completed`, {
            hint: "EVE_SCHEDULE_COMPLETED",
          }),
        );
      }

      const { deliver } = context.target;

      if (deliver === undefined) {
        throw new DbException(
          dbError(
            "unsupported",
            "eve: this call carries no delivery target to invoke the schedule through",
            { hint: "EVE_SCHEDULE_NO_TARGET" },
          ),
        );
      }

      await deliver({
        payload: run.payload,
        occurrence: {
          executionId: `${run.scheduleId}:invoke:${context.operationId}`,
          name: run.name,
          scheduleId: run.scheduleId,
          scheduledAt: now().toString(),
        },
      });
    },
    delete: async (context, name) => {
      const run = await read(context, name);

      return run === null ? false : unschedule(run);
    },
  };

  STORES.set(provider, {
    queue,
    current: find,
    save,
    remove: unschedule,
    record,
  });

  return provider;
}

/** Eve's `ScheduleOccurrenceIdentity`, as `auth`, `run` and the events read it. */
export interface EveScheduleOccurrenceIdentity extends EveScheduleOccurrence {
  readonly displayName?: string;
  readonly collection: string;
}

/** Eve's `SchedulePrincipalReference`: the creator a schedule runs as. */
export interface EveSchedulePrincipal {
  readonly type: string;
  readonly authenticator: string;
  readonly issuer?: string;
  readonly principalId: string;
  readonly subject?: string;
}

/** Eve's `ScheduleHandle`: controls the schedule that fired. */
export interface EveScheduleHandle {
  disable(): Promise<void>;
  delete(): Promise<void>;
}

/** The handle the dynamic `to(channel, target)` returns. */
export interface EveDynamicTargetHandle {
  send(
    message: string,
    options?: Omit<EveSendOptions, "auth">,
  ): Promise<unknown>;
}

/** An `occurrence.dispatched` or `occurrence.failed` event. */
export interface EveScheduleOccurrenceEvent {
  readonly type: "occurrence.dispatched" | "occurrence.failed";
  readonly collection: string;
  readonly executionId: string;
  readonly name: string;
  readonly scheduleId: string;
  readonly scheduledAt: string;
  readonly occurrence: EveScheduleOccurrenceIdentity;
  readonly sessionIds?: readonly string[];
  readonly reason?: string;
  readonly schedule?: unknown;
}

/** What `queueDynamicSchedules` passes to a definition's `auth`. */
export interface EveScheduleAuthContext {
  readonly principal: EveSchedulePrincipal;
  readonly payload: unknown;
  readonly occurrence: EveScheduleOccurrenceIdentity;
  readonly schedule: EveScheduleHandle;
}

/** What `queueDynamicSchedules` passes to a definition's `run`. */
export interface EveDynamicRunParams {
  readonly to: (channel: never, target: never) => EveDynamicTargetHandle;
  readonly payload: unknown;
  readonly occurrence: EveScheduleOccurrenceIdentity;
  readonly auth: EveSessionAuth;
  readonly schedule: EveScheduleHandle;
  readonly waitUntil: (task: Promise<unknown>) => void;
}

/**
 * The parts of a `defineDynamicSchedules` definition `queueDynamicSchedules`
 * calls, typed structurally so this entry never imports eve. eve types `auth`,
 * `run` and the events by the definition's payload, so they take `never` here;
 * `queueDynamicSchedules` calls them with `EveScheduleAuthContext`,
 * `EveDynamicRunParams` and `EveScheduleOccurrenceEvent`.
 */
export interface EveDynamicSchedules {
  readonly inputSchema: {
    readonly "~standard": { validate(value: unknown): unknown };
  };
  readonly preparePayload?: unknown;
  readonly auth: (context: never) => unknown;
  readonly run: (args: never) => unknown;
  readonly events?: {
    readonly "occurrence.dispatched"?: (event: never) => unknown;
    readonly "occurrence.failed"?: (event: never) => unknown;
  };
}

/** The part of a queue job `queueDynamicSchedules` reads. */
export interface EveScheduleJob extends EveQueueJob {
  readonly id: number | string;
  readonly attempts: number;
  readonly maxAttempts: number;
  readonly enqueuedAt: Temporal.Instant;
  /** Set when a Vercel schedule pushed the run. */
  readonly schedule?: {
    readonly executionId: string;
    readonly scheduledAt: Temporal.Instant;
  };
}

/** Options for `queueDynamicSchedules`. */
export interface QueueDynamicSchedulesOptions {
  readonly queue: EveQueueDrainer<EveScheduleRun, EveScheduleJob>;
  /** The provider the definitions pass to `defineDynamicSchedules`. */
  readonly provider: EveScheduleProvider;
  /**
   * The definitions by collection name: the definition's `id`, or its file path
   * under `agent/schedules/` when it sets none, such as `requests` for
   * `agent/schedules/requests.ts`.
   */
  readonly collections: Readonly<Record<string, EveDynamicSchedules>>;
  /** Stop claiming after this many ms. Default: 50 000. */
  readonly budgetMs?: number;
  readonly now?: () => Temporal.Instant;
  /**
   * Tells the creator when an occurrence fails for good: the definition's
   * `auth` returned null, the payload is invalid, the retries ran out or the
   * occurrence was stale. A failing notifier is ignored, like an event
   * handler.
   */
  readonly notify?: EveScheduleFailureNotice;
  /**
   * A cron occurrence that starts later than this after its time fails as stale
   * instead of firing, so a backlog after an outage does not send hours old
   * prompts. Unset, every occurrence fires.
   */
  readonly staleAfterMs?: number;
}

/** Where `queueDynamicSchedules` reports a failed occurrence. */
export interface EveScheduleFailureNotice {
  /** The `notifications` block, from `createBlocks`. */
  readonly notifier: Notifier;
  /**
   * The notification type. Its data holds the schedule, occurrence and
   * `reason`.
   */
  readonly type: string;
  /** Who is told. Defaults to the schedule's creator. */
  readonly recipients?: (
    run: EveScheduleRun,
    creator: EveSchedulePrincipal | undefined,
  ) => readonly string[];
}

/** A failure retrying can't fix: the occurrence fails without a retry. */
class PermanentFailure extends Error {
  override readonly name = "PermanentFailure";
}

interface StoredEnvelope {
  readonly payload: unknown;
  readonly principal: EveSchedulePrincipal;
}

const envelopeOf = (payload: unknown): StoredEnvelope => {
  const envelope = isRecord(payload) ? payload["envelope"] : undefined;
  const principal = isRecord(envelope) ? envelope["principal"] : undefined;

  if (
    !isRecord(envelope) ||
    envelope["version"] !== 3 ||
    !isRecord(principal) ||
    typeof principal["type"] !== "string" ||
    typeof principal["authenticator"] !== "string" ||
    typeof principal["principalId"] !== "string"
  ) {
    throw new PermanentFailure(
      "Invalid scheduled collection payload; recreate the schedule.",
    );
  }

  return {
    payload: envelope["payload"],
    principal: {
      type: principal["type"],
      authenticator: principal["authenticator"],
      principalId: principal["principalId"],
      ...(typeof principal["issuer"] === "string"
        ? { issuer: principal["issuer"] }
        : {}),
      ...(typeof principal["subject"] === "string"
        ? { subject: principal["subject"] }
        : {}),
    },
  };
};

const isIssueResult = (
  value: unknown,
): value is { readonly issues: readonly { readonly message?: unknown }[] } =>
  isRecord(value) && Array.isArray(value["issues"]);

/** Validates the stored payload with `inputSchema`, as eve does before a run. */
async function validated(
  definition: EveDynamicSchedules,
  value: unknown,
): Promise<unknown> {
  const result: unknown =
    await definition.inputSchema["~standard"].validate(value);

  if (isIssueResult(result) || !isRecord(result) || !("value" in result)) {
    const issues = isIssueResult(result)
      ? result.issues.map((issue) => String(issue.message)).join("; ")
      : "schema validation failed";

    throw new PermanentFailure(`Invalid schedule payload: ${issues}.`);
  }

  return result["value"];
}

/**
 * The run's auth from what `auth` returned: a full context for the creator, or
 * `{ attributes }` added to the stored creator. `null` and any other shape fail
 * the occurrence without a retry, as in eve.
 */
function creatorAuth(
  result: unknown,
  principal: EveSchedulePrincipal,
): EveSessionAuth {
  if (result === null) {
    throw new PermanentFailure(
      'Scheduled execution is no longer authorized: "auth" returned null for the schedule creator.',
    );
  }

  if (
    isRecord(result) &&
    typeof result["principalId"] === "string" &&
    (result["principalId"] !== principal.principalId ||
      result["principalType"] !== principal.type ||
      result["authenticator"] !== principal.authenticator ||
      result["issuer"] !== principal.issuer ||
      result["subject"] !== principal.subject)
  ) {
    throw new PermanentFailure(
      "Scheduled execution auth must resolve the schedule creator.",
    );
  }

  const attributes = isRecord(result) ? result["attributes"] : undefined;

  if (!isRecord(attributes)) {
    throw new PermanentFailure(
      'Scheduled execution "auth" must return { attributes }, a SessionAuthContext for the schedule creator, or null.',
    );
  }

  const values: Record<string, string | readonly string[]> = {};

  for (const [key, value] of Object.entries(attributes)) {
    if (
      typeof value === "string" ||
      (Array.isArray(value) &&
        value.every((part): part is string => typeof part === "string"))
    ) {
      values[key] = value;
    }
  }

  return {
    authenticator: principal.authenticator,
    principalType: principal.type,
    principalId: principal.principalId,
    ...(principal.issuer === undefined ? {} : { issuer: principal.issuer }),
    ...(principal.subject === undefined ? {} : { subject: principal.subject }),
    attributes: values,
  };
}

const sessionIdOf = (delivery: unknown): string | undefined =>
  isRecord(delivery) && typeof delivery["sessionId"] === "string"
    ? delivery["sessionId"]
    : undefined;

/**
 * The `run` handler for an eve schedule that fires every minute
 * (`defineSchedule({ cron: "* * * * *", run })`), which fires the dynamic
 * schedules `queueScheduleProvider` stores. It enqueues the due schedules
 * (`runSchedules`), then drains the provider's queue; for each run it rereads
 * the schedule, checks the creator with the definition's `auth` and calls its
 * `run`, whose `to()` starts sessions as the creator. A send without an
 * `idempotencyKey` gets one from the occurrence and the message, so a retried
 * run reaches the session the first attempt started. `null` from `auth`, an
 * invalid payload or an unknown collection fail the occurrence for good
 * (`occurrence.failed`); a thrown error retries the job.
 */
export function queueDynamicSchedules(
  options: QueueDynamicSchedulesOptions,
): (args: EveScheduleOptions) => void {
  const now = options.now ?? nowInstant;
  const provider = STORES.get(options.provider);

  if (provider === undefined) {
    throw new TypeError(
      "queueDynamicSchedules needs the provider queueScheduleProvider returned",
    );
  }

  const tell = async (
    run: EveScheduleRun,
    failed: EveScheduleOccurrenceEvent,
  ): Promise<void> => {
    const { notify } = options;

    if (notify === undefined || run.tenant === undefined) {
      return;
    }

    let creator: EveSchedulePrincipal | undefined;

    try {
      creator = envelopeOf(run.payload).principal;
    } catch {
      creator = undefined;
    }

    const recipients =
      notify.recipients?.(run, creator) ??
      (creator === undefined ? [] : [creator.principalId]);

    if (recipients.length === 0) {
      return;
    }

    try {
      await notify.notifier.send({
        type: notify.type,
        input: {
          recipients,
          tenant: run.tenant,
          key: `eve-schedule-failed:${failed.executionId}`,
          subject: { type: "eve_schedule", id: run.scheduleId },
          data: {
            collection: run.collection,
            name: run.name,
            displayName: run.displayName,
            scheduleId: run.scheduleId,
            executionId: failed.executionId,
            scheduledAt: failed.scheduledAt,
            reason: failed.reason,
          },
        },
      });
    } catch {
      // A notification that fails must not change what the occurrence did.
    }
  };

  const fire = async (
    args: EveScheduleOptions,
    queued: EveScheduleRun,
    job: EveScheduleJob,
  ): Promise<void> => {
    const definition = options.collections[queued.collection];

    if (definition === undefined) {
      throw new TypeError(
        `eve: no dynamic schedules "${queued.collection}" in queueDynamicSchedules' collections`,
      );
    }

    const run = await provider.current(queued);

    if (run?.state !== "active") {
      return;
    }

    let scheduledAt = job.schedule?.scheduledAt ?? job.enqueuedAt;

    if (run.expression.type === "single") {
      scheduledAt = singleInstant(
        run.expression.at,
        run.expression.timezone ?? "UTC",
      );

      // The cron for a one-time schedule matches the same minute every year.
      if (temporal().Instant.compare(now(), scheduledAt) < 0) {
        return;
      }
    }

    const occurrence: EveScheduleOccurrenceIdentity = {
      executionId:
        job.schedule?.executionId ?? `${run.scheduleId}:${String(job.id)}`,
      name: run.name,
      scheduleId: run.scheduleId,
      scheduledAt: scheduledAt.toString(),
      displayName: run.displayName,
      collection: run.collection,
    };

    const event = (
      type: EveScheduleOccurrenceEvent["type"],
      extra: Partial<EveScheduleOccurrenceEvent>,
    ): EveScheduleOccurrenceEvent => ({
      type,
      collection: run.collection,
      executionId: occurrence.executionId,
      name: run.name,
      scheduleId: run.scheduleId,
      scheduledAt: occurrence.scheduledAt,
      occurrence,
      ...extra,
    });

    const schedule: EveScheduleHandle = {
      disable: () =>
        provider.save({
          ...run,
          state: "inactive",
          updatedAt: now().epochMilliseconds,
        }),
      delete: async () => {
        await provider.remove(run);
      },
    };

    const sessions: string[] = [];

    await provider.record(run, scheduledAt, "running");

    try {
      const envelope = envelopeOf(run.payload);

      if (
        options.staleAfterMs !== undefined &&
        run.expression.type === "cron" &&
        now().epochMilliseconds - scheduledAt.epochMilliseconds >
          options.staleAfterMs
      ) {
        throw new PermanentFailure(
          `The occurrence for ${scheduledAt.toString()} started more than ${String(options.staleAfterMs)} ms late and was skipped.`,
        );
      }

      const payload =
        definition.preparePayload === undefined
          ? await validated(definition, envelope.payload)
          : envelope.payload;

      const authContext: EveScheduleAuthContext = {
        principal: envelope.principal,
        payload,
        occurrence,
        schedule,
      };

      const auth = creatorAuth(
        // SAFETY: eve types `auth` by the definition's payload, which `validated`
        // checked against `inputSchema` (or `preparePayload` shaped when stored).
        await definition.auth(authContext as never),
        envelope.principal,
      );

      const tasks: Promise<unknown>[] = [];

      const runArgs: EveDynamicRunParams = {
        payload,
        occurrence,
        auth,
        schedule,
        waitUntil: (task) => {
          tasks.push(task);
        },
        to: (channel, target) => ({
          send: async (message, sendOptions = {}) => {
            const delivery = await args
              .to(channel, target)
              .send(message, {
                ...sendOptions,
                auth,
                idempotencyKey:
                  sendOptions.idempotencyKey ??
                  `eve-schedule:${await stableUuid(JSON.stringify([occurrence.executionId, message]))}`,
              });

            const sessionId = sessionIdOf(delivery);

            if (sessionId !== undefined) {
              sessions.push(sessionId);
            }

            return delivery;
          },
        }),
      };

      // SAFETY: as for `auth`: `run` takes the payload `auth` received.
      await definition.run(runArgs as never);
      await Promise.all(tasks);
    } catch (cause) {
      const permanent = cause instanceof PermanentFailure;

      if (permanent || job.attempts >= job.maxAttempts) {
        const failed = event("occurrence.failed", {
          reason:
            cause instanceof Error
              ? cause.message
              : "Scheduled occurrence failed.",
        });

        await tell(run, failed);
        await provider.record(run, scheduledAt, "failed", failed.reason);
        // SAFETY: eve types the event by the payload; this one carries none.
        await definition.events?.["occurrence.failed"]?.(failed as never);
      }

      if (permanent) {
        return;
      }

      throw cause;
    }

    await provider.record(run, scheduledAt, "completed");

    if (run.expression.type === "single") {
      await provider.save({
        ...run,
        state: "completed",
        updatedAt: now().epochMilliseconds,
      });
    }

    const dispatched = event("occurrence.dispatched", { sessionIds: sessions });

    // SAFETY: eve types the event by the payload; this one carries none.
    await definition.events?.["occurrence.dispatched"]?.(dispatched as never);
  };

  const drain = async (args: EveScheduleOptions): Promise<unknown> => {
    await options.queue.runSchedules().orThrow();

    return options.queue.drain({
      // SAFETY: the provider's queue is the app's own; `never` keeps a `Queue`
      // with literal names assignable, and the name is checked there.
      queue: provider.queue as never,
      handler: (payload, job) => fire(args, payload, job),
      budgetMs: options.budgetMs ?? 50_000,
    });
  };

  return (args) => {
    args.waitUntil(drain(args));
  };
}
