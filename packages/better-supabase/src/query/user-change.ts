import type { QueryClient } from "@tanstack/query-core";

/** The part of `createClient().auth` that `clearOnUserChange` reads. */
export interface UserChangeSource {
  subscribe(listener: () => void): () => void;
  current(): {
    readonly status: string;
    readonly user: { readonly id: string } | null;
  };
}

/**
 * Removes every `['bs', ...]` query when the signed-in user changes or signs
 * out, so the next user never sees the previous user's rows. Returns the
 * function that stops listening. `BetterSupabaseProvider` calls it for React;
 * call it yourself with Vue, Solid, Svelte or Angular Query.
 *
 * ```ts
 * const stop = clearOnUserChange(queryClient, bs.auth);
 * ```
 */
export function clearOnUserChange(
  queryClient: Pick<QueryClient, "removeQueries">,
  auth: UserChangeSource,
): () => void {
  let user: string | null | undefined;
  const check = (): void => {
    const snapshot = auth.current();
    if (snapshot.status === "loading") return;
    const id = snapshot.user?.id ?? null;
    if (user !== undefined && user !== id) {
      queryClient.removeQueries({ queryKey: ["bs"] });
    }
    user = id;
  };
  const stop = auth.subscribe(check);
  check();
  return stop;
}
