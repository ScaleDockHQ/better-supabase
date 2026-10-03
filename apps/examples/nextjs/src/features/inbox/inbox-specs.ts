import { betterSupabase } from "@/lib/supabase";

/** The caller's unread notifications; RLS keeps it to their own rows. */
export const unreadSpec = betterSupabase.spec.notifications.count({
  where: { readAt: null },
});
