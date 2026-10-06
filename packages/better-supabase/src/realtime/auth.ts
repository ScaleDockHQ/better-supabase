import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Hands the client's access token to Realtime before a private join,
 * unless the app set one itself with `realtime.setAuth(token)`. A bare
 * `setAuth()` replaces such a token with the session's, so a client that
 * joins with a token minted for Realtime (a service or agent token) keeps it.
 * realtime-js versions without the manual-token check always refresh.
 */
export async function refreshRealtimeAuth(
  client: Pick<SupabaseClient, "realtime">,
): Promise<void> {
  if (manualToken(client.realtime)) return;
  await client.realtime.setAuth();
}

/** Whether realtime-js says the token came from `setAuth(token)`. */
function manualToken(realtime: object): boolean {
  if (!("_isManualToken" in realtime)) return false;
  // oxlint-disable-next-line no-underscore-dangle -- realtime-js names its internal check this way.
  const check = realtime._isManualToken;
  return typeof check === "function" && check.call(realtime) === true;
}
