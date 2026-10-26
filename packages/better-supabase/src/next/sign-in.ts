import type {
  AuthResolution,
  AuthState,
  ResolveAuthOptions,
} from "../auth/resolve.ts";
import type { CookieScope, StoredSession } from "../auth/session.ts";
import type { PasswordGrantOptions } from "../auth/sign-in.ts";
import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { Result } from "../core/result.ts";
import type { ActionResult } from "../server/kit.ts";
import type {
  CodeExchange,
  MfaVerification,
  OAuthStart,
  SignInCredentials,
  SignInOptions,
  SignOutParams,
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
  mfaGrant,
  needsMfa,
  otpGrant,
  passwordGrant,
  pkceGrant,
  pkcePair,
  revokeSession,
  safeRedirectPath,
} from "../auth/sign-in.ts";
import { snapshotOf } from "../auth/snapshot.ts";
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

export interface AuthFlows<C> {
  signIn(
    credentials: SignInCredentials,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
  verifyOtp(
    params: VerifyOtpParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
  authorizeUrl(params: OAuthStart): Promise<{ readonly url: string }>;
  exchangeCode(
    params: CodeExchange,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
  verifyMfa(
    params: MfaVerification,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
  signOut(
    params?: SignOutParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn<C>>>;
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
 * the same request.
 */
export function authFlows<C, P>(deps: AuthFlowDeps<C, P>): AuthFlows<C> {
  const { auth } = deps;

  const cookieName = (): string =>
    auth?.cookie?.name ?? sessionCookieName(deps.env().url);

  const verifierName = (): string => `${cookieName()}-code-verifier`;

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
  ): Promise<ActionResult<SignedIn<C>>> => {
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

    const session = snapshotOf(resolution.auth);

    return {
      ok: true,
      data: {
        redirectTo: safeRedirectPath(next, options.fallback ?? "/"),
        mfa:
          stored !== null &&
          needsMfa(stored) &&
          session?.claims["aal"] !== "aal2",
        session,
      },
      error: null,
    };
  };

  const signIn: AuthFlows<C>["signIn"] = async (credentials, options = {}) =>
    commit(
      await passwordGrant(
        { email: credentials.email, password: credentials.password },
        await grantOptions(),
      ),
      credentials.next,
      options,
    );

  return {
    signIn,

    verifyOtp: async (params, options = {}) =>
      commit(
        await otpGrant(params, await grantOptions()),
        params.next,
        options,
      ),

    async authorizeUrl(params) {
      const { verifier, challenge } = await pkcePair();
      const jar = await deps.jar();

      jar.set(verifierName(), verifier, {
        path: "/",
        ...auth?.cookie?.options,
        httpOnly: true,
        sameSite: "lax",
        maxAge: VERIFIER_MAX_AGE,
      });

      const next = safeRedirectPath(params.next, "");
      const redirectTo = new URL(params.redirectTo);

      if (next) {
        redirectTo.searchParams.set("next", next);
      }

      return {
        url: authorizeUrlFor(
          deps.env().url,
          { ...params, redirectTo: redirectTo.href },
          challenge,
        ),
      };
    },

    async exchangeCode(params, options = {}) {
      const jar = await deps.jar();

      const verifier = jar
        .getAll()
        .find((cookie) => cookie.name === verifierName())?.value;

      jar.set(verifierName(), "", {
        path: "/",
        ...auth?.cookie?.options,
        httpOnly: true,
        sameSite: "lax",
        maxAge: 0,
      });

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

      if (scope === "others") {
        return {
          ok: true,
          data: {
            redirectTo: safeRedirectPath(params.next, options.fallback ?? "/"),
            mfa: false,
            session: current,
          },
          error: null,
        };
      }

      if (current) {
        deps.signedOut(current.userId);
      }

      return commit(ok(null), params.next, options);
    },
  };
}
