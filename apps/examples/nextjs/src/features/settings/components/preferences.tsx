import { getExtracted, getLocale } from "next-intl/server";

import { KpiBand } from "@/components/record-list/kpi-band";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { SettingsLayout } from "./settings-layout";

/**
 * Render inside `<Suspense>`. The settings module checks `settings.update` on
 * every write; the session decides which controls are enabled.
 */
export async function Preferences() {
  const [permissions, locale, t] = await Promise.all([
    getPermissions(),
    getLocale(),
    getExtracted("settings"),
  ]);

  const canEdit = can(permissions, "settings.update");

  return (
    <div className="flex flex-col gap-6">
      <KpiBand
        kpis={[
          { label: t("Language"), value: locale.toUpperCase() },
          {
            label: t("Organization settings"),
            value: canEdit ? t("Editable") : t("Read only"),
            hint: t("Needs the settings.update permission."),
          },
        ]}
      />
      <SettingsLayout canEditOrganization={canEdit} />
    </div>
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
