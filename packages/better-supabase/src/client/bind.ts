import type { Session, SupabaseClient } from "@supabase/supabase-js";

import type { BetterSupabase } from "../core/define.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Db } from "../core/repository-types.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";

import { userContext } from "../auth/impersonation.ts";
import { decodeJwtPayload } from "../core/base64.ts";
import { createQueries, type BetterQueries } from "../query/index.ts";
import { identityKey } from "../query/user-change.ts";

export interface AuthUser {
  readonly id: string;
  readonly email?: string;
  readonly role?: string;
}

/**
 * What the UI needs to know. Claims are decoded, not verified: RLS enforces
 * access. A token refresh that changes only `exp`, `iat`, `nbf` or `jti`
 * keeps the previous snapshot, so read expiry from the session, not here.
 */
export type AuthSnapshot =
  | { readonly status: "loading"; readonly user: null; readonly claims: null }
  | {
      readonly status: "signed-out";
      readonly user: null;
      readonly claims: null;
    }
  | {
      readonly status: "signed-in";
      readonly user: AuthUser;
      readonly claims: Readonly<Record<string, unknown>>;
    };

export interface ClientAuth {
  readonly current: () => AuthSnapshot;
  /** `useSyncExternalStore`-compatible. */
  readonly subscribe: (listener: () => void) => () => void;
}

export interface BetterClient<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> {
  /** The definition the client was created from (schema metadata, specs, live queries). */
  readonly betterSupabase: BetterSupabase<M, unknown, F, E, C, P>;
  readonly supabase: SupabaseClient;
  /** Repositories with the current session's actor and claims. */
  readonly db: Db<M, F, E, SupabaseClient>;
  /** TanStack Query option factories over `db`. */
  readonly queries: BetterQueries<M, E, F>;
  readonly auth: ClientAuth;
  /**
   * Stops following `supabase`'s session. Call it when the client goes away
   * before the app does: Fast Refresh, tests, a client per account.
   */
  readonly dispose: () => void;
}

export interface BindClientOptions {
  /**
   * `staleTime` for every query option in `queries`. Above zero, a remount
   * or a window focus reuses cached rows instead of refetching them.
   */
  readonly staleTime?: number;
}

const LOADING: AuthSnapshot = { status: "loading", user: null, claims: null };
const SIGNED_OUT: AuthSnapshot = {
  status: "signed-out",
  user: null,
  claims: null,
};

/**
 * `session.user`, or `undefined` when auth-js put its placeholder there: with
 * `tokens-only` cookies and no user in `userStorage`, reading `id` throws.
 */
function storedUser(session: Session): Session["user"] | undefined {
  try {
    return typeof session.user.id === "string" ? session.user : undefined;
  } catch {
    return undefined;
  }
}

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value !== "" ? value : undefined;

function snapshotOf(session: Session | null): AuthSnapshot {
  if (!session) return SIGNED_OUT;
  const claims = decodeJwtPayload(session.access_token) ?? {};
  const stored = storedUser(session);
  const id = text(claims["sub"]) ?? stored?.id;
  if (id === undefined) return SIGNED_OUT;
  const email = text(claims["email"]) ?? text(stored?.email);
  const role = text(claims["role"]) ?? text(stored?.role);
  return {
    status: "signed-in",
    user: {
      id,
      ...(email ? { email } : {}),
      ...(role ? { role } : {}),
    },
    claims,
  };
}

function contextOf(snapshot: AuthSnapshot): RequestContext {
  if (snapshot.status !== "signed-in") {
    return {
      actor: { id: "anon", kind: "anon", role: "anon" },
      claims: { role: "anon" },
    };
  }
  return userContext(snapshot.user, snapshot.claims);
}

/**
 * Repositories that follow `supabase`'s session, TanStack Query options and
 * an auth store, for a supabase-js client you created yourself.
 */
export function bindClient<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  supabase: SupabaseClient,
  options: BindClientOptions = {},
): BetterClient<M, F, E, C, P> {
  let snapshot: AuthSnapshot = LOADING;
  let db: Db<M, F, E, SupabaseClient> | undefined;
  const listeners = new Set<() => void>();

  const { data } = supabase.auth.onAuthStateChange((_event, session) => {
    const next = snapshotOf(session);
    // A refresh only moves the time claims: keeping the snapshot keeps `db`
    // and spares every `useAuth` consumer a render once an hour.
    if (
      next.status === snapshot.status &&
      identityKey(next) === identityKey(snapshot)
    )
      return;
    snapshot = next;
    db = undefined;
    for (const listener of listeners) listener();
  });

  const client: BetterClient<M, F, E, C, P> = {
    betterSupabase,
    supabase,
    get db() {
      db ??= betterSupabase.connect(supabase, contextOf(snapshot));
      return db;
    },
    queries: createQueries(
      betterSupabase,
      () => client.db,
      options.staleTime === undefined ? {} : { staleTime: options.staleTime },
    ),
    dispose: () => {
      data.subscription.unsubscribe();
      listeners.clear();
    },
    auth: {
      current: () => snapshot,
      subscribe: (listener) => {
        listeners.add(listener);
        return () => {
          listeners.delete(listener);
        };
      },
    },
  };
  return client;
}
