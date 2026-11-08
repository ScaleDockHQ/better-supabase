import type { JobHandler } from "../blocks/queue/types.ts";
import type { BlockTemporalOptions } from "../blocks/shared.ts";
import type { BlockHooks } from "../core/block-hooks.ts";
import type { BlockTransport } from "../core/block-transport.ts";
import type { ErrorMapper } from "../core/errors.ts";
import type { Logger } from "../core/logger.ts";
import type { ProblemFormat } from "../core/problem.ts";
import type { SqlClient } from "../postgres/executor.ts";

import {
  blockCall,
  isRecord,
  run,
  seconds,
  applyTemporal,
} from "../blocks/shared.ts";
import { withBlockHooks } from "../core/block-hooks.ts";
import { sqlTransport } from "../core/block-transport.ts";
import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { AsyncResult } from "../core/result.ts";

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

/** One limit of a `checkAll` call: its own scope and key, and an optional rule. */
export interface RateLimitHit {
  readonly scope: string;
  readonly key: string;
  /** A limit for this call, instead of the scope's rule from `set_rate_limit`. */
  readonly rule?: RateLimitRule;
  /** Uses the rule `setRule` stored for this organization, when there is one. */
  readonly organizationId?: string;
}

/** The answer of `checkAll`: allowed only when every limit allowed the hit. */
export interface RateLimitAllDecision extends RateLimitDecision {
  /** The first limit over its maximum, or `undefined` when the hit counted. */
  readonly blocked?: {
    readonly index: number;
    readonly scope: string;
    readonly key: string;
  };
  /** One decision per limit, in the order of the hits. */
  readonly results: readonly RateLimitDecision[];
}

export interface RateLimit {
  /**
   * Counts a hit of `key` (an API key, a public token, a tenant) against
   * `scope`. The limit is the scope's rule (`set_rate_limit`) unless `rule`
   * gives one.
   */
  check(input: {
    scope: string;
    key: string;
    rule?: RateLimitRule | undefined;
    /** Uses the rule `setRule` stored for this organization, when there is one. */
    organizationId?: string | undefined;
  }): AsyncResult<RateLimitDecision>;
  /**
   * Sets the limit of `scope` for one organization
   * (`set_organization_rate_limit`). It replaces the scope's own rule for hits
   * that pass `organizationId`; other hits keep the scope's rule. `max: null`
   * removes the organization's rule. Needs a service role.
   */
  setRule(input: {
    scope: string;
    organizationId: string;
    max: number | null;
    /** Seconds, or a Postgres interval such as `1 minute`. Default one minute. */
    period?: number | string | undefined;
  }): AsyncResult<void>;
  /**
   * Counts one hit against several limits in one database round trip, such as a
   * per-user, a per-IP and a per-organization limit. The hit counts only when
   * every limit allows it; a refusal leaves every counter as it was. Each hit
   * needs its own scope and key: two limits on the same key take two scopes,
   * such as `login:minute` and `login:day`. `remaining` is the lowest of the
   * limits and `retryAfter` the longest wait of the refusing ones.
   */
  checkAll(hits: readonly RateLimitHit[]): AsyncResult<RateLimitAllDecision>;
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

interface RateLimitBase extends BlockTemporalOptions {
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

export type RateLimitOptions = RateLimitSource & RateLimitBase;

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

  const hitAll: HitAll =
    options.transport === undefined
      ? (hits) =>
          run(async () =>
            decodeAll(await checkRateLimits(options.sql, hits), hits),
          )
      : (hits) =>
          call("check_rate_limits", { hits }, (value) =>
            decodeAll(value, hits),
          );

  const setOrganizationRule: SetRule =
    options.transport === undefined
      ? (scope, organizationId, max, period) =>
          run(async () => {
            await options.sql.queryRaw(
              "select better_supabase.set_organization_rate_limit($1, $2::uuid, $3, coalesce($4::interval, interval '1 minute'))",
              [scope, organizationId, max, period],
            );
          })
      : (scope, organizationId, max, period) =>
          call(
            "set_organization_rate_limit",
            {
              scope,
              organization_id: organizationId,
              max_requests: max,
              period: period ?? undefined,
            },
            () => undefined,
          );

