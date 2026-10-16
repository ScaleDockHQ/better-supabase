import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { SettingsLayout } from "./settings-layout";

/**
 * Render inside `<Suspense>`. The settings module checks `settings.update`
 * on every write; the session decides which controls are enabled.
 */
export async function Preferences() {
  const session = await getSession();
  return (
    <SettingsLayout canEditOrganization={can(session, "settings.update")} />
  );
}

export function PreferencesSkeleton() {
  return (
    <div className="space-y-6" aria-busy="true">
      <Skeleton className="h-40 rounded-xl" />
      <Skeleton className="h-56 rounded-xl" />
    </div>
  );
}
