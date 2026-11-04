/** What an Auth error means for the caller. */
export type AuthErrorKind =
  | "retryable"
  | "session-missing"
  | "invalid-credentials"
  | "rate-limited"
  | "banned"
  | "unknown";

const BY_CODE: Readonly<Record<string, AuthErrorKind>> = {
  session_not_found: "session-missing",
  refresh_token_not_found: "session-missing",
  refresh_token_already_used: "session-missing",
  session_expired: "session-missing",
  invalid_credentials: "invalid-credentials",
  user_not_found: "invalid-credentials",
  email_not_confirmed: "invalid-credentials",
  over_request_rate_limit: "rate-limited",
  over_email_send_rate_limit: "rate-limited",
  over_sms_send_rate_limit: "rate-limited",
  user_banned: "banned",
  unexpected_failure: "retryable",
  request_timeout: "retryable",
};

/** Message fallbacks for responses that carry no `code`, in one table. */
const BY_MESSAGE: readonly (readonly [RegExp, AuthErrorKind])[] = [
  [
    /auth session missing|refresh token (not found|already used)/i,
    "session-missing",
  ],
  [/invalid login credentials/i, "invalid-credentials"],
  [/rate limit|too many requests/i, "rate-limited"],
  [/user is banned/i, "banned"],
];

/**
 * Classifies an auth-js error. `code` and `status` decide first; the message is
 * the fallback for older Auth servers.
 */
export function authErrorKind(error: unknown): AuthErrorKind {
  if (typeof error !== "object" || error === null) {
    return "unknown";
  }

  // SAFETY: every field is read as unknown and type-checked below.
  const { code, status, name, message } = error as Record<string, unknown>;

  if (typeof code === "string" && code in BY_CODE) {
    return BY_CODE[code] ?? "unknown";
  }

  if (status === 429) {
    return "rate-limited";
  }

  if (
    name === "AuthRetryableFetchError" ||
    (typeof status === "number" && status >= 500)
  ) {
    return "retryable";
  }

  if (name === "AuthSessionMissingError") {
    return "session-missing";
  }

  if (typeof message === "string") {
    for (const [pattern, kind] of BY_MESSAGE) {
      if (pattern.test(message)) {
        return kind;
      }
    }
  }

  return "unknown";
}
