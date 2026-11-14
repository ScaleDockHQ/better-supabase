import type { DbError } from "../core/errors.ts";
import type { ProblemFormat } from "../core/problem.ts";

import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";

/**
 * A check that runs before a route handler: `undefined` lets the request
 * through, and a `Response` is the refusal to send instead.
 */
export type VercelGuard = (request: Request) => Promise<Response | undefined>;

/** What to do when the Vercel service can't answer. */
export type VercelGuardErrorPolicy = "allow" | "deny";

/** BotID's verdict on a request, typed structurally. */
export interface BotIdVerdict {
  readonly isHuman: boolean;
  readonly isBot: boolean;
  readonly isVerifiedBot: boolean;
  readonly bypassed: boolean;
  /** The verified bot's name, such as a search engine crawler. */
  readonly verifiedBotName?: string | undefined;
}

/** The `checkBotId` options from `botid/server`, typed structurally. */
export interface BotIdConfig {
  readonly developmentOptions?: {
    readonly bypass?: "HUMAN" | "BAD-BOT" | "GOOD-BOT" | "ALLOWED" | undefined;
    readonly isDevelopment?: boolean;
  };
  readonly advancedOptions?: {
    readonly checkLevel?: "deepAnalysis" | "basic";
    readonly extraAllowedHosts?: string[];
    readonly headers?: Record<string, string>;
    readonly returnResponseHeaders?: boolean;
    readonly vercelOidcToken?: string;
  };
}

/**
 * `checkBotId` from `botid/server`, typed structurally; pass `import {
 * checkBotId } from "botid/server"`.
 */
export type CheckBotId = (config?: BotIdConfig) => Promise<BotIdVerdict>;

/** The `checkRateLimit` options this module passes, typed structurally. */
export interface FirewallRateLimitCheckOptions {
  rateLimitKey?: string;
  request?: Request;
  timeout?: number;
}

/** What `checkRateLimit` from `@vercel/firewall` answers, typed structurally. */
export interface FirewallRateLimitResult {
  readonly rateLimited: boolean;
  readonly error?: "not-found" | "blocked";
}

/**
 * `checkRateLimit` from `@vercel/firewall`, typed structurally; pass `import {
 * checkRateLimit } from "@vercel/firewall"`.
 */
export type CheckRateLimit = (
  rateLimitId: string,
  options?: FirewallRateLimitCheckOptions,
) => Promise<FirewallRateLimitResult>;

export interface BotIdCheckOptions {
  readonly checkBotId: CheckBotId;
  /**
   * Let verified bots through (search engines, monitoring services that
   * identify themselves). Default: false, so a sign-up form refuses them too.
   */
  readonly allowVerifiedBots?: boolean;
  /** Passed to `checkBotId`. */
  readonly config?: BotIdConfig;
  /**
   * When `checkBotId` throws: `deny` (the default) refuses with a 503, so an
   * outage can't open the route to bots; `allow` lets the request through.
   */
  readonly onError?: VercelGuardErrorPolicy;
}

export interface BotIdGuardOptions extends BotIdCheckOptions {
  /** The app's error body. Defaults to RFC 9457 Problem Details. */
  readonly problem?: ProblemFormat;
}

export interface FirewallRateLimitOptions {
  readonly checkRateLimit: CheckRateLimit;
  /** The rate limit rule's id, as set in the Vercel Firewall. */
  readonly id: string;
  /**
   * The entity the limit counts, such as the email address of a sign-in
   * attempt. Defaults to the client IP, which the Firewall reads itself.
   */
  readonly key?: (request: Request) => string | undefined;
  /** The `Retry-After` seconds of a 429. Default: 60. */
  readonly retryAfter?: number;
  /**
   * Milliseconds before `checkRateLimit` gives up, which then counts as a
   * failed check. Unset, it waits as long as the Firewall takes.
   */
  readonly timeout?: number;
  /** The app's error body. Defaults to RFC 9457 Problem Details. */
  readonly problem?: ProblemFormat;
  /**
   * When `checkRateLimit` throws or the rule id is not configured: `allow` (the
   * default) lets the request through, `deny` refuses with a 503.
   */
  readonly onError?: VercelGuardErrorPolicy;
}

const DEFAULT_RETRY_AFTER = 60;

const instanceOf = (request: Request): string => new URL(request.url).pathname;

function headersOf(request: Request): Record<string, string> {
  const headers: Record<string, string> = {};

  for (const [name, value] of request.headers) {
    headers[name] = value;
  }

  return headers;
}

/** BotID's options for one request, with its headers unless the app set them. */
function configFor(
  config: BotIdConfig | undefined,
  request: Request | undefined,
): BotIdConfig | undefined {
  if (request === undefined || config?.advancedOptions?.headers !== undefined) {
    return config;
  }

  return {
    ...config,
    advancedOptions: {
      ...config?.advancedOptions,
      headers: headersOf(request),
    },
  };
}

