import type { DbError } from "../../core/errors.ts";
import type {
  QueueMessageBody,
  ScheduleProvider,
  StoredSchedule,
} from "./backends.ts";

import { nextCronRun } from "../../core/cron.ts";
import { DbException, dbError, dbErrorOfStatus } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { temporal } from "../../core/temporal-required.ts";
import { nowInstant } from "../../core/temporal.ts";
import { errorText } from "../shared.ts";
import { vercelTopicOf } from "./vercel-queue.ts";
import {
  vercelCronOf,
  vercelNamespaceOf,
  vercelScheduleNameFrom,
  vercelScheduleNameOf,
} from "./vercel-schedules.ts";

/** A schedule's expression in Vercel Schedules. */
export type VercelScheduleExpression =
  | { readonly type: "cron"; readonly cron: string }
  | { readonly type: "single"; readonly at: string };

/** What the scheduler reads of a `Schedule` from `@vercel/schedules`. */
export interface VercelSchedule {
  readonly name: string;
  readonly namespace: string;
  readonly expression: VercelScheduleExpression;
  readonly timezone: string;
  readonly target: { readonly type: string; readonly topic?: string };
  readonly source: string;
  readonly createdAt: number;
}

/** The arguments of `create` and `update`, as `@vercel/schedules` takes them. */
export interface VercelScheduleWrite {
  readonly name: string;
  readonly namespace?: string;
  readonly expression: { readonly type: "cron"; readonly cron: string };
  readonly timezone?: string;
  readonly jitter?: number;
  readonly target: { readonly topic: string };
  readonly payload?: unknown;
}

/**
 * The part of `Schedules` (or a `SchedulesClient`) from `@vercel/schedules` the
 * scheduler calls, typed structurally so the package stays an optional peer.
 */
export interface VercelSchedulesClient {
  create(params: VercelScheduleWrite): PromiseLike<VercelSchedule>;
  update(params: VercelScheduleWrite): PromiseLike<VercelSchedule>;
  delete(params: {
    readonly name: string;
    readonly namespace?: string;
  }): PromiseLike<unknown>;
  list(params?: {
    readonly namespace?: string;
    readonly cursor?: string;
    readonly limit?: number;
  }): PromiseLike<{
    readonly data: readonly VercelSchedule[];
    readonly cursor: string | null;
  }>;
}

/**
 * The payload of a dynamic schedule `vercelScheduler` writes: the job body
 * `vercelQueueRoute` reads, plus what the bridge route needs.
 */
export interface VercelScheduleBody extends QueueMessageBody {
  /** The schedule name as `jobs.schedule` took it. */
  readonly name: string;
  /** The queue the run goes to. */
  readonly queue: string;
  readonly probe?: string;
}

export interface VercelSchedulerOptions {
  /**
   * The Vercel Queues topic every run publishes to, read by
   * `vercelScheduleBridgeRoute`, which checks the probe and enqueues the run on
   * a Supabase queue. Without it a run publishes to its job's topic
   * (`vercelTopicOf(queue)`), which only a Vercel Queues backend reads.
   */
  readonly bridge?: string;
  /** Minutes Vercel spreads each run over, 1 to 15. Default: the plan's. */
  readonly jitter?: number;
  /**
   * The namespace of schedules without a tenant. Default `better-supabase`,
   * apart from the `default` namespace that static schedules use.
   */
  readonly namespace?: string;
  /** Fills each listed schedule's next run. */
  readonly now?: () => Temporal.Instant;
}

const MAX_PAYLOAD = 16 * 1024;
const PAGE = 100;

const INVALID = new Set([
  "bad_request",
  "invalid_cron_expression",
  "invalid_jitter",
  "jitter_exceeds_cadence",
  "payload_too_large",
  "schedule_type_change_not_allowed",
  "static_schedule",
]);

/** A `SchedulesApiError` as the scheduler reads it. */
interface ApiError {
  readonly status: number;
  readonly code?: string;
  readonly message: string;
  readonly retryAfter?: number;
}

