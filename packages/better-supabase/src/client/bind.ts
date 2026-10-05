import type { Session, SupabaseClient } from "@supabase/supabase-js";

import type { BetterSupabase } from "../core/define.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Db } from "../core/repository-types.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";

import { userContext } from "../auth/impersonation.ts";
import { decodeJwtPayload } from "../core/base64.ts";
import { createQueries, type BetterQueries } from "../query/index.ts";

export interface AuthUser {
  readonly id: string;
  readonly email?: string;
  readonly role?: string;
}

/** What the UI needs to know. Claims are decoded, not verified: RLS enforces access. */
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
}

const LOADING: AuthSnapshot = { status: "loading", user: null, claims: null };
const SIGNED_OUT: AuthSnapshot = {
  status: "signed-out",
  user: null,
  claims: null,
};

function snapshotOf(session: Session | null): AuthSnapshot {
  if (!session) return SIGNED_OUT;
  const claims = decodeJwtPayload(session.access_token) ?? {};
  const role =
    typeof claims["role"] === "string" ? claims["role"] : session.user.role;
  return {
    status: "signed-in",
    user: {
      id: session.user.id,
      ...(session.user.email ? { email: session.user.email } : {}),
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
): BetterClient<M, F, E, C, P> {
  let snapshot: AuthSnapshot = LOADING;
  let db: Db<M, F, E, SupabaseClient> | undefined;
  const listeners = new Set<() => void>();

  supabase.auth.onAuthStateChange((_event, session) => {
    const next = snapshotOf(session);
    const changed =
      next.status !== snapshot.status ||
      next.user?.id !== snapshot.user?.id ||
      (next.status === "signed-in" &&
        snapshot.status === "signed-in" &&
        next.claims["exp"] !== snapshot.claims["exp"]);
    if (!changed) return;
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
    queries: createQueries(betterSupabase, () => client.db),
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
