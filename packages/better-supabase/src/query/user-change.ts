import type { QueryClient } from "@tanstack/query-core";

/** The part of `createClient().auth` that `clearOnUserChange` reads. */
export interface UserChangeSource {
  subscribe(listener: () => void): () => void;
  current(): {
    readonly status: string;
    readonly user: { readonly id: string } | null;
    readonly claims?: Readonly<Record<string, unknown>> | null;
  };
}

/** Claims every refresh changes; the rest says who the caller is and what RLS lets them read. */
const TIME_CLAIMS = new Set(["exp", "iat", "nbf", "jti"]);

/**
 * The user plus every claim except the time claims, so a token refresh keeps
 * the identity and an organization switch, a role change or a second factor
 * (a new `tenant_id`, `role` or `aal`) changes it.
 */
export function identityKey(
  snapshot: ReturnType<UserChangeSource["current"]>,
): string | null {
  if (!snapshot.user) return null;
  const claims = Object.entries(snapshot.claims ?? {})
    .filter(([key]) => !TIME_CLAIMS.has(key))
    .toSorted(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return JSON.stringify([snapshot.user.id, claims]);
}

/**
 * Resets every `['bs', ...]` query when the caller changes: another user,
 * signing out, or new claims for the same user (an organization switch, a
 * role change). Mounted queries refetch, so no one sees the previous
 * identity's rows. Returns the function that stops listening.
 * `BetterSupabaseProvider` calls it for React; call it yourself with Vue,
 * Solid, Svelte or Angular Query.
 *
 * Queries that fetched while the session was still loading ran as anon, so
 * they are reset when a user arrives. Data already in the cache when loading
 * started (hydrated from the server) stays.
 *
 * ```ts
 * const stop = clearOnUserChange(queryClient, bs.auth);
 * ```
 */
export function clearOnUserChange(
  queryClient: Pick<QueryClient, "resetQueries" | "getQueryCache">,
  auth: UserChangeSource,
): () => void {
  let identity: string | null | undefined;
  let before: Map<string, number> | undefined;
  const bsQueries = () =>
    queryClient.getQueryCache().findAll({ queryKey: ["bs"] });
  const check = (): void => {
    const snapshot = auth.current();
    if (snapshot.status === "loading") {
      before ??= new Map(
        bsQueries().map((query) => [
          query.queryHash,
          query.state.dataUpdatedAt,
        ]),
      );
      return;
    }
    const next = identityKey(snapshot);
    if (identity !== undefined && identity !== next) {
      void queryClient.resetQueries({ queryKey: ["bs"] });
    } else if (identity === undefined && next !== null && before) {
      const known = before;
      const fetchedAsAnon = new Set(
        bsQueries()
          .filter(
            (query) =>
              query.state.dataUpdatedAt > 0 &&
              known.get(query.queryHash) !== query.state.dataUpdatedAt,
          )
          .map((query) => query.queryHash),
      );
      if (fetchedAsAnon.size > 0) {
        void queryClient.resetQueries({
          queryKey: ["bs"],
          predicate: (query) => fetchedAsAnon.has(query.queryHash),
        });
      }
    }
    before = undefined;
    identity = next;
  };
  const stop = auth.subscribe(check);
  check();
  return stop;
}