function apiErrorOf(cause: unknown): ApiError | undefined {
  return !(cause instanceof DbException) &&
    isRecord(cause) &&
    typeof cause["status"] === "number" &&
    typeof cause["message"] === "string"
    ? {
        status: cause["status"],
        message: cause["message"],
        ...(typeof cause["code"] === "string" ? { code: cause["code"] } : {}),
        ...(typeof cause["retryAfter"] === "number"
          ? { retryAfter: cause["retryAfter"] }
          : {}),
      }
    : undefined;
}

const codeOf = (cause: unknown): string | undefined => apiErrorOf(cause)?.code;

/**
 * The `DbError` for a `SchedulesApiError`: `rate_limited` keeps `retryAfter`, a
 * static schedule, an invalid cron or a payload past 16 KB is
 * `invalid_request`, and the rest follow the HTTP status.
 */
export function vercelSchedulesErrorOf(cause: unknown): DbError | undefined {
  const api = apiErrorOf(cause);

  if (api === undefined) {
    return undefined;
  }

  const message = `Vercel Schedules: ${api.message}`;
  const code = api.code;

  if (code === "rate_limited") {
    return dbError("rate_limited", message, {
      code,
      ...(api.retryAfter === undefined ? {} : { retryAfter: api.retryAfter }),
    });
  }

  if (code === "service_unavailable") {
    return dbError("network", message, {
      code,
      ...(api.retryAfter === undefined ? {} : { retryAfter: api.retryAfter }),
    });
  }

  if (code !== undefined && INVALID.has(code)) {
    return dbError("invalid_request", message, { code });
  }

  if (code === "feature_blocked" || code === "schedule_limit_exceeded") {
    return dbError("quota_exceeded", message, { code });
  }

  if (code === "schedule_already_exists") {
    return dbError("conflict", message, { code });
  }

  return dbErrorOfStatus(
    api.status,
    message,
    code === undefined ? {} : { code },
  );
}

/** Rethrows a `SchedulesApiError` as a `DbException`, anything else as it is. */
function rethrow(cause: unknown): never {
  const error = vercelSchedulesErrorOf(cause);

  throw error === undefined ? cause : new DbException(error);
}

const invalid = (message: string): DbException =>
  new DbException(dbError("invalid_request", message));

/**
 * Vercel Schedules as the scheduler of `createQueue`: each queue schedule is a
 * dynamic schedule whose payload is the job body. Pass `Schedules` from
 * `@vercel/schedules`. A tenant's schedules live in its own namespace
 * (`vercelNamespaceOf`), the rest in `options.namespace`. Without `bridge` runs
 * publish to the job's topic, so the queue must be Vercel Queues and a schedule
 * can't name a probe; with `bridge` they publish to that topic, for
 * `vercelScheduleBridgeRoute`. Vercel returns no payloads, so a listed schedule
 * has no payload or probe and `ensureSchedules` writes every definition again.
 */
