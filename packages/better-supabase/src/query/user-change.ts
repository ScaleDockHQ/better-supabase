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
 * ```ts
 * const stop = clearOnUserChange(queryClient, bs.auth);
 * ```
 */
export function clearOnUserChange(
  queryClient: Pick<QueryClient, "resetQueries">,
  auth: UserChangeSource,
): () => void {
  let identity: string | null | undefined;
  const check = (): void => {
    const snapshot = auth.current();
    if (snapshot.status === "loading") return;
    const next = identityKey(snapshot);
    if (identity !== undefined && identity !== next) {
      void queryClient.resetQueries({ queryKey: ["bs"] });
    }
    identity = next;
  };
  const stop = auth.subscribe(check);
  check();
  return stop;
}
