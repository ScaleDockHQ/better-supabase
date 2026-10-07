import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { SqlClient } from "../../postgres/executor.ts";

import { dbError } from "../../core/errors.ts";
import { type ProblemFormat, problemResponse } from "../../core/problem.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  type BlockTemporalOptions,
  blockCall,
  isRecord,
  run,
  seconds,
  applyTemporal,
} from "../shared.ts";

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
}

export interface RateLimitOptions extends BlockTemporalOptions {
  readonly mappers?: readonly ErrorMapper[];
}

const isTransport = (
  source: SqlClient | BlockTransport,
): source is BlockTransport => "call" in source;

/**
 * Fixed-window limits for keys that aren't claims, over the `rate-limit`
 * module's counters. Pass a service SQL connection (`ctx.postgresAdmin`,
 * `postgres.admin`), or a service-role `BlockTransport` such as
 * `rpcTransport(adminClient)`.
 */
export function createRateLimit(
  source: SqlClient | BlockTransport,
  options: RateLimitOptions = {},
): RateLimit {
  applyTemporal(options);
  const hit = isTransport(source)
    ? overTransport(blockCall(source, undefined, options.mappers))
    : overSql(source);
  return {
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

const overSql =
  (sql: SqlClient): Hit =>
  (scope, key, max, period) =>
    run(async () => {
      const [row] = await sql.queryRaw<{
        allowed: boolean;
        remaining: number;
        retry_after: number;
      }>(
        "select * from better_supabase.hit_rate_limit($1, $2, $3, $4::interval)",
        [scope, key, max, period],
      );
      return {
        allowed: row?.allowed ?? false,
        remaining: row?.remaining ?? 0,
        retryAfter: row?.retry_after ?? 0,
      };
    });

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
