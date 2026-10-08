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
  /**
   * Milliseconds before a refresh counts as a network failure (the session is
   * kept). 5000 by default.
   */
  readonly timeoutMs?: number;
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

const DEFAULT_TIMEOUT_MS = 5000;
/** Finished refreshes kept for reuse; a burst of sign-ins can't grow it past this. */
const RECENT_MAX = 1000;

const inflight = new Map<string, Promise<RefreshOutcome>>();
const recent = new Map<
  string,
  { readonly outcome: RefreshOutcome; readonly until: number }
>();

function shared(outcome: RefreshOutcome): RefreshOutcome {
  return outcome.ok ? { ...outcome, shared: true } : outcome;
}

function prune(now: number): void {
  // Entries are inserted in expiry order, so the first fresh one ends the scan.
  for (const [token, entry] of recent) {
    if (entry.until > now) return;
    recent.delete(token);
  }
}

async function request(
  refreshToken: string,
  options: RefreshOptions,
  now: number,
): Promise<RefreshOutcome> {
  const doFetch = options.fetch ?? fetch;
  const signal = AbortSignal.timeout(options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
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
        signal,
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
  if (signal.aborted) {
    return { ok: false, reason: "network", message: "refresh timed out" };
  }
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
  const clock = options.now ?? Date.now;
  const now = clock();
  prune(now);
  // Two projects can't share a refresh token, but one process can serve both.
  const key = `${options.url}\n${refreshToken}`;
  const cached = recent.get(key);
  if (cached) return Promise.resolve(shared(cached.outcome));
  const pending = inflight.get(key);
  if (pending) return pending.then(shared);

  // A rejection is reused too, so parallel requests with a dead token don't
  // each ask Auth again.
  const promise = request(refreshToken, options, now)
    .then((outcome) => {
      if (outcome.ok || outcome.reason === "rejected") {
        recent.delete(key);
        // From completion: a slow refresh still gets the whole window.
        recent.set(key, { outcome, until: clock() + REUSE_MS });
        if (recent.size > RECENT_MAX) {
          const oldest = recent.keys().next();
          if (!oldest.done) recent.delete(oldest.value);
        }
      }
      return outcome;
    })
    .finally(() => {
      inflight.delete(key);
    });
  inflight.set(key, promise);
  return promise;
}
