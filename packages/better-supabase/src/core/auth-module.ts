import type { SupabaseClient } from "@supabase/supabase-js";

type AuthEvents = Pick<SupabaseClient["auth"], "onAuthStateChange">;

/**
 * The client's auth module, when it has one to follow. A client built by hand
 * for Storage or Realtime only (a `relayRealtimeClient`, a test stand-in) has
 * none.
 */
export function authModuleOf(client: object): AuthEvents | undefined {
  if (!("auth" in client)) {
    return undefined;
  }

  const auth: unknown = client.auth;

  if (
    typeof auth !== "object" ||
    auth === null ||
    !("onAuthStateChange" in auth) ||
    typeof auth.onAuthStateChange !== "function"
  ) {
    return undefined;
  }

  // SAFETY: a supabase-js auth module; `onAuthStateChange` was checked above.
  return auth as AuthEvents;
}

/** Whether the client has an auth module to follow. */
export function hasAuthModule(supabase: object): boolean {
  return authModuleOf(supabase) !== undefined;
}
