import type { DbError } from "../core/errors.ts";
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

/** The email link and code types `/auth/v1/verify` accepts. */
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

/** Where `logout` ends sessions: this one, every one, or every other one. */
export type SignOutScope = "local" | "global" | "others";

type Body = Record<string, unknown>;

function failure(status: number, body: Body | null, what: string): DbError {
  const code =
    typeof body?.["error_code"] === "string" ? body["error_code"] : undefined;

  if (status === 429) {
    return dbError(
      "rate_limited",
      `${what} was rate limited`,
      code === undefined ? {} : { code },
    );
  }

  if (status >= 500) {
    return dbError("network", `${what} failed with ${String(status)}`);
  }

  // Auth's own message can tell whether an account exists, so it stays out.
  return dbError(
    "unauthorized",
    `${what} failed`,
    code === undefined ? {} : { code },
  );
}

/**
 * One POST to the Auth server, with the secret key and the user's IP when
 * `forwardedFor` is set. Returns the JSON body, `{}` when there is none.
 */
async function authPost(
  path: string,
  body: Body | undefined,
  options: PasswordGrantOptions & { readonly token?: string },
  what: string,
): Promise<Result<Body>> {
  const doFetch = options.fetch ?? fetch;
  const signal = AbortSignal.timeout(options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
  let response: Response;

  try {
    response = await doFetch(`${options.url}/auth/v1/${path}`, {
      method: "POST",
      headers: {
        apikey: options.forwardedFor?.secretKey ?? options.publishableKey,
        "content-type": "application/json",
        ...(options.forwardedFor
          ? { "sb-forwarded-for": options.forwardedFor.ip }
          : {}),
        ...(options.token ? { authorization: `Bearer ${options.token}` } : {}),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal,
    });
  } catch (cause) {
    return err(
      signal.aborted
        ? dbError("timeout", `${what} timed out`)
        : dbError(
            "network",
            cause instanceof Error ? cause.message : "fetch failed",
          ),
    );
  }

  const parsed: unknown = await response.json().catch(() => null);

  let json: Body | null = null;

  if (typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)) {
    // SAFETY: a non-array object; every field is checked before use.
    json = parsed as Body;
  }

  return response.ok
    ? ok(json ?? {})
    : err(failure(response.status, json, what));
}

/** The session in a token response, with `expires_at` filled in. */
function sessionFrom(
  body: Result<Body>,
  options: PasswordGrantOptions,
  what: string,
): Result<StoredSession> {
  if (!body.ok) {
    return body;
  }

  const data = body.data;
  const accessToken = data["access_token"];
  const refreshToken = data["refresh_token"];

  if (typeof accessToken !== "string" || typeof refreshToken !== "string") {
    return err(
      dbError("unauthorized", `${what} returned no session`, {
        code: "no_session",
      }),
    );
  }

  const expiresIn =
    typeof data["expires_in"] === "number" ? data["expires_in"] : undefined;

  const now = options.now ?? Date.now;

  return ok({
    ...data,
    access_token: accessToken,
    refresh_token: refreshToken,
    ...(typeof data["expires_at"] !== "number" && expiresIn !== undefined
      ? { expires_at: Math.floor(now() / 1000) + expiresIn }
      : {}),
  });
}

/**
 * Signs in with an email and a password against the Auth server's password
 * grant, without a supabase-js client. Returns the session to write as
 * cookies.
 */
export async function passwordGrant(
  credentials: { readonly email: string; readonly password: string },
  options: PasswordGrantOptions,
): Promise<Result<StoredSession>> {
  return sessionFrom(
    await authPost(
      "token?grant_type=password",
      { email: credentials.email, password: credentials.password },
      options,
      "Sign-in",
    ),
    options,
    "Sign-in",
  );
}

/**
 * Verifies an email link's `token_hash`, or an emailed code, against
 * `/auth/v1/verify` and returns the session it starts.
 */
export async function otpGrant(
  params: OtpParams,
  options: PasswordGrantOptions,
): Promise<Result<StoredSession>> {
  return sessionFrom(
    await authPost(
      "verify",
      "tokenHash" in params
        ? { type: params.type, token_hash: params.tokenHash }
        : { type: params.type, email: params.email, token: params.token },
      options,
      "Verification",
    ),
    options,
    "Verification",
  );
}

/** Exchanges an OAuth or email `code` and its PKCE verifier for a session. */
export async function pkceGrant(
  params: { readonly code: string; readonly verifier: string },
  options: PasswordGrantOptions,
): Promise<Result<StoredSession>> {
  return sessionFrom(
    await authPost(
      "token?grant_type=pkce",
      { auth_code: params.code, code_verifier: params.verifier },
      options,
      "Code exchange",
    ),
    options,
    "Code exchange",
  );
}

/** The Auth endpoints that email the user a link to `redirect_to`. */
export type EmailFlowPath = "otp" | "recover" | "signup" | "resend";

/**
 * Starts an email flow (magic link or code, password reset, sign-up, resend)
 * with a PKCE `challenge`, so the link lands on `redirectTo` with a `?code=`
 * that `pkceGrant` exchanges. Returns the session a sign-up starts when email
 * confirmation is off, else `null`.
 */
export async function emailFlow(
  path: EmailFlowPath,
  params: {
    readonly body: Body;
    readonly redirectTo: string;
    readonly challenge: string;
  },
  options: PasswordGrantOptions,
): Promise<Result<StoredSession | null>> {
  const what = path === "signup" ? "Sign-up" : "Email request";

  const sent = await authPost(
    `${path}?redirect_to=${encodeURIComponent(params.redirectTo)}`,
    {
      ...params.body,
      code_challenge: params.challenge,
      code_challenge_method: "s256",
    },
    options,
    what,
  );

  return sent.ok && typeof sent.data["access_token"] !== "string"
    ? ok(null)
    : sessionFrom(sent, options, what);
}

/**
 * Challenges an MFA factor and verifies the code against it, as the user the
 * access token belongs to. Returns the `aal2` session.
 */
export async function mfaGrant(
  params: {
    readonly accessToken: string;
    readonly factorId: string;
    readonly code: string;
  },
  options: PasswordGrantOptions,
): Promise<Result<StoredSession>> {
  const factor = `factors/${encodeURIComponent(params.factorId)}`;
  const withToken = { ...options, token: params.accessToken };

  const challenge = await authPost(
    `${factor}/challenge`,
    {},
    withToken,
    "MFA challenge",
  );

  if (!challenge.ok) {
    return challenge;
  }

  const challengeId = challenge.data["id"];

  if (typeof challengeId !== "string") {
    return err(dbError("unauthorized", "MFA challenge failed"));
  }

  return sessionFrom(
    await authPost(
      `${factor}/verify`,
      { challenge_id: challengeId, code: params.code },
      withToken,
      "MFA verification",
    ),
    options,
    "MFA verification",
  );
}

/**
 * Ends the access token's session (`local`), every session of its user
 * (`global`) or every other one (`others`) on the Auth server. A session that
 * is already gone counts as ended.
 */
export async function revokeSession(
  accessToken: string,
  scope: SignOutScope,
  options: PasswordGrantOptions,
): Promise<Result<null>> {
  const revoked = await authPost(
    `logout?scope=${scope}`,
    undefined,
    { ...options, token: accessToken },
    "Sign-out",
  );

  return revoked.ok || revoked.error.kind === "unauthorized"
    ? ok(null)
    : revoked;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCodePoint(byte);
  }

  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/, "");
}

