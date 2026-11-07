import { tenantOf } from "better-supabase/next";

import { getSession } from "@/features/user/user-queries";

import { AnnouncementBanner } from "./announcement-banner";

// skeleton: none, the layout's fallback is null because the banner reserves no space
/** Render inside `<Suspense>`: reads the session. */
export async function Announcements() {
  const session = await getSession();

  if (session.kind !== "user") {
    return null;
  }

  return <AnnouncementBanner organizationId={tenantOf(session) ?? null} />;
}
