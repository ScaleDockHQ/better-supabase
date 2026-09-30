import { createBrowserClient } from "@supabase/ssr";
import {
  createClient,
  type Session,
  type SupabaseClient,
} from "@supabase/supabase-js";

import type { BetterSupabase } from "../core/define.ts";
import type { Actor, RequestContext } from "../core/plugin.ts";
import type { Db } from "../core/repository-types.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";

import { EnvValidationError, parseEnv, type PublicEnv } from "../env/index.ts";
import { createQueries, type Queries } from "../query/index.ts";

export interface BrowserOptions {
  /** URL and publishable key. Not needed when `client` is given. */
  readonly env?: PublicEnv;
  /** Bring your own supabase-js client (React Native, custom storage). */
  readonly client?: SupabaseClient;
  /**
   * `cookies` (default) shares the session with the server through
   * `@supabase/ssr`; `local` keeps it in localStorage for SPAs without a server.
   */
  readonly storage?: "cookies" | "local";
}

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

export interface BrowserAuth {
  readonly current: () => AuthSnapshot;
  /** `useSyncExternalStore`-compatible. */
  readonly subscribe: (listener: () => void) => () => void;
}

export interface BetterBrowser<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> {
  /** The definition the browser was created from (schema metadata, specs, live queries). */
  readonly sb: BetterSupabase<M, unknown, F, E, C, P>;
  readonly supabase: SupabaseClient;
  /** Repositories with the current session's actor and claims. */
  readonly db: Db<M, F, E, SupabaseClient>;
  /** TanStack Query option factories over `db`. */
  readonly queries: Queries<M, E, F>;
  readonly auth: BrowserAuth;
}

const LOADING: AuthSnapshot = { status: "loading", user: null, claims: null };
const SIGNED_OUT: AuthSnapshot = {
  status: "signed-out",
  user: null,
  claims: null,
};

function decodeClaims(token: string): Record<string, unknown> {
  const part = token.split(".")[1];
  if (!part) return {};
  try {
    const bytes = Uint8Array.from(
      atob(part.replace(/-/g, "+").replace(/_/g, "/")),
      (char) => char.charCodeAt(0),
    );
    const parsed: unknown = JSON.parse(new TextDecoder().decode(bytes));
    // SAFETY: parsed is a non-null object, and callers check each claim they read.
    return typeof parsed === "object" && parsed !== null
      ? (parsed as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

function snapshotOf(session: Session | null): AuthSnapshot {
  if (!session) return SIGNED_OUT;
  const claims = decodeClaims(session.access_token);
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
  const actor: Actor = {
    id: snapshot.user.id,
    kind: "user",
    ...(snapshot.user.role ? { role: snapshot.user.role } : {}),
    ...(snapshot.user.email ? { email: snapshot.user.email } : {}),
  };
  return { actor, claims: snapshot.claims };
}

function clientFor(options: BrowserOptions): SupabaseClient {
  if (options.client) return options.client;
  if (!options.env)
    throw new TypeError(
      "createBrowser needs `env` ({ url, publishableKey }) or `client`",
    );
  const checked = parseEnv({
    SUPABASE_URL: options.env.url,
    SUPABASE_PUBLISHABLE_KEY: options.env.publishableKey,
  });
  if (!checked.ok) throw new EnvValidationError(checked.issues);
  if (options.storage === "local")
    // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
    return createClient(checked.env.url, checked.env.publishableKey);
  // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
  return createBrowserClient(checked.env.url, checked.env.publishableKey);
}

/**
 * The browser side: a supabase-js client, repositories that follow the
 * session, TanStack Query options and an auth store for UI state.
 *
 * ```ts
 * export const browser = createBrowser(sb, { env: { url, publishableKey } });
 * ```
 */
export function createBrowser<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  sb: BetterSupabase<M, D, F, E, C, P>,
  options: BrowserOptions = {},
): BetterBrowser<M, F, E, C, P> {
  const supabase = clientFor(options);
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

  const browser: BetterBrowser<M, F, E, C, P> = {
    sb: sb,
    supabase,
    get db() {
      db ??= sb.connect(supabase, contextOf(snapshot));
      return db;
    },
    queries: createQueries(sb, () => browser.db),
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
  return browser;
}
