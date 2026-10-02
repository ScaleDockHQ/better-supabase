import type { StoredSession } from "./session.ts";

export interface RefreshOptions {
  readonly url: string;
  readonly publishableKey: string;
  /**
   * Sends `Sb-Forwarded-For: ip` with the secret key, so Auth rate-limits the
   * refresh by the user's IP (when IP forwarding is on for the project).
   */
  readonly forwardedFor?: { readonly ip: string; readonly secretKey: string };
  readonly fetch?: typeof fetch;
  /** Epoch milliseconds, the unit JWT `exp` and `iat` math needs. */
  readonly now?: () => number;
}

export type RefreshOutcome =
  | {
      readonly ok: true;
      readonly session: StoredSession;
      /** Served from a concurrent or just-finished refresh of the same token. */
      readonly shared?: boolean;
    }
  | {
      readonly ok: false;
      /** `rejected`: the refresh token is dead, sign the user out. `network`: keep the session and retry later. */
      readonly reason: "rejected" | "network";
      readonly status?: number;
      readonly message: string;
    };

/**
 * How long a finished refresh is reused for requests still carrying the old
 * refresh token (parallel page loads, prefetches). Matches the default
 * refresh-token reuse interval of Supabase Auth.
 */
const REUSE_MS = 10_000;

const inflight = new Map<string, Promise<RefreshOutcome>>();
const recent = new Map<
  string,
  { readonly outcome: RefreshOutcome; readonly until: number }
>();

function shared(outcome: RefreshOutcome): RefreshOutcome {
  return outcome.ok ? { ...outcome, shared: true } : outcome;
}

function prune(now: number): void {
  for (const [token, entry] of recent) {
    if (entry.until <= now) recent.delete(token);
  }
}

async function request(
  refreshToken: string,
  options: RefreshOptions,
  now: number,
): Promise<RefreshOutcome> {
  const doFetch = options.fetch ?? fetch;
  let response: Response;
  try {
    response = await doFetch(
      `${options.url}/auth/v1/token?grant_type=refresh_token`,
      {
        method: "POST",
        headers: {
          apikey: options.forwardedFor?.secretKey ?? options.publishableKey,
          "content-type": "application/json",
          ...(options.forwardedFor
            ? { "sb-forwarded-for": options.forwardedFor.ip }
            : {}),
        },
        body: JSON.stringify({ refresh_token: refreshToken }),
      },
    );
  } catch (cause) {
    return {
      ok: false,
      reason: "network",
      message: cause instanceof Error ? cause.message : "fetch failed",
    };
  }
  // SAFETY: the Auth server responds with a JSON object, and every field is
  // checked before use.
  const body = (await response.json().catch(() => null)) as Record<
    string,
    unknown
  > | null;
  if (
    !response.ok ||
    !body ||
    typeof body["access_token"] !== "string" ||
    typeof body["refresh_token"] !== "string"
  ) {
    const message =
      typeof body?.["msg"] === "string"
        ? body["msg"]
        : typeof body?.["error_description"] === "string"
          ? body["error_description"]
          : `Refresh failed with ${String(response.status)}`;
    return {
      ok: false,
      reason:
        response.status >= 500 || response.status === 429
          ? "network"
          : "rejected",
      status: response.status,
      message,
    };
  }
  const expiresIn =
    typeof body["expires_in"] === "number" ? body["expires_in"] : undefined;
  const session: StoredSession = {
    ...body,
    access_token: body["access_token"],
    refresh_token: body["refresh_token"],
    ...(typeof body["expires_at"] !== "number" && expiresIn !== undefined
      ? { expires_at: Math.floor(now / 1000) + expiresIn }
      : {}),
  };
  return { ok: true, session };
}

/**
 * Exchanges a refresh token for a new session. Concurrent calls with the same
 * token share one request, and a successful result is reused for a short
 * window so parallel requests carrying the old cookie converge on one session.
 */
export function refreshSession(
  refreshToken: string,
  options: RefreshOptions,
): Promise<RefreshOutcome> {
  const now = (options.now ?? Date.now)();
  prune(now);
  const cached = recent.get(refreshToken);
  if (cached) return Promise.resolve(shared(cached.outcome));
  const pending = inflight.get(refreshToken);
  if (pending) return pending.then(shared);

  const promise = request(refreshToken, options, now).then((outcome) => {
    inflight.delete(refreshToken);
    if (outcome.ok)
      recent.set(refreshToken, { outcome, until: now + REUSE_MS });
    return outcome;
  });
  inflight.set(refreshToken, promise);
  return promise;
}
