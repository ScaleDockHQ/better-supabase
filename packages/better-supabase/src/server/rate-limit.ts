import type { DbError } from "../core/errors.ts";
import type { ProblemFormat } from "../core/problem.ts";
import type {
  RateLimitPolicy,
  RateLimitState,
} from "../core/ratelimit-headers.ts";
import type { Result } from "../core/result.ts";

import { dbError } from "../core/errors.ts";
import {
  isRateLimitPolicyName,
  periodSeconds,
  rateLimitHeader,
  rateLimitPolicyHeader,
} from "../core/ratelimit-headers.ts";

/** A counted hit, as `createRateLimit().check` answers. */
export interface RateLimitVerdict {
  readonly allowed: boolean;
  readonly remaining: number;
  /** Seconds until the window ends; 0 when allowed. */
  readonly retryAfter: number;
}

/** A limit for one route instead of the scope's stored rule. */
export interface RouteRateLimitRule {
  readonly max: number;
  /** Seconds, or a Postgres interval such as `1 minute`. */
  readonly period: number | string;
}

/** One limit of a `hits` list: its own scope and key, and an optional rule. */
export interface RouteRateLimitHit {
  readonly scope: string;
  readonly key: string;
  readonly rule?: RouteRateLimitRule;
}

/** What `checkAll` answers: one verdict per hit, in the order of the hits. */
export interface RateLimitAllVerdict extends RateLimitVerdict {
  readonly results: readonly RateLimitVerdict[];
}

/**
 * What `rateLimit()` counts hits with: `createRateLimit()` from
 * `better-supabase/rate-limit`.
 */
export interface RateLimiter {
  check(
    scope: string,
    key: string,
    rule?: RouteRateLimitRule,
  ): PromiseLike<Result<RateLimitVerdict>>;
}

/** A limiter that counts one hit against several limits, as `checkAll` does. */
export interface MultiRateLimiter {
  checkAll(
    hits: readonly RouteRateLimitHit[],
  ): PromiseLike<Result<RateLimitAllVerdict>>;
}

interface RateLimitCommonOptions {
  /**
   * Let the request through when the limiter fails. Default: answer with its
   * error.
   */
  readonly failOpen?: boolean;
  /** The app's error body for the 429. */
  readonly problem?: ProblemFormat;
}

/** One limit: a scope, whose key the request names. */
export interface SingleRateLimitOptions<I> extends RateLimitCommonOptions {
  readonly limiter: RateLimiter;
  /** The scope the hits count against, and its rule from `set_rate_limit`. */
  readonly scope: string;
  /**
   * Whose hits these are, such as an API key or a client IP; `undefined` skips
   * the limit.
   */
  readonly key: (
    input: I,
  ) => string | undefined | PromiseLike<string | undefined>;
  /**
   * The route's limit instead of the scope's rule. With it, responses also
   * carry `RateLimit-Policy`.
   */
  readonly rule?: RouteRateLimitRule;
  /** The policy name in the headers. Default: `scope`. */
  readonly policy?: string;
}

/**
 * Several limits counted in one `checkAll` round trip, such as a per-user, a
 * per-IP and a per-organization limit. The call counts only when every limit
 * allows it.
 */
export interface MultiRateLimitOptions<I> extends RateLimitCommonOptions {
  readonly limiter: MultiRateLimiter;
  /**
   * The limits this request counts against; each scope names its policy in the
   * headers. An empty list skips the limit.
   */
  readonly hits: (
    input: I,
  ) => readonly RouteRateLimitHit[] | PromiseLike<readonly RouteRateLimitHit[]>;
}

/** The options of the Hono and oRPC `rateLimit()` middleware. */
export type RateLimitRouteOptions<I> =
  | SingleRateLimitOptions<I>
  | MultiRateLimitOptions<I>;

export type RateLimitOutcome =
  | { readonly kind: "skip" }
  | { readonly kind: "allow"; readonly headers: Headers }
  | {
      readonly kind: "deny";
      readonly error: DbError;
      readonly headers: Headers;
    };