export function vercelScheduler(
  client: VercelSchedulesClient,
  options: VercelSchedulerOptions = {},
): ScheduleProvider {
  const home = options.namespace ?? "better-supabase";
  const now = options.now ?? nowInstant;

  if (options.bridge !== undefined) {
    vercelTopicOf(options.bridge);
  }

  const namespaceOf = async (tenant: string | undefined): Promise<string> => {
    if (tenant === undefined) {
      return home;
    }

    const namespace = await vercelNamespaceOf(tenant);

    if (namespace === home) {
      throw invalid(
        `The tenant "${tenant}" maps to the namespace of schedules without a tenant; pass vercelScheduler another namespace`,
      );
    }

    return namespace;
  };

  const write = async (params: VercelScheduleWrite): Promise<void> => {
    try {
      await client.update(params);

      return;
    } catch (cause) {
      if (codeOf(cause) !== "not_found") {
        rethrow(cause);
      }
    }

    try {
      await client.create(params);
    } catch (cause) {
      if (codeOf(cause) !== "schedule_already_exists") {
        rethrow(cause);
      }

      // Another writer created it between the update and the create.
      await client.update(params).then(undefined, rethrow);
    }
  };

  const page = async (namespace: string, cursor: string | undefined) => {
    try {
      return await client.list({
        namespace,
        limit: PAGE,
        ...(cursor === undefined ? {} : { cursor }),
      });
    } catch (cause) {
      return rethrow(cause);
    }
  };

  async function* each(namespace: string): AsyncGenerator<VercelSchedule> {
    let cursor: string | undefined;

    do {
      const listed = await page(namespace, cursor);

      yield* listed.data;
      cursor = listed.cursor ?? undefined;
    } while (cursor !== undefined);
  }

  const storedOf = (
    schedule: VercelSchedule,
    name: string,
    tenant: string | undefined,
  ): StoredSchedule => {
    const cron =
      schedule.expression.type === "cron" ? schedule.expression.cron : "";

    let nextRun: Temporal.Instant | null = null;

    try {
      nextRun = nextCronRun(cron, schedule.timezone, now());
    } catch {
      nextRun = null;
    }

    const topic = schedule.target.topic;

    return {
      name,
      cron,
      timeZone: schedule.timezone,
      queue: options.bridge === undefined && topic !== undefined ? topic : null,
      tenant: tenant ?? null,
      nextRun,
      lastRun: null,
      leasedUntil: null,
      createdAt: temporal().Instant.fromEpochMilliseconds(schedule.createdAt),
      probe: null,
    };
  };

  return {
    apiVersion: 1,
    name:
      options.bridge === undefined
        ? "vercel-schedules"
        : "vercel-schedules-bridge",
    ...(options.bridge === undefined
      ? { delivers: "vercel-queues" as const }
      : {}),
    async schedule(
      name,
      cron,
      queue,
      payload,
      timeZone,
      _nextRun,
      tenant,
      probe,
    ) {
      if (probe !== undefined && options.bridge === undefined) {
        throw invalid(
          `The schedule "${name}" names the probe ${probe}, but a Vercel schedule that publishes to the job's topic runs without asking the database. Pass vercelScheduler(client, { bridge }) with vercelScheduleBridgeRoute, or use the drain scheduler`,
        );
      }

      let expression: string;

      try {
        expression = vercelCronOf(cron);
      } catch (cause) {
        throw invalid(errorText(cause));
      }

      const body: VercelScheduleBody = {
        payload: payload ?? {},
        max_attempts: 5,
        name,
        queue,
        ...(probe === undefined ? {} : { probe }),
      };

      if (new TextEncoder().encode(JSON.stringify(body)).length > MAX_PAYLOAD) {
        throw invalid(
          `The payload of the schedule "${name}" is larger than the 16 KB Vercel Schedules keeps`,
        );
      }

      await write({
        name: await vercelScheduleNameOf(name),
        namespace: await namespaceOf(tenant),
        expression: { type: "cron", cron: expression },
        timezone: timeZone,
        ...(options.jitter === undefined ? {} : { jitter: options.jitter }),
        target: { topic: options.bridge ?? vercelTopicOf(queue) },
        payload: body,
      });
    },
    async unschedule(name, tenant) {
      try {
        await client.delete({
          name: await vercelScheduleNameOf(name),
          namespace: await namespaceOf(tenant),
        });

        return true;
      } catch (cause) {
        if (codeOf(cause) === "not_found") {
          return false;
        }

        return rethrow(cause);
      }
    },
    async listSchedules(filter) {
      const listed: StoredSchedule[] = [];

      for await (const schedule of each(await namespaceOf(filter.tenant))) {
        const name = vercelScheduleNameFrom(schedule.name);

        if (
          name !== null &&
          schedule.source !== "static" &&
          (filter.prefix === undefined || name.startsWith(filter.prefix))
        ) {
          listed.push(storedOf(schedule, name, filter.tenant));
        }
      }

      return listed.toSorted((a, b) => (a.name < b.name ? -1 : 1));
    },
    async unscheduleTenant(tenant) {
      const namespace = await namespaceOf(tenant);
      const names: string[] = [];

      for await (const schedule of each(namespace)) {
        if (schedule.source !== "static") {
          names.push(schedule.name);
        }
      }

      let removed = 0;

      for (const name of names) {
        try {
          await client.delete({ name, namespace });
          removed += 1;
        } catch (cause) {
          const code = codeOf(cause);

          if (code !== "not_found" && code !== "schedule_single_at_passed") {
            rethrow(cause);
          }
        }
      }

      return removed;
    },
  };
}
