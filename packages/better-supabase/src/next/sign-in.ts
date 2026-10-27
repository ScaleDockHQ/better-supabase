import type {
  AuthResolution,
  AuthState,
  ResolveAuthOptions,
} from "../auth/resolve.ts";
import type { CookieScope, StoredSession } from "../auth/session.ts";
import type { EmailFlowPath, PasswordGrantOptions } from "../auth/sign-in.ts";
import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { Result } from "../core/result.ts";
import type { ActionResult } from "../server/kit.ts";
import type {
  ExchangeCodeParams,
  EmailRedirect,
  MfaVerification,
  SignInWithOAuthParams,
  ResendParams,
  ResetPasswordParams,
  SignInCredentials,
  SignInOptions,
  SignInWithOtpParams,
  SignOutParams,
  SignUpParams,
  SignedIn,
  VerifyOtpParams,
} from "./types.ts";

import { clientIp } from "../auth/resolve.ts";
import {
  applyCookieWrites,
  clearSessionAtScopes,
  sessionCookieName,
  writeSession,
} from "../auth/session.ts";
import {
  authorizeUrlFor,
  emailFlow,
  mfaGrant,
  needsMfa,
  otpGrant,
  passwordGrant,
  pkceGrant,
  pkcePair,
  revokeSession,
  safeRedirectPath,
} from "../auth/sign-in.ts";
import { authOfSnapshot, snapshotOf } from "../auth/snapshot.ts";
import { dbError } from "../core/errors.ts";
import { ok } from "../core/result.ts";

interface CookieJar {
  getAll(): readonly { readonly name: string; readonly value: string }[];
  set(name: string, value: string, options: object): unknown;
}

/** How long the PKCE verifier cookie lives, in seconds. */
const VERIFIER_MAX_AGE = 600;

export interface AuthFlowDeps<C, P> {
  /** Read on each call: the env may load after `createNext`. */
  readonly env: () => {
    readonly url: string;
    readonly publishableKey: string;
    readonly secretKey?: string | undefined;
  };
  readonly auth: Omit<ResolveAuthOptions, "env"> | undefined;
  readonly cookieScopes: readonly CookieScope[] | undefined;
  /** The incoming request: its headers, cookies and the caller's IP. */
  readonly request: () => Promise<Request>;
  readonly jar: () => Promise<CookieJar>;
  /** The request's current session, after any earlier commit. */
  readonly current: () => Promise<SessionSnapshot<C> | null>;
  /** Verifies a token like a request carrying it would be. */
  readonly verify: (token: string | null) => Promise<AuthResolution<C, P>>;
  /**
   * Makes the committed session what later reads in the request see, and stores
   * it for the next render.
   */
  readonly publish: (
    resolution: AuthResolution<C, P>,
    request: Request,
  ) => Promise<void>;
  /** Forgets a signed-out user's verified sessions and cache tags. */
  readonly signedOut: (userId: string) => void;
}