  const client: RateLimit = {
    purge: (purgeOptions = {}) =>
      call("purge_rate_limits", { batch: purgeOptions.batch }, (value) =>
        Number(value ?? 0),
      ),
    purgeJob: (jobOptions) => async () => hooked.purge(jobOptions).orThrow(),
    setRule: ({ scope, organizationId, max, period }) => {
      if (max !== null && (!Number.isInteger(max) || max < 1)) {
        return AsyncResult.err(
          dbError(
            "invalid_input",
            "A rate limit's max must be a positive integer",
          ),
        );
      }

      return setOrganizationRule(
        scope,
        organizationId,
        max,
        period === undefined ? null : seconds(period),
      );
    },
    check: ({ scope, key, rule, organizationId }) => {
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
        organizationId ?? null,
      );
    },
    checkAll: (hits) => {
      if (hits.length === 0) {
        return AsyncResult.err(
          dbError("invalid_input", "checkAll needs at least one limit"),
        );
      }

      const rows: LimitRow[] = [];

      for (const hit of hits) {
        if (
          hit.rule !== undefined &&
          (!Number.isInteger(hit.rule.max) || hit.rule.max < 1)
        ) {
          return AsyncResult.err(
            dbError(
              "invalid_input",
              "A rate limit's max must be a positive integer",
            ),
          );
        }

        rows.push({
          scope: hit.scope,
          key: hit.key,
          ...(hit.organizationId === undefined
            ? {}
            : { organization_id: hit.organizationId }),
          ...(hit.rule === undefined
            ? {}
            : { max_requests: hit.rule.max, period: seconds(hit.rule.period) }),
        });
      }

      return hitAll(rows);
    },
  };

  const hooked = withBlockHooks(client, options.hooks, {
    block: "rate-limit",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}

interface LimitRow {
  readonly scope: string;
  readonly key: string;
  readonly max_requests?: number;
  readonly period?: string;
  readonly organization_id?: string;
}

type SetRule = (
  scope: string,
  organizationId: string,
  max: number | null,
  period: string | null,
) => AsyncResult<void>;

type HitAll = (hits: readonly LimitRow[]) => AsyncResult<RateLimitAllDecision>;

const numberOr = (value: unknown, fallback: number): number => {
  const parsed = Number(value ?? fallback);

  return Number.isFinite(parsed) ? parsed : fallback;
};

function decodeOne(value: unknown): RateLimitDecision {
  const row = isRecord(value) ? value : {};

  return {
    allowed: row["allowed"] === true,
    remaining: numberOr(row["remaining"], 0),
    retryAfter: numberOr(row["retry_after"], 0),
  };
}

/** Reads `check_rate_limits`' answer; a missing one is a refusal. */
function decodeAll(
  value: unknown,
  hits: readonly LimitRow[],
): RateLimitAllDecision {
  const row = isRecord(value) ? value : {};

  const results = Array.isArray(row["results"])
    ? row["results"].map(decodeOne)
    : [];

  const allowed = row["allowed"] === true && results.length === hits.length;

  const index =
    typeof row["blocked"] === "number" ? row["blocked"] : allowed ? -1 : 0;

  const blocked = hits[index];

  return {
    allowed,
    remaining:
      results.length === 0
        ? 0
        : Math.min(...results.map((each) => each.remaining)),
    retryAfter: allowed ? 0 : numberOr(row["retry_after"], 0),
    ...(allowed || blocked === undefined
      ? {}
      : { blocked: { index, scope: blocked.scope, key: blocked.key } }),
    results,
  };
}

/** One `check_rate_limits` call over SQL. */
async function checkRateLimits(
  sql: SqlClient,
  hits: readonly LimitRow[],
): Promise<unknown> {
  const [row] = await sql.queryRaw<{ result: unknown }>(
    "select better_supabase.check_rate_limits($1::jsonb) as result",
    [JSON.stringify(hits)],
  );

  return row?.result;
}

type Hit = (
  scope: string,
  key: string,
  max: number | null,
  period: string | null,
  organizationId: string | null,
) => AsyncResult<RateLimitDecision>;

const overTransport =
  (call: ReturnType<typeof blockCall>): Hit =>
  (scope, key, max, period, organizationId) =>
    call(
      "check_rate_limit",
      {
        scope,
        key,
        max_requests: max ?? undefined,
        period: period ?? undefined,
        organization_id: organizationId ?? undefined,
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
  organizationId: string | null = null,
): Promise<RateLimitDecision> {
  const [row] = await sql.queryRaw<{
    allowed: boolean;
    remaining: number;
    retry_after: number;
  }>(
    "select * from better_supabase.hit_rate_limit($1, $2, $3, $4::interval, $5::uuid)",
    [scope, key, max, period, organizationId],
  );

  return {
    allowed: row?.allowed ?? false,
    remaining: row?.remaining ?? 0,
    retryAfter: row?.retry_after ?? 0,
  };
}

const overSql =
  (sql: SqlClient): Hit =>
  (scope, key, max, period, organizationId) =>
    run(() => hitRateLimit(sql, scope, key, max, period, organizationId));

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
