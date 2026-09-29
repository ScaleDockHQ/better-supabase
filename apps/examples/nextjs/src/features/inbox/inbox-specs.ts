import { sb } from '@/lib/supabase';

/** The caller's unread notifications; RLS keeps it to their own rows. */
export const unreadSpec = sb.spec.notifications.count({
  where: { readAt: null },
});
