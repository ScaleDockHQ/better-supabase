import type { ProblemFormat } from "../core/problem.ts";
import type { Result } from "../core/result.ts";

import { type DbError, dbError } from "../core/errors.ts";
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

/** What `rateLimit()` counts hits with: `createRateLimit()` from `better-supabase/blocks/jobs`. */
export interface RateLimiter {
  check(
    scope: string,
    key: string,
    rule?: RouteRateLimitRule,
  ): PromiseLike<Result<RateLimitVerdict>>;
}

/** The options of the Hono and oRPC `rateLimit()` middleware. */
export interface RateLimitRouteOptions<I> {
  readonly limiter: RateLimiter;
  /** The scope the hits count against, and its rule from `set_rate_limit`. */
  readonly scope: string;
  /** Whose hits these are, such as an API key or a client IP; `undefined` skips the limit. */
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
  /** Let the request through when the limiter fails. Default: answer with its error. */
  readonly failOpen?: boolean;
  /** The app's error body for the 429. */
  readonly problem?: ProblemFormat;
}

export type RateLimitOutcome =
  | { readonly kind: "skip" }
  | { readonly kind: "allow"; readonly headers: Headers }
  | {
      readonly kind: "deny";
      readonly error: DbError;
      readonly headers: Headers;
    };

/** Counts a hit for each request and builds the RateLimit fields or the refusal. */
export function rateLimitGate<I>(
  options: RateLimitRouteOptions<I>,
): (input: I) => Promise<RateLimitOutcome> {
  const policy = options.policy ?? options.scope;
  if (!isRateLimitPolicyName(policy)) {
    throw new TypeError(
      `rateLimit(): "${policy}" can't name a RateLimit policy; pass a printable ASCII \`policy\``,
    );
  }
  const window =
    options.rule === undefined ? undefined : periodSeconds(options.rule.period);
  const policyHeader =
    options.rule === undefined
      ? undefined
      : rateLimitPolicyHeader([
          {
            name: policy,
            quota: options.rule.max,
            ...(window === undefined ? {} : { window }),
          },
        ]);
  const headersFor = (remaining: number, reset?: number): Headers => {
    const headers = new Headers();
    if (policyHeader !== undefined) {
      headers.set("ratelimit-policy", policyHeader);
    }
    headers.set(
      "ratelimit",
      rateLimitHeader([
        { policy, remaining, ...(reset === undefined ? {} : { reset }) },
      ]),
    );
    return headers;
  };

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
        headers: headersFor(Math.max(0, verdict.remaining)),
      };
    }
    const retryAfter = Math.max(1, Math.ceil(verdict.retryAfter));
    const headers = headersFor(0, retryAfter);
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
  };
}
