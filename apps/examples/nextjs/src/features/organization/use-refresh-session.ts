"use client";

import { useSessionChange } from "better-supabase/next/client";

import { sessionChanged } from "@/features/user/user-actions";
import { useRouter } from "@/i18n/navigation";
import { useSupabase } from "@/lib/hooks";

/**
 * After a switch, the active tenant and the `memberships` claim live in a
 * new access token: refresh it in the browser (the proxy sees the new
 * cookie), let the server re-render with it, then go to `to`.
 */
export function useRefreshSession(): (to: string) => Promise<void> {
  const supabase = useSupabase();
  const router = useRouter();
  return useSessionChange(async () => {
    await supabase.auth.refreshSession();
    await sessionChanged();
  }, router);
}