function assertPolicyName(policy: string): void {
  if (!isRateLimitPolicyName(policy)) {
    throw new TypeError(
      `rateLimit(): "${policy}" can't name a RateLimit policy; pass a printable ASCII \`policy\``,
    );
  }
}

function policyOf(name: string, rule: RouteRateLimitRule): RateLimitPolicy {
  const window = periodSeconds(rule.period);

  return { name, quota: rule.max, ...(window === undefined ? {} : { window }) };
}

function limitHeaders(
  policies: readonly RateLimitPolicy[],
  states: readonly RateLimitState[],
): Headers {
  const headers = new Headers();

  if (policies.length > 0) {
    headers.set("ratelimit-policy", rateLimitPolicyHeader(policies));
  }

  headers.set("ratelimit", rateLimitHeader(states));

  return headers;
}

function refusal(
  verdict: RateLimitVerdict,
  policies: readonly RateLimitPolicy[],
  states: (retryAfter: number) => readonly RateLimitState[],
): RateLimitOutcome {
  const retryAfter = Math.max(1, Math.ceil(verdict.retryAfter));
  const headers = limitHeaders(policies, states(retryAfter));
  headers.set("retry-after", String(retryAfter));

  return {
    kind: "deny",
    error: dbError(
      "rate_limited",
      `Too many requests. Retry after ${retryAfter} seconds.`,
      { retryAfter },
    ),
    headers,
  };
}

function singleGate<I>(
  options: SingleRateLimitOptions<I>,
): (input: I) => Promise<RateLimitOutcome> {
  const policy = options.policy ?? options.scope;
  assertPolicyName(policy);

  const policies =
    options.rule === undefined ? [] : [policyOf(policy, options.rule)];

  return async (input) => {
    const key = await options.key(input);

    if (key === undefined) {
      return { kind: "skip" };
    }

    const checked = await options.limiter.check(
      options.scope,
      key,
      options.rule,
    );

    if (!checked.ok) {
      return options.failOpen
        ? { kind: "skip" }
        : { kind: "deny", error: checked.error, headers: new Headers() };
    }

    const verdict = checked.data;

    if (verdict.allowed) {
      return {
        kind: "allow",
        headers: limitHeaders(policies, [
          { policy, remaining: Math.max(0, verdict.remaining) },
        ]),
      };
    }

    return refusal(verdict, policies, (reset) => [
      { policy, remaining: 0, reset },
    ]);
  };
}

function multiGate<I>(
  options: MultiRateLimitOptions<I>,
): (input: I) => Promise<RateLimitOutcome> {
  return async (input) => {
    const hits = await options.hits(input);

    if (hits.length === 0) {
      return { kind: "skip" };
    }

    for (const hit of hits) {
      assertPolicyName(hit.scope);
    }

    const checked = await options.limiter.checkAll(hits);

    if (!checked.ok) {
      return options.failOpen
        ? { kind: "skip" }
        : { kind: "deny", error: checked.error, headers: new Headers() };
    }

    const verdict = checked.data;

    const policies = hits.flatMap((hit) =>
      hit.rule === undefined ? [] : [policyOf(hit.scope, hit.rule)],
    );

    const states = (reset?: number): RateLimitState[] =>
      hits.map((hit, index) => {
        const result = verdict.results[index];

        return result === undefined || result.allowed
          ? {
              policy: hit.scope,
              remaining: Math.max(0, result?.remaining ?? 0),
            }
          : {
              policy: hit.scope,
              remaining: 0,
              ...(reset === undefined
                ? {}
                : { reset: Math.max(1, Math.ceil(result.retryAfter)) }),
            };
      });

    if (verdict.allowed) {
      return { kind: "allow", headers: limitHeaders(policies, states()) };
    }

    return refusal(verdict, policies, (retryAfter) => states(retryAfter));
  };
}

/** Counts a hit for each request and builds the RateLimit fields or the refusal. */
export function rateLimitGate<I>(
  options: RateLimitRouteOptions<I>,
): (input: I) => Promise<RateLimitOutcome> {
  return "hits" in options ? multiGate(options) : singleGate(options);
}
