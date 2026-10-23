import type { Result } from "../core/result.ts";
import type { RefreshOptions } from "./refresh.ts";
import type { StoredSession } from "./session.ts";

import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";

const DEFAULT_TIMEOUT_MS = 5000;

/** Matches a same-origin path. Browsers read `/\host` like `//host`. */
const SAME_ORIGIN_PATH = /^\/(?![/\\])/;

/** Control characters and spaces, which some browsers strip before parsing. */
function hasUnsafe(path: string): boolean {
  for (const char of path) {
    const code = char.codePointAt(0) ?? 0;

    if (code <= 0x20 || code === 0x7f) {
      return true;
    }
  }

  return false;
}

/**
 * `next` when it is a same-origin path (`/dashboard?tab=1`), else `fallback`.
 * Use it on any `?next=` or `redirectTo` value a request carries, so the value
 * can't send the user to another origin.
 */
export function safeRedirectPath(
  next: string | null | undefined,
  fallback: string,
): string {
  return next && SAME_ORIGIN_PATH.test(next) && !hasUnsafe(next)
    ? next
    : fallback;
}

/**
 * Whether the session's user has a verified MFA factor, so the session must
 * reach `aal2` before the app treats it as signed in.
 */
export function needsMfa(session: StoredSession): boolean {
  const user = session.user;

  if (typeof user !== "object" || user === null || !("factors" in user)) {
    return false;
  }

  const factors: unknown = user.factors;

  return (
    Array.isArray(factors) &&
    factors.some(
      (factor: unknown) =>
        typeof factor === "object" &&
        factor !== null &&
        "status" in factor &&
        factor.status === "verified",
    )
  );
}

export type PasswordGrantOptions = Omit<RefreshOptions, "now"> & {
  readonly now?: () => number;
};

/**
 * Signs in with an email and a password against the Auth server's password
 * grant, without a supabase-js client. Returns the session to write as
 * cookies.
 */
export async function passwordGrant(
  credentials: { readonly email: string; readonly password: string },
  options: PasswordGrantOptions,
): Promise<Result<StoredSession>> {
  const doFetch = options.fetch ?? fetch;
  const signal = AbortSignal.timeout(options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
  let response: Response;

  try {
    response = await doFetch(
      `${options.url}/auth/v1/token?grant_type=password`,
      {
        method: "POST",
        headers: {
          apikey: options.forwardedFor?.secretKey ?? options.publishableKey,
          "content-type": "application/json",
          ...(options.forwardedFor
            ? { "sb-forwarded-for": options.forwardedFor.ip }
            : {}),
        },
        body: JSON.stringify({
          email: credentials.email,
          password: credentials.password,
        }),
        signal,
      },
    );
  } catch (cause) {
    return err(
      signal.aborted
        ? dbError("timeout", "sign-in timed out")
        : dbError(
            "network",
            cause instanceof Error ? cause.message : "fetch failed",
          ),
    );
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
          : `Sign-in failed with ${String(response.status)}`;

    const code =
      typeof body?.["error_code"] === "string" ? body["error_code"] : undefined;

    if (response.status === 429) {
      return err(dbError("rate_limited", message));
    }

    if (response.status >= 500) {
      return err(dbError("network", message));
    }

    return err(
      dbError("unauthorized", message, code === undefined ? {} : { code }),
    );
  }

  const expiresIn =
    typeof body["expires_in"] === "number" ? body["expires_in"] : undefined;

  const now = options.now ?? Date.now;

  return ok({
    ...body,
    access_token: body["access_token"],
    refresh_token: body["refresh_token"],
    ...(typeof body["expires_at"] !== "number" && expiresIn !== undefined
      ? { expires_at: Math.floor(now() / 1000) + expiresIn }
      : {}),
  });
}
