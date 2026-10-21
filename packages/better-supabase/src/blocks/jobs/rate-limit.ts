import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { ProblemFormat } from "../../core/problem.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { JobHandler } from "./types.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { sqlTransport } from "../../core/block-transport.ts";
import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { AsyncResult } from "../../core/result.ts";
import { blockCall, isRecord, run, seconds, applyTemporal } from "../shared.ts";

// ---------------------------------------------------------------------------
// Rate limits for route handlers (SQL module `rate-limit`)

/** One counted hit: whether it is allowed, and when to retry if not. */
export interface RateLimitDecision {
  readonly allowed: boolean;
  /** Hits left in the current window. */
  readonly remaining: number;
  /** Seconds until the window ends; 0 when allowed. */
  readonly retryAfter: number;
}

/** A limit for one call, instead of the scope's rule from `set_rate_limit`. */
export interface RateLimitRule {
  readonly max: number;
  /** Seconds, or a Postgres interval such as `1 minute`. */
  readonly period: number | string;
}

export interface RateLimit {
  /**
   * Counts a hit of `key` (an API key, a public token, a tenant) against
   * `scope`. The limit is the scope's rule (`set_rate_limit`) unless `rule`
   * gives one.
   */
  check(
    scope: string,
    key: string,
    rule?: RateLimitRule,
  ): AsyncResult<RateLimitDecision>;
  /**
   * Deletes up to `batch` counters whose window ended (`purge_rate_limits`);
   * returns how many.
   */
  purge(options?: { readonly batch?: number }): AsyncResult<number>;
  /** A job handler that runs `purge`; schedule it hourly. */
  purgeJob(options?: { readonly batch?: number }): JobHandler<unknown>;
}

/** Where `createRateLimit` keeps its counters: a transport or a SQL connection. */
export type RateLimitSource =
  | {
      /**
       * A service-role transport, such as `rpcTransport(adminClient)`, over the
       * `rate-limit` module's functions.
       */
      readonly transport: BlockTransport;
      readonly sql?: never;
    }
  | {
      /** A service SQL connection: `postgres.admin` or `ctx.postgresAdmin`. */
      readonly sql: SqlClient;
      readonly transport?: never;
    };

export interface RateLimitSettings extends BlockTemporalOptions {
  /**
   * The schema the functions live in, over a transport. Defaults to
   * `better_supabase`.
   */
  readonly schema?: string;
  /** Error mappers that run before the built-in ones. */
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<RateLimit>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export type RateLimitOptions = RateLimitSource & RateLimitSettings;

/**
 * Fixed-window limits for keys that aren't claims, over the `rate-limit`
 * module's counters. Pass `sql`, a service SQL connection (`ctx.postgresAdmin`,
 * `postgres.admin`), or `transport`, a service-role `BlockTransport` such as
 * `rpcTransport(adminClient)`.
 */
export function createRateLimit(options: RateLimitOptions): RateLimit {
  applyTemporal(options);

  const call =
    options.transport === undefined
      ? blockCall(sqlTransport(options.sql), undefined, options.mappers)
      : blockCall(options.transport, options.schema, options.mappers);

  const hit =
    options.transport === undefined
      ? overSql(options.sql)
      : overTransport(call);

  const client: RateLimit = {
    purge: (purgeOptions = {}) =>
      call("purge_rate_limits", { batch: purgeOptions.batch }, (value) =>
        Number(value ?? 0),
      ),
    purgeJob: (jobOptions) => async () => hooked.purge(jobOptions).orThrow(),
    check: (scope, key, rule) => {
      if (rule !== undefined && (!Number.isInteger(rule.max) || rule.max < 1)) {
        return AsyncResult.err(
          dbError(
            "invalid_input",
            "A rate limit's max must be a positive integer",
          ),
        );
      }

      return hit(
        scope,
        key,
        rule?.max ?? null,
        rule === undefined ? null : seconds(rule.period),
      );
    },
  };

  const hooked = withBlockHooks(client, options.hooks, {
    block: "rate-limit",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}

type Hit = (
  scope: string,
  key: string,
  max: number | null,
  period: string | null,
) => AsyncResult<RateLimitDecision>;

const overTransport =
  (call: ReturnType<typeof blockCall>): Hit =>
  (scope, key, max, period) =>
    call(
      "check_rate_limit",
      {
        scope,
        key,
        max_requests: max ?? undefined,
        period: period ?? undefined,
      },
      (value) => {
        const row = isRecord(value) ? value : {};

        return {
          allowed: row["allowed"] === true,
          remaining: Number(row["remaining"] ?? 0),
          retryAfter: Number(row["retry_after"] ?? 0),
        };
      },
    );

/**
 * One `hit_rate_limit` call: whether the hit is allowed, what is left and when
 * to retry.
 */
export async function hitRateLimit(
  sql: SqlClient,
  scope: string,
  key: string,
  max: number | null,
  period: string | null,
): Promise<RateLimitDecision> {
  const [row] = await sql.queryRaw<{
    allowed: boolean;
    remaining: number;
    retry_after: number;
  }>("select * from better_supabase.hit_rate_limit($1, $2, $3, $4::interval)", [
    scope,
    key,
    max,
    period,
  ]);

  return {
    allowed: row?.allowed ?? false,
    remaining: row?.remaining ?? 0,
    retryAfter: row?.retry_after ?? 0,
  };
}

const overSql =
  (sql: SqlClient): Hit =>
  (scope, key, max, period) =>
    run(() => hitRateLimit(sql, scope, key, max, period));

/** A `problem+json` 429 with `Retry-After`, for a refused `check`. */
export function rateLimited(
  decision: Pick<RateLimitDecision, "retryAfter">,
  options: {
    readonly instance?: string;
    readonly detail?: string;
    readonly problem?: ProblemFormat;
  } = {},
): Response {
  const retryAfter = Math.max(1, Math.ceil(decision.retryAfter));

  return problemResponse(
    dbError(
      "rate_limited",
      options.detail ?? `Too many requests. Retry after ${retryAfter} seconds.`,
      { retryAfter },
    ),
    {
      ...(options.instance === undefined ? {} : { instance: options.instance }),
      format: options.problem,
    },
  );
}
