import type { AuthError, SupabaseClient } from "@supabase/supabase-js";

import { createServerClient } from "@supabase/ssr";

import type {
  AuthResolution,
  AuthState,
  ResolveAuthOptions,
} from "../auth/resolve.ts";
import type { CookieScope, CookieWrite } from "../auth/session.ts";
import type { ExistingAccount } from "../auth/sign-in.ts";
import type { SessionSnapshot } from "../auth/snapshot.ts";
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
import { applyCookieWrites, sessionCookieName } from "../auth/session.ts";
import {
  authFailure,
  isStandInUser,
  needsMfa,
  safeRedirectPath,
} from "../auth/sign-in.ts";
import { authOfSnapshot, snapshotOf } from "../auth/snapshot.ts";
import { clearCookieSession } from "../auth/ssr-client.ts";
import { dbError } from "../core/errors.ts";

interface CookieJar {
  getAll(): readonly { readonly name: string; readonly value: string }[];
  set(name: string, value: string, options: object): unknown;
}

const DEFAULT_TIMEOUT_MS = 5000;

/** The part of a new session a commit reads. */
interface Granted {
  readonly access_token: string;
  readonly user?: unknown;
}

/** One flow's `createServerClient` and the cookie writes it buffered. */
interface Flow {
  readonly auth: SupabaseClient["auth"];
  readonly writes: CookieWrite[];
  failed(error: AuthError, what: string): ActionResult<never>;
}

/**
 * Where to send the user after signing in: the `next` value of the search
 * params (a `URLSearchParams`, a page's `searchParams` object or a request)
 * when it is a same-origin path, else `fallback`.
 *
 * ```ts
 * redirect(postAuthPath(await searchParams, "/dashboard"));
 * ```
 */
export function postAuthPath(
  source:
    | Request
    | URLSearchParams
    | Readonly<Record<string, string | readonly string[] | undefined>>,
  fallback: string,
): string {
  if (source instanceof Request) {
    return safeRedirectPath(
      new URL(source.url).searchParams.get("next"),
      fallback,
    );
  }

  if (source instanceof URLSearchParams) {
    return safeRedirectPath(source.get("next"), fallback);
  }

  const next = source["next"];

  return safeRedirectPath(
    typeof next === "string" ? next : next?.[0],
    fallback,
  );
}

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
  ): Promise<ActionResult<SignedIn | ExistingAccount | null>>;
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
 * The server-side sign-in and sign-out flows. Each runs one auth-js call on a
 * `createServerClient` made for it, then one commit: it verifies the new token,
 * writes the cookies the client produced through the request's cookie jar, and
 * publishes the session to later reads in the same request. The result carries
 * no token: it crosses the action boundary, and the session is on the request's
 * reads.
 */
