import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Whether the client has an auth module to follow. A client built by hand for
 * Storage or Realtime only (or a test stand-in) has none.
 */
export function hasAuthModule(supabase: SupabaseClient): boolean {
  const auth: Partial<SupabaseClient["auth"]> | undefined = supabase.auth;

  // oxlint-disable-next-line typescript/no-unnecessary-condition, typescript/no-deprecated -- the type says present, a hand-built client may not have it; only the presence is read.
  return typeof auth?.onAuthStateChange === "function";
}
