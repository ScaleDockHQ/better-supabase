import type { RateLimit } from "../rate-limit/rate-limit.ts";

import { dbError } from "../core/errors.ts";

/** Who asks for a realtime token. */
export interface RealtimeCaller {
  /** What the limit counts by: a user or a tenant. */
  readonly key: string;
  readonly organizationId?: string;
  readonly userId?: string;
}

/** One minted token, for the audit row. */
export interface RealtimeTokenEntry {
  readonly caller: RealtimeCaller;
  readonly model?: string;
  readonly at: Date;
}

export interface RealtimeTokenRouteOptions {
  /** Resolves the caller from the request, or `undefined` for a 401. */
  readonly identify: (
    request: Request,
  ) => Promise<RealtimeCaller | undefined> | RealtimeCaller | undefined;
  /**
   * Mints the short-lived token, such as
   * `gateway.experimental_realtime.getToken({ model })`. The body is the parsed
   * JSON of the request, or `{}`.
   */
  readonly mint: (
    body: Record<string, unknown>,
    caller: RealtimeCaller,
  ) => Promise<Record<string, unknown>>;
  /** The rate-limit client; needs a service role. */
  readonly rateLimit: Pick<RateLimit, "check">;
  /** The scope the token requests count against. Defaults to `ai.realtime`. */
  readonly scope?: string;
  /**
   * Writes one row per token, such as an `ai_usage` entry or an audit row. An
   * error here never changes the response.
   */
  readonly record?: (entry: RealtimeTokenEntry) => Promise<void> | void;
}

const json = (status: number, body: unknown, headers?: HeadersInit): Response =>
  Response.json(body, {
    status,
    ...(headers === undefined ? {} : { headers }),
  });

/**
 * A Fetch handler for the realtime setup endpoint. It identifies the caller,
 * counts the request against a rate limit, mints the token and records it, so
 * the app's provider key never mints sessions for anonymous or runaway
 * callers.
 */
export function realtimeTokenRoute(
  options: RealtimeTokenRouteOptions,
): (request: Request) => Promise<Response> {
  const scope = options.scope ?? "ai.realtime";

  return async (request) => {
    const caller = await options.identify(request);

    if (caller === undefined) {
      return json(401, { error: "unauthorized" });
    }

    const decision = await options.rateLimit.check({
      scope,
      key: caller.key,
      organizationId: caller.organizationId,
    });

    if (!decision.ok) {
      return json(503, {
        error: dbError("network", "Rate limit check failed."),
      });
    }

    if (!decision.data.allowed) {
      const retryAfter = Math.max(1, Math.ceil(decision.data.retryAfter));

      return json(
        429,
        { error: "rate_limited", retryAfter },
        { "retry-after": String(retryAfter) },
      );
    }

    const parsed: unknown = await request.json().catch(() => ({}));

    // SAFETY: a JSON body that isn't an object is treated as empty.
    const body =
      typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
        ? (parsed as Record<string, unknown>)
        : {};

    const token = await options.mint(body, caller);

    try {
      await options.record?.({
        caller,
        ...(typeof body["model"] === "string" ? { model: body["model"] } : {}),
        at: new Date(),
      });
    } catch {
      // The audit row never changes what the caller gets.
    }

    return json(200, token);
  };
}
