import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { settingsTabs } from "../settings-tabs";
import { SettingsNavLinks } from "./settings-nav-links";

/** Render inside `<Suspense>`: shows the tabs the caller's role allows. */
export async function SettingsNav() {
  const session = await getSession();
  const visible = settingsTabs
    .filter((tab) => !tab.requires || can(session, tab.requires))
    .map((tab) => tab.id);
  return <SettingsNavLinks visible={visible} />;
}

export function SettingsNavSkeleton() {
  return <Skeleton className="h-9 w-full max-w-2xl" aria-busy="true" />;
}