export interface AuthFlows {
  signInWithPassword(
    credentials: SignInCredentials,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  verifyOtp(
    params: VerifyOtpParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  signInWithOAuth(
    params: SignInWithOAuthParams,
  ): Promise<{ readonly url: string }>;
  exchangeCodeForSession(
    params: ExchangeCodeParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  verifyMfa(
    params: MfaVerification,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  signOut(
    params?: SignOutParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  signInWithOtp(params: SignInWithOtpParams): Promise<ActionResult<null>>;
  resetPasswordForEmail(
    params: ResetPasswordParams,
  ): Promise<ActionResult<null>>;
  signUp(
    params: SignUpParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn | null>>;
  resend(params: ResendParams): Promise<ActionResult<null>>;
}

function refused(auth: AuthState): ActionResult<never> {
  return {
    ok: false,
    data: null,
    error:
      auth.kind === "invalid"
        ? auth.error
        : dbError("unauthorized", "The new session did not verify"),
  };
}

/**
 * The server-side sign-in and sign-out flows. Each runs one Auth call, then one
 * commit: it verifies the new token, writes or clears the session cookies
 * through the request's cookie jar, and publishes the session to later reads in
 * the same request. The result carries no token: it crosses the action
 * boundary, and the session is on the request's reads.
 */
export function authFlows<C, P>(deps: AuthFlowDeps<C, P>): AuthFlows {
  const { auth } = deps;

  const cookieName = (): string =>
    auth?.cookie?.name ?? sessionCookieName(deps.env().url);

  const verifierName = (): string => `${cookieName()}-code-verifier`;

  const setVerifier = async (value: string, maxAge: number): Promise<void> => {
    (await deps.jar()).set(verifierName(), value, {
      path: "/",
      ...auth?.cookie?.options,
      httpOnly: true,
      sameSite: "lax",
      maxAge,
    });
  };

  /** Writes a new PKCE verifier cookie and returns its challenge. */
  const startPkce = async (): Promise<string> => {
    const { verifier, challenge } = await pkcePair();
    await setVerifier(verifier, VERIFIER_MAX_AGE);

    return challenge;
  };

  /** `redirectTo` with a same-origin `next` as `?next=`. */
  const callbackUrl = (params: EmailRedirect): string => {
    const next = safeRedirectPath(params.next, "");
    const target = new URL(params.redirectTo);

    if (next) {
      target.searchParams.set("next", next);
    }

    return target.href;
  };

  /** Starts an email flow; drops the verifier when Auth refuses it. */
  const sendEmail = async (
    path: EmailFlowPath,
    params: EmailRedirect,
    body: Record<string, unknown>,
  ): Promise<Result<StoredSession | null>> => {
    const challenge = await startPkce();

    const sent = await emailFlow(
      path,
      { body, redirectTo: callbackUrl(params), challenge },
      await grantOptions(),
    );

    if (!sent.ok) {
      await setVerifier("", 0);
    }

    return sent;
  };

  const requested = (sent: Result<unknown>): ActionResult<null> =>
    sent.ok ? { ok: true, data: null, error: null } : sent;

  const grantOptions = async (): Promise<PasswordGrantOptions> => {
    const env = deps.env();
    const secretKey = env.secretKey;

    const ip =
      secretKey && auth?.clientIp !== false
        ? (auth?.clientIp ?? clientIp)(await deps.request())
        : undefined;

    return {
      url: env.url,
      publishableKey: env.publishableKey,
      ...(secretKey && ip ? { forwardedFor: { ip, secretKey } } : {}),
      ...(auth?.fetch ? { fetch: auth.fetch } : {}),
      ...(auth?.refreshTimeoutMs === undefined
        ? {}
        : { timeoutMs: auth.refreshTimeoutMs }),
    };
  };

  /** Verifies, writes the cookies and publishes `stored` (`null` clears). */
  const commit = async (
    granted: Result<StoredSession | null>,
    next: string | null | undefined,
    options: SignInOptions,
  ): Promise<ActionResult<SignedIn>> => {
    if (!granted.ok) {
      return granted;
    }

    const stored = granted.data;
    const resolution = await deps.verify(stored?.access_token ?? null);

    if (stored && resolution.auth.kind !== "user") {
      return refused(resolution.auth);
    }

    const jar = await deps.jar();
    const existing = jar.getAll();

    const writes = [
      ...writeSession(
        existing,
        cookieName(),
        stored,
        auth?.cookie?.options,
        auth?.cookie?.encode === undefined
          ? {}
          : { encode: auth.cookie.encode },
      ),
      ...(stored
        ? []
        : clearSessionAtScopes(
            existing,
            cookieName(),
            deps.cookieScopes ?? [],
          )),
    ];

    for (const write of writes) {
      jar.set(write.name, write.value, write.options);
    }

    const headers = new Headers((await deps.request()).headers);

    headers.set(
      "cookie",
      applyCookieWrites(existing, writes)
        .map((cookie) => `${cookie.name}=${encodeURIComponent(cookie.value)}`)
        .join("; "),
    );

    await deps.publish(
      resolution,
      new Request("http://next.local/", { headers }),
    );

    return {
      ok: true,
      data: {
        redirectTo: safeRedirectPath(next, options.fallback ?? "/"),
        mfa:
          stored !== null &&
          needsMfa(stored) &&
          snapshotOf(resolution.auth)?.claims["aal"] !== "aal2",
        user: resolution.auth.kind === "user" ? resolution.auth.user : null,
      },
      error: null,
    };
  };

  const signInWithPassword: AuthFlows["signInWithPassword"] = async (
    credentials,
    options = {},
  ) =>
    commit(
      await passwordGrant(
        { email: credentials.email, password: credentials.password },
        await grantOptions(),
      ),
      credentials.next,
      options,
    );

  return {
    signInWithPassword,

    verifyOtp: async (params, options = {}) =>
      commit(
        await otpGrant(params, await grantOptions()),
        params.next,
        options,
      ),

    async signInWithOAuth(params) {
      const challenge = await startPkce();

      return {
        url: authorizeUrlFor(
          deps.env().url,
          { ...params, redirectTo: callbackUrl(params) },
          challenge,
        ),
      };
    },

    async signInWithOtp(params) {
      return requested(
        await sendEmail("otp", params, {
          email: params.email,
          create_user: params.shouldCreateUser ?? true,
          data: params.data ?? {},
        }),
      );
    },

    async resetPasswordForEmail(params) {
      return requested(
        await sendEmail("recover", params, { email: params.email }),
      );
    },

    async signUp(params, options = {}) {
      const sent = await sendEmail("signup", params, {
        email: params.email,
        password: params.password,
        data: params.data ?? {},
      });

      if (!sent.ok || sent.data === null) {
        return requested(sent);
      }

      await setVerifier("", 0);

      return commit(sent, params.next, options);
    },

    async resend(params) {
      return requested(
        await sendEmail("resend", params, {
          email: params.email,
          type: params.type,
        }),
      );
    },

    async exchangeCodeForSession(params, options = {}) {
      const verifier = (await deps.jar())
        .getAll()
        .find((cookie) => cookie.name === verifierName())?.value;

      await setVerifier("", 0);

      if (!verifier) {
        return {
          ok: false,
          data: null,
          error: dbError("unauthorized", "Code exchange failed", {
            code: "code_verifier_missing",
          }),
        };
      }

      return commit(
        await pkceGrant({ code: params.code, verifier }, await grantOptions()),
        params.next,
        options,
      );
    },

    async verifyMfa(params, options = {}) {
      const current = await deps.current();

      if (!current) {
        return {
          ok: false,
          data: null,
          error: dbError("unauthorized", "MFA verification needs a session"),
        };
      }

      return commit(
        await mfaGrant(
          {
            accessToken: current.accessToken,
            factorId: params.factorId,
            code: params.code,
          },
          await grantOptions(),
        ),
        params.next,
        options,
      );
    },

    async signOut(params = {}, options = {}) {
      const scope = params.scope ?? "local";
      const current = await deps.current();

      if (current) {
        const revoked = await revokeSession(
          current.accessToken,
          scope,
          await grantOptions(),
        );

        if (!revoked.ok) {
          return revoked;
        }
      }

      // The other sessions' tokens stay valid until they expire, so the memo
      // and the cache tags built on them go for every scope.
      if (current) {
        deps.signedOut(current.userId);
      }

      if (scope === "others") {
        const kept = current ? authOfSnapshot(current) : undefined;

        return {
          ok: true,
          data: {
            redirectTo: safeRedirectPath(params.next, options.fallback ?? "/"),
            mfa: false,
            user: kept?.kind === "user" ? kept.user : null,
          },
          error: null,
        };
      }

      return commit(ok(null), params.next, options);
    },
  };
}