export function authFlows<C, P>(deps: AuthFlowDeps<C, P>): AuthFlows {
  const { auth } = deps;

  const cookieName = (): string =>
    auth?.cookie?.name ?? sessionCookieName(deps.env().url);

  /**
   * A server client on the request's cookies whose writes wait in `writes`: a
   * session reaches the jar only once its token verifies. With the secret key
   * and a client IP, Auth's per-IP rate limit counts the user, not the server
   * (`Sb-Forwarded-For`).
   */
  const flow = async (): Promise<Flow> => {
    const env = deps.env();

    const ip =
      env.secretKey && auth?.clientIp !== false
        ? (auth?.clientIp ?? clientIp)(await deps.request())
        : undefined;

    const forwarded = env.secretKey && ip ? env.secretKey : undefined;
    const existing = (await deps.jar()).getAll();
    const writes: CookieWrite[] = [];
    const baseFetch = auth?.fetch ?? fetch;
    const timeoutMs = auth?.refreshTimeoutMs ?? DEFAULT_TIMEOUT_MS;
    let timedOut = false;

    const timedFetch: typeof fetch = async (input, init) => {
      const timeout = AbortSignal.timeout(timeoutMs);

      try {
        return await baseFetch(input, {
          ...init,
          signal: init?.signal
            ? AbortSignal.any([init.signal, timeout])
            : timeout,
        });
      } catch (error) {
        timedOut ||= timeout.aborted;
        throw error;
      }
    };

    const client = createServerClient(
      env.url,
      forwarded ?? env.publishableKey,
      {
        cookieOptions: { ...auth?.cookie?.options, name: cookieName() },
        cookies: {
          getAll: () =>
            existing.map((cookie) => ({
              name: cookie.name,
              value: cookie.value,
            })),
          setAll: (cookies) => {
            writes.push(...cookies);
          },
          ...(auth?.cookie?.encode === undefined
            ? {}
            : { encode: auth.cookie.encode }),
        },
        global: {
          fetch: timedFetch,
          ...(forwarded && ip ? { headers: { "sb-forwarded-for": ip } } : {}),
        },
      },
    );

    return {
      auth: client.auth,
      writes,
      failed: (error, what) => ({
        ok: false,
        data: null,
        error: authFailure(error, what, timedOut),
      }),
    };
  };

  /** Writes a flow's cookies, such as the PKCE verifier of an email flow. */
  const keep = async (writes: readonly CookieWrite[]): Promise<void> => {
    const jar = await deps.jar();

    for (const write of writes) {
      jar.set(write.name, write.value, write.options);
    }
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

  const requested = async (
    started: Flow,
    error: AuthError | null,
    what: string,
  ): Promise<ActionResult<null>> => {
    await keep(started.writes);

    return error
      ? started.failed(error, what)
      : { ok: true, data: null, error: null };
  };

  const noSession = (what: string): ActionResult<never> => ({
    ok: false,
    data: null,
    error: dbError("unauthorized", `${what} returned no session`, {
      code: "no_session",
    }),
  });

  /**
   * Verifies `granted`, writes `writes` and publishes the session (`null` signs
   * out).
   */
  const commit = async (
    granted: Granted | null,
    writes: readonly CookieWrite[],
    next: string | null | undefined,
    options: SignInOptions,
  ): Promise<ActionResult<SignedIn>> => {
    const resolution = await deps.verify(granted?.access_token ?? null);

    if (granted && resolution.auth.kind !== "user") {
      return refused(resolution.auth);
    }

    const existing = (await deps.jar()).getAll();

    await keep(writes);

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
          granted !== null &&
          needsMfa(granted.user) &&
          snapshotOf(resolution.auth)?.claims["aal"] !== "aal2",
        user: resolution.auth.kind === "user" ? resolution.auth.user : null,
      },
      error: null,
    };
  };

  return {
    async signInWithPassword(credentials, options = {}) {
      const started = await flow();

      const { data, error } = await started.auth.signInWithPassword({
        email: credentials.email,
        password: credentials.password,
      });

      return error
        ? started.failed(error, "Sign-in")
        : commit(data.session, started.writes, credentials.next, options);
    },

    async verifyOtp(params, options = {}) {
      const started = await flow();

      const { data, error } = await started.auth.verifyOtp(
        "tokenHash" in params
          ? { type: params.type, token_hash: params.tokenHash }
          : { type: params.type, email: params.email, token: params.token },
      );

      if (error) {
        return started.failed(error, "Verification");
      }

      return data.session
        ? commit(data.session, started.writes, params.next, options)
        : noSession("Verification");
    },

    async signInWithOAuth(params) {
      const started = await flow();

      const { data, error } = await started.auth.signInWithOAuth({
        provider: params.provider,
        options: {
          redirectTo: callbackUrl(params),
          skipBrowserRedirect: true,
          ...(params.scopes ? { scopes: params.scopes } : {}),
          ...(params.queryParams
            ? { queryParams: { ...params.queryParams } }
            : {}),
        },
      });

      if (error) {
        throw error;
      }

      await keep(started.writes);

      return { url: data.url };
    },

    async signInWithOtp(params) {
      const started = await flow();

      const { error } = await started.auth.signInWithOtp({
        email: params.email,
        options: {
          emailRedirectTo: callbackUrl(params),
          shouldCreateUser: params.shouldCreateUser ?? true,
          data: { ...params.data },
        },
      });

      return requested(started, error, "Email request");
    },

    async resetPasswordForEmail(params) {
      const started = await flow();

      const { error } = await started.auth.resetPasswordForEmail(params.email, {
        redirectTo: callbackUrl(params),
      });

      return requested(started, error, "Email request");
    },

    async signUp(params, options = {}) {
      const started = await flow();

      const { data, error } = await started.auth.signUp({
        email: params.email,
        password: params.password,
        options: {
          emailRedirectTo: callbackUrl(params),
          data: { ...params.data },
        },
      });

      if (error) {
        return requested(started, error, "Sign-up");
      }

      if (data.session) {
        return commit(data.session, started.writes, params.next, options);
      }

      if (isStandInUser(data.user)) {
        await keep(started.writes);

        return {
          ok: true,
          data: { existingAccount: true } satisfies ExistingAccount,
          error: null,
        };
      }

      return requested(started, null, "Sign-up");
    },

    async resend(params) {
      const started = await flow();

      const { error } = await started.auth.resend({
        type: params.type,
        email: params.email,
        options: { emailRedirectTo: callbackUrl(params) },
      });

      return requested(started, error, "Email request");
    },

    async exchangeCodeForSession(params, options = {}) {
      const started = await flow();

      const { data, error } = await started.auth.exchangeCodeForSession(
        params.code,
      );

      if (error) {
        await keep(started.writes);

        return started.failed(error, "Code exchange");
      }

      return commit(data.session, started.writes, params.next, options);
    },

    async verifyMfa(params, options = {}) {
      if (!(await deps.current())) {
        return {
          ok: false,
          data: null,
          error: dbError("unauthorized", "MFA verification needs a session"),
        };
      }

      const started = await flow();

      const { data, error } = await started.auth.mfa.challengeAndVerify({
        factorId: params.factorId,
        code: params.code,
      });

      return error
        ? started.failed(error, "MFA verification")
        : commit(data, started.writes, params.next, options);
    },

    async signOut(params = {}, options = {}) {
      const scope = params.scope ?? "local";
      const current = await deps.current();

      if (current) {
        const started = await flow();
        const { error } = await started.auth.signOut({ scope });

        if (error) {
          return started.failed(error, "Sign-out");
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

      const cleared = await clearCookieSession({
        cookieName: cookieName(),
        cookies: (await deps.jar()).getAll(),
        ...(auth?.cookie?.options
          ? { cookieOptions: auth.cookie.options }
          : {}),
        scopes: deps.cookieScopes ?? [],
      });

      return commit(null, cleared.writes, params.next, options);
    },
  };
}