/** A PKCE verifier and its S256 challenge (RFC 7636). */
export async function pkcePair(): Promise<{
  readonly verifier: string;
  readonly challenge: string;
}> {
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));

  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier),
  );

  return { verifier, challenge: base64url(new Uint8Array(digest)) };
}

export interface AuthorizeUrlParams {
  /** The OAuth provider, such as `github` or `google`. */
  readonly provider: string;
  /**
   * The absolute URL of the callback route that calls `exchangeCode`. It must
   * be in the project's redirect allow list.
   */
  readonly redirectTo: string;
  /** Space-separated provider scopes. */
  readonly scopes?: string;
  /** Extra query parameters for the provider, such as `prompt`. */
  readonly queryParams?: Readonly<Record<string, string>>;
}

/** The Auth server's `/authorize` URL for a PKCE sign-in with `challenge`. */
export function authorizeUrlFor(
  url: string,
  params: AuthorizeUrlParams,
  challenge: string,
): string {
  const target = new URL(`${url}/auth/v1/authorize`);

  for (const [key, value] of Object.entries(params.queryParams ?? {})) {
    target.searchParams.set(key, value);
  }

  target.searchParams.set("provider", params.provider);
  target.searchParams.set("redirect_to", params.redirectTo);
  target.searchParams.set("code_challenge", challenge);
  target.searchParams.set("code_challenge_method", "s256");

  if (params.scopes) {
    target.searchParams.set("scopes", params.scopes);
  }

  return target.href;
}
