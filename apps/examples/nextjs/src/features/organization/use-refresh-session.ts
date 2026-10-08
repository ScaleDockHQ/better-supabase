"use client";

import { useSessionChange } from "better-supabase/next/client";

import { sessionChanged } from "@/features/user/user-actions";
import { useRouter } from "@/i18n/navigation";
import { useSupabase } from "@/lib/hooks";

/**
 * After a switch, the active tenant and the `memberships` claim live in a
 * new access token: `refreshToken` refreshes it in the browser (the proxy
 * sees the new cookie), the server re-renders with it, then it goes to `to`.
 */
export function useRefreshSession(): (to: string) => Promise<void> {
  return useSessionChange(sessionChanged, useRouter(), {
    refreshToken: useSupabase(),
  });
}
