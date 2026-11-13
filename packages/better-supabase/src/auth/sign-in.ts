import type { AuthError, Provider } from "@supabase/supabase-js";

import { isAuthRetryableFetchError } from "@supabase/supabase-js";

import type { DbError } from "../core/errors.ts";

import { dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";

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
 * Whether the user has a verified MFA factor, so the session must reach `aal2`
 * before the app treats it as signed in.
 */
export function needsMfa(user: unknown): boolean {
  if (!isRecord(user)) {
    return false;
  }

  const factors = user["factors"];

  return (
    Array.isArray(factors) &&
    factors.some(
      (factor: unknown) => isRecord(factor) && factor["status"] === "verified",
    )
  );
}

/** The email link and code types `verifyOtp` accepts. */
export type EmailOtpType =
  | "signup"
  | "invite"
  | "magiclink"
  | "recovery"
  | "email_change"
  | "email";

/** A link's `token_hash`, or the email and the code Auth sent to it. */
export type OtpParams =
  | { readonly type: EmailOtpType; readonly tokenHash: string }
  | {
      readonly type: EmailOtpType;
      readonly email: string;
      readonly token: string;
    };

/** Where `signOut` ends sessions: this one, every one, or every other one. */
export type SignOutScope = "local" | "global" | "others";

/** A sign-up for an email that already has an account. */
export interface ExistingAccount {
  readonly existingAccount: true;
}

/**
 * Auth answers a sign-up for a confirmed email with a stand-in user that has no
 * identities, and sends no email.
 */
export function isStandInUser(user: unknown): boolean {
  const identities = isRecord(user) ? user["identities"] : undefined;

  return Array.isArray(identities) && identities.length === 0;
}

export interface AuthorizeUrlParams {
  /** The OAuth provider, such as `github` or `google`. */
  readonly provider: Provider;
  /**
   * The absolute URL of the callback route that calls `exchangeCodeForSession`.
   * It must be in the project's redirect allow list.
   */
  readonly redirectTo: string;
  /** Space-separated provider scopes. */
  readonly scopes?: string;
  /** Extra query parameters for the provider, such as `prompt`. */
  readonly queryParams?: Readonly<Record<string, string>>;
}

/**
 * An auth-js error as a `DbError`. Auth's own message can tell whether an
 * account exists, so only its `code` is kept.
 */
export function authFailure(
  error: AuthError,
  what: string,
  timedOut: boolean,
): DbError {
  const code = error.code === undefined ? {} : { code: error.code };

  if (timedOut) {
    return dbError("timeout", `${what} timed out`);
  }

  if (error.name === "AuthInvalidTokenResponseError") {
    return dbError("unauthorized", `${what} returned no session`, {
      code: "no_session",
    });
  }

  if (error.status === 429) {
    return dbError("rate_limited", `${what} was rate limited`, code);
  }

  if (error.status !== undefined && error.status >= 500) {
    return dbError("network", `${what} failed with ${String(error.status)}`);
  }

  // Status 0: the fetch threw, so the message is the runtime's, not Auth's.
  if (isAuthRetryableFetchError(error)) {
    return dbError("network", error.message || `${what} failed`);
  }

  return dbError("unauthorized", `${what} failed`, code);
}
