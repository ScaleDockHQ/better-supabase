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

/** The key `createNext` stores the pieces `createAuthFlows` needs under. */
export const AUTH_FLOWS_HOST: unique symbol = Symbol.for(
  "better-supabase.next.auth-flows-host",
);

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
  /**
   * Signs in with an email and a password from a server action. It writes the
   * session cookies, stores the verified session for the next render and
   * returns `redirectTo`: `credentials.next` when it is a same-origin path,
   * else `options.fallback` (`/`). Reads later in the same request
   * (`getClaims()`, `claims()`, `context()`) see the new session.
   */
  signInWithPassword(
    credentials: SignInCredentials,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * Verifies an email link's `token_hash` (sign-up, invite, magic link,
   * recovery, email change) or an emailed code, then commits the session like
   * `signInWithPassword`. The new session replaces any session the request
   * carried.
   */
  verifyOtp(
    params: VerifyOtpParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * The Auth server's OAuth URL for `provider`, for a `redirect()`, from
   * auth-js's `signInWithOAuth`. auth-js stores the PKCE verifier in a cookie
   * through `@supabase/ssr`, where `exchangeCodeForSession` reads it. `next`
   * rides on `redirectTo` as `?next=` when it is a same-origin path.
   */
  signInWithOAuth(
    params: SignInWithOAuthParams,
  ): Promise<{ readonly url: string }>;
  /**
   * Exchanges the callback's `?code=` and the PKCE verifier cookie for a
   * session with auth-js, and commits it like `signInWithPassword`.
   */
  exchangeCodeForSession(
    params: ExchangeCodeParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * Challenges and verifies an MFA factor for the signed-in user and commits
   * the `aal2` session; `mfa` is then false.
   */
  verifyMfa(
    params: MfaVerification,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * Ends the session on the Auth server first (`scope`, `local` by default),
   * then clears the session cookies (also at `cookieScopes`), forgets the
   * verified sessions and expires its cache tags. `others` keeps this session
   * and its cookies, and still forgets the verified sessions. Reads later in
   * the same request are signed out.
   */
  signOut(
    params?: SignOutParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn>>;
  /**
   * Emails a magic link and a code. It writes the PKCE verifier cookie like
   * `signInWithOAuth`, so the link's `?code=` goes to `exchangeCodeForSession`,
   * and the code to `verifyOtp` with `type: "email"`. Returns `null`: nothing
   * is signed in yet.
   */
  signInWithOtp(params: SignInWithOtpParams): Promise<ActionResult<null>>;
  /**
   * Emails a password reset link with the PKCE verifier cookie.
   * `exchangeCodeForSession` on the callback signs the user in; the app then
   * asks for the new password. Auth answers the same whether or not an account
   * has the email.
   */
  resetPasswordForEmail(
    params: ResetPasswordParams,
  ): Promise<ActionResult<null>>;
  /**
   * Signs up with an email and a password. With email confirmation on, it
   * emails the confirmation link with the PKCE verifier cookie and returns
   * `null`. With it off, Auth returns a session, committed like
   * `signInWithPassword`. When the email already has a confirmed account, Auth
   * sends nothing and this returns `{ existingAccount: true }`, so the app can
   * email the owner itself. Show the user the same screen either way, so the
   * page doesn't tell who has an account.
   */
  signUp(
    params: SignUpParams,
    options?: SignInOptions,
  ): Promise<ActionResult<SignedIn | ExistingAccount | null>>;
  /**
   * Emails the sign-up confirmation or the email change link again, with a new
   * PKCE verifier.
   */
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
function authFlows<C, P>(deps: AuthFlowDeps<C, P>): AuthFlows {
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
    const target = URL.parse(params.redirectTo);

    // Supabase Auth rejects a redirect outside the allow list, so the flow
    // reports it as a failed request instead of throwing here.
    if (target === null) {
      return params.redirectTo;
    }

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

      // auth-js stores a PKCE verifier for the confirmation link even when
      // confirmation is off and the session comes back at once; no link will
      // spend it, so the commit expires it instead.
      if (data.session) {
        const writes = started.writes.map((write) =>
          write.name.endsWith("-code-verifier")
            ? { ...write, value: "", options: { ...write.options, maxAge: 0 } }
            : write,
        );

        return commit(data.session, writes, params.next, options);
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

/**
 * The server-side sign-in and sign-out flows of a `createNext` instance. They
 * live on their own subpath so an app that signs in with the browser client
 * does not ship them (ADR 1258).
 *
 * ```ts
 * export const flows = createAuthFlows(bsb);
 * ```
 */
export function createAuthFlows<C, P>(bsb: {
  readonly [AUTH_FLOWS_HOST]: AuthFlowDeps<C, P>;
}): AuthFlows {
  return authFlows(bsb[AUTH_FLOWS_HOST]);
}