async function botIdError(
  options: BotIdCheckOptions,
  request: Request | undefined,
): Promise<DbError | undefined> {
  let verdict: BotIdVerdict;

  try {
    verdict = await options.checkBotId(configFor(options.config, request));
  } catch {
    return options.onError === "allow"
      ? undefined
      : dbError("network", "The bot check could not run", {
          hint: "BOT_CHECK_FAILED",
        });
  }

  if (!verdict.isBot || (verdict.isVerifiedBot && options.allowVerifiedBots)) {
    return undefined;
  }

  return dbError("forbidden", "The request looks automated", {
    hint: "BOT_DETECTED",
  });
}

/**
 * The BotID check for a Server Action, which has no request to guard: it
 * resolves to the `DbError` to return (a 403 with the hint `BOT_DETECTED`, or a
 * 503 with `BOT_CHECK_FAILED` when BotID fails and `onError` is `deny`), or to
 * `undefined` for a human.
 */
export function botIdCheck(
  options: BotIdCheckOptions,
): () => Promise<DbError | undefined> {
  return () => botIdError(options, undefined);
}

/**
 * A guard that refuses bots with a `problem+json` 403 and the hint
 * `BOT_DETECTED`. It passes the request's headers to `checkBotId`, which reads
 * them only where it has no Vercel request context (local development); on
 * Vercel it reads the request itself.
 */
export function botIdGuard(options: BotIdGuardOptions): VercelGuard {
  return async (request) => {
    const error = await botIdError(options, request);

    return error === undefined
      ? undefined
      : problemResponse(error, {
          instance: instanceOf(request),
          format: options.problem,
        });
  };
}

/**
 * A guard on a Vercel Firewall rate limit rule. A limited request gets a
 * `problem+json` 429 with `Retry-After`, and one the Firewall blocked a 403
 * with the hint `FIREWALL_BLOCKED`. A rule id the Firewall doesn't know, or a
 * failed check, follows `onError`.
 */
export function firewallRateLimit(
  options: FirewallRateLimitOptions,
): VercelGuard {
  const retryAfter = Math.max(
    1,
    Math.ceil(options.retryAfter ?? DEFAULT_RETRY_AFTER),
  );

  const refuse = (request: Request, error: DbError): Response =>
    problemResponse(error, {
      instance: instanceOf(request),
      format: options.problem,
    });

  const failed = (request: Request, error: DbError): Response | undefined =>
    options.onError === "deny" ? refuse(request, error) : undefined;

  return async (request) => {
    let result: FirewallRateLimitResult;

    try {
      const key = options.key?.(request);

      result = await options.checkRateLimit(options.id, {
        request,
        ...(key === undefined ? {} : { rateLimitKey: key }),
        ...(options.timeout === undefined ? {} : { timeout: options.timeout }),
      });
    } catch {
      return failed(
        request,
        dbError("network", "The rate limit check could not run", {
          hint: "FIREWALL_UNAVAILABLE",
        }),
      );
    }

    if (result.error === "blocked") {
      return refuse(
        request,
        dbError("forbidden", "The Firewall blocked the request", {
          hint: "FIREWALL_BLOCKED",
        }),
      );
    }

    if (result.error === "not-found") {
      return failed(
        request,
        dbError(
          "network",
          `The Firewall has no rate limit rule ${options.id}`,
          { hint: "FIREWALL_RULE_NOT_FOUND" },
        ),
      );
    }

    return result.rateLimited
      ? refuse(
          request,
          dbError(
            "rate_limited",
            `Too many requests. Retry after ${retryAfter} seconds.`,
            { retryAfter },
          ),
        )
      : undefined;
  };
}

/** Runs `guards` in order; the first refusal wins and the rest don't run. */
export function combineGuards(...guards: readonly VercelGuard[]): VercelGuard {
  return async (request) => {
    for (const check of guards) {
      const refused = await check(request);

      if (refused !== undefined) {
        return refused;
      }
    }

    return;
  };
}

/**
 * Wraps a route handler so `guards` run first, in order; the first refusal is
 * answered instead of calling `handler`. Extra handler arguments, such as the
 * Next.js route context, pass through.
 */
export function withGuards<R extends Request, A extends unknown[]>(
  handler: (request: R, ...rest: A) => Response | Promise<Response>,
  ...guards: readonly VercelGuard[]
): (request: R, ...rest: A) => Promise<Response> {
  const check = combineGuards(...guards);

  return async (request, ...rest) =>
    (await check(request)) ?? handler(request, ...rest);
}
