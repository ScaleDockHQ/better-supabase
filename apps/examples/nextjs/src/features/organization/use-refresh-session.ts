"use client";

import { sessionChanged } from "@/features/user/user-actions";
import { useRouter } from "@/i18n/navigation";
import { useSupabase } from "@/lib/hooks";

/**
 * After a switch, the active tenant and the `memberships` claim live in a
 * new access token: refresh it in the browser (the proxy sees the new
 * cookie), let the server re-render with it, then go to `to`. The client
 * `router.refresh()` is needed too: `refresh()` in the Server Action leaves
 * the prefetched private App Shells, so `router.push` would show the old
 * organization.
 */
export function useRefreshSession(): (to: string) => Promise<void> {
  const supabase = useSupabase();
  const router = useRouter();
  return async (to) => {
    await supabase.auth.refreshSession();
    await sessionChanged();
    router.push(to);
    router.refresh();
  };
}
