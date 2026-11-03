import type { LanguageModelMiddleware } from "ai";

import type { RateLimit } from "../rate-limit/rate-limit.ts";

import { DbException } from "../core/db-exception.ts";
import { dbError } from "../core/errors.ts";

type TransformParams = NonNullable<LanguageModelMiddleware["transformParams"]>;

/** What `rateLimitMiddleware` hands a `key` or `organizationId` resolver. */
export type RateLimitCall = Parameters<TransformParams>[0];

type Resolved<T> = T | undefined | PromiseLike<T | undefined>;

export interface RateLimitMiddlewareOptions {
  /** The rate-limit client; needs a service role. */
  readonly rateLimit: Pick<RateLimit, "check">;
  /**
   * The scope the model calls count against. Its rule comes from
   * `set_rate_limit`, or from `setRule` for an organization.
   */
  readonly scope: string;
  /**
   * What a call is counted by (a user, a chat, a tenant). A call whose key
   * resolves to `undefined` is not limited.
   */
  readonly key: string | ((call: RateLimitCall) => Resolved<string>);
  /**
   * The organization whose rule from `setRule` applies. A call without one uses
   * the scope's own rule.
   */
  readonly organizationId?:
    | string
    | ((call: RateLimitCall) => Resolved<string>);
  /**
   * Lets the call through when the limit can't be checked. By default the call
   * fails with the database error, so a broken limiter doesn't remove the
   * limit.
   */
  readonly failOpen?: boolean;
}

/**
 * A language model middleware that counts every model call (`generateText`,
 * `streamText` and each agent step) against a rate limit and refuses it before
 * the model runs. A refused call throws a `DbException` whose error is
 * `rate_limited` with code `AI_RATE_LIMITED` and `retryAfter` in seconds, so
 * `aiErrorToDbError` and the problem-details helpers answer it with a 429.
 */
export function rateLimitMiddleware(
  options: RateLimitMiddlewareOptions,
): LanguageModelMiddleware {
  const resolve = async (
    value: string | ((call: RateLimitCall) => Resolved<string>) | undefined,
    call: RateLimitCall,
  ): Promise<string | undefined> =>
    typeof value === "function" ? value(call) : value;

  return {
    transformParams: async (call) => {
      const key = await resolve(options.key, call);

      if (key === undefined) {
        return call.params;
      }

      const organizationId = await resolve(options.organizationId, call);

      const decision = await options.rateLimit.check({
        scope: options.scope,
        key,
        organizationId,
      });

      if (!decision.ok) {
        if (options.failOpen) {
          return call.params;
        }

        throw new DbException(decision.error);
      }

      if (!decision.data.allowed) {
        const retryAfter = Math.max(1, Math.ceil(decision.data.retryAfter));

        throw new DbException(
          dbError("rate_limited", "Too many model calls.", {
            code: "AI_RATE_LIMITED",
            retryAfter,
          }),
        );
      }

      return call.params;
    },
  };
}
