import type {
  AuthResolution,
  AuthState,
  VerifiedUser,
} from "../auth/resolve.ts";
import type { SessionMemo, SessionSnapshot } from "../auth/snapshot.ts";
import type { AuthzVersionCache } from "../core/authorizer.ts";
import type { ServerSessions } from "./server-types.ts";

import { authOfSnapshot, snapshotOf } from "../auth/snapshot.ts";
import { dbError } from "../core/errors.ts";

const ANON = { kind: "none", reason: "none" } as const;

/**
 * The verified state behind a snapshot this process built, `anon` once it
 * expired, and `invalid` for a forged or deserialized one.
 */
function authFor<C, P>(session: SessionSnapshot<C>): AuthState<C, P> {
  const source = authOfSnapshot<C, P>(session);

  if (!source) {
    return {
      kind: "invalid",
      reason: "token",
      error: dbError("unauthorized", "The session snapshot is invalid"),
    };
  }

  if (session.expiresAt !== null && session.expiresAt * 1000 <= Date.now()) {
    return { kind: "none", reason: "expired" };
  }

  return source;
}

export interface SessionsOptions<C, P, Ctx> {
  /** Resolves a request; its token verification goes through `memo`. */
  readonly resolve: (
    request: Request,
    options: { readonly refresh: false; readonly cookies?: false },
  ) => Promise<AuthResolution<C, P>>;
  /** The server's verified-token memo, `undefined` with `sessions: false`. */
  readonly memo: SessionMemo<VerifiedUser> | undefined;
  readonly versions: AuthzVersionCache | undefined;
  /** A context for an auth state, without a request. */
  readonly contextFor: (auth: AuthState<C, P>, options: object) => Ctx;
}

/** The members of `BetterServer` that the verified-token memo backs. */
export function serverSessions<C, P, Ctx, Opts extends object>(
  options: SessionsOptions<C, P, Ctx>,
): {
  readonly snapshot: (request: Request) => Promise<SessionSnapshot<C> | null>;
  readonly contextFromSession: (
    snapshot: SessionSnapshot<C> | null,
    options?: Opts,
  ) => Promise<Ctx>;
  readonly sessions: ServerSessions<C, P>;
  readonly evictSession: (userId: string) => Promise<void>;
} {
  const { memo } = options;

  /** A memo hit returns the stored user, so its snapshot is built once. */
  const snapshots = new WeakMap<object, SessionSnapshot<C> | null>();

  /** Loaders of one request share its resolution until an eviction. */
  let byRequest = new WeakMap<Request, Promise<SessionSnapshot<C> | null>>();

  const build = async (
    request: Request,
  ): Promise<SessionSnapshot<C> | null> => {
    const { auth } = await options.resolve(request, { refresh: false });
    let found = snapshots.get(auth);

    if (found === undefined) {
      found = snapshotOf(auth);
      snapshots.set(auth, found);
    }

    return found;
  };

  const snapshot = (request: Request): Promise<SessionSnapshot<C> | null> => {
    let found = byRequest.get(request);

    if (!found) {
      found = build(request);
      byRequest.set(request, found);
    }

    return found;
  };

  const contextFromSession = (
    session: SessionSnapshot<C> | null,
    contextOptions?: Opts,
  ): Promise<Ctx> => {
    const auth = session ? authFor<C, P>(session) : ANON;

    return Promise.resolve(options.contextFor(auth, contextOptions ?? {}));
  };

  const evict = (userId: string): void => {
    byRequest = new WeakMap();
    memo?.evict((user) => user.user.id === userId);
  };

  return {
    snapshot,
    contextFromSession,
    sessions: {
      stats: () => memo?.stats() ?? { hits: 0, misses: 0, size: 0 },
      seed: async (auth) => {
        if (auth.kind === "user" && auth.token !== "" && memo) {
          await memo.seed(auth.token, auth);
        }
      },
      evict,
      clear: () => {
        byRequest = new WeakMap();
        memo?.clear();
      },
    },
    evictSession: async (userId) => {
      evict(userId);
      await options.versions?.evict(userId);
    },
  };
}
