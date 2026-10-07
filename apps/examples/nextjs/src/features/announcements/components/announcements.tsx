import { activeOrganizationId } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { AnnouncementBanner } from "./announcement-banner";

/** Render inside `<Suspense>`: reads the session. */
export async function Announcements() {
  const session = await getSession();
  if (session.kind !== "user") return null;
  return (
    <AnnouncementBanner
      organizationId={activeOrganizationId(session) ?? null}
    />
  );
}
