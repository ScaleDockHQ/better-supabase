import type { AuthResolution, AuthState } from "../auth/resolve.ts";
import type { SessionMemoOptions, SessionSnapshot } from "../auth/snapshot.ts";
import type { AuthzVersionCache } from "../core/authorizer.ts";
import type { ServerSessions } from "./server-types.ts";

import { requestToken } from "../auth/resolve.ts";
import { sessionMemo, snapshotOf } from "../auth/snapshot.ts";
import { dbError } from "../core/errors.ts";

/** A memoized session: the verified user and the snapshot handed out for it. */
interface VerifiedSession<C, P> {
  readonly auth: Extract<AuthState<C, P>, { readonly kind: "user" }>;
  readonly snapshot: SessionSnapshot<C>;
}

/** The placeholder URL of the request a snapshot's token is verified on. */
const SNAPSHOT_URL = "http://snapshot.invalid/";

export interface SessionsOptions<C, P, Ctx> {
  readonly resolve: (
    request: Request,
    options: { readonly refresh: false; readonly cookies?: false },
  ) => Promise<AuthResolution<C, P>>;
  readonly cookieName: () => string;
  /** Read the session cookie (`auth.cookies`). */
  readonly cookies: boolean;
  /**
   * A custom resolver or the lite backend may read credentials `requestToken`
   * doesn't know, so their requests skip the memo.
   */
  readonly custom: boolean;
  readonly memo: SessionMemoOptions | false | undefined;
  readonly versions: AuthzVersionCache | undefined;
  /** A context for an auth state, without a request. */
  readonly contextFor: (auth: AuthState<C, P>, options: object) => Ctx;
}

/** The members of `BetterServer` that the verified-session memo backs. */
export function serverSessions<C, P, Ctx, Opts extends object>(
  options: SessionsOptions<C, P, Ctx>,
): {
  readonly snapshot: (request: Request) => Promise<SessionSnapshot<C> | null>;
  readonly contextFromSession: (
    snapshot: SessionSnapshot<C> | null,
    options?: Opts,
  ) => Promise<Ctx>;
  readonly sessions: ServerSessions<C, P>;
  readonly forgetSession: (userId: string) => Promise<void>;
} {
  const memo =
    options.memo === false
      ? undefined
      : sessionMemo<VerifiedSession<C, P>>(
          (verified) => verified.auth.expiresAt,
          options.memo,
        );

  const verified = (
    auth: AuthState<C, P>,
    token: string,
  ): VerifiedSession<C, P> | null => {
    if (auth.kind !== "user" || auth.token !== token) {
      return null;
    }

    const snapshot = snapshotOf(auth);

    return snapshot ? { auth, snapshot } : null;
  };

  const snapshot = async (
    request: Request,
  ): Promise<SessionSnapshot<C> | null> => {
    const token = options.custom
      ? null
      : requestToken(request, options.cookieName(), options.cookies);

    if (!token || !memo) {
      const resolution = await options.resolve(request, { refresh: false });

      return snapshotOf(resolution.auth);
    }

    const found = await memo.get(token, async () => {
      const resolution = await options.resolve(request, { refresh: false });

      return verified(resolution.auth, token);
    });

    return found?.snapshot ?? null;
  };

  const verifyToken = async (
    token: string,
  ): Promise<VerifiedSession<C, P> | null> => {
    const load = async (): Promise<VerifiedSession<C, P> | null> => {
      const resolution = await options.resolve(
        new Request(SNAPSHOT_URL, {
          headers: { authorization: `Bearer ${token}` },
        }),
        { refresh: false, cookies: false },
      );

      return verified(resolution.auth, token);
    };

    return memo ? memo.get(token, load) : load();
  };

  const contextFromSession = async (
    session: SessionSnapshot<C> | null,
    contextOptions?: Opts,
  ): Promise<Ctx> => {
    const found = session ? await verifyToken(session.accessToken) : null;

    const auth: AuthState<C, P> = session
      ? found && found.auth.user.id === session.userId
        ? found.auth
        : {
            kind: "invalid",
            reason: "token",
            error: dbError("unauthorized", "The session snapshot is invalid"),
          }
      : { kind: "anon", reason: "none" };

    return options.contextFor(auth, contextOptions ?? {});
  };

  const evict = (userId: string): void => {
    memo?.evict((session) => session.auth.user.id === userId);
  };

  return {
    snapshot,
    contextFromSession,
    sessions: {
      stats: () => memo?.stats() ?? { hits: 0, misses: 0, size: 0 },
      seed: async (auth) => {
        const found = auth.kind === "user" ? verified(auth, auth.token) : null;

        if (found && memo) {
          await memo.seed(found.auth.token, found);
        }
      },
      evict,
      clear: () => memo?.clear(),
    },
    forgetSession: async (userId) => {
      evict(userId);
      await options.versions?.evict(userId);
    },
  };
}
