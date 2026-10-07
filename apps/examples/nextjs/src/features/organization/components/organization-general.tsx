import { getExtracted } from "next-intl/server";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getOrganizationSettings } from "@/features/settings/settings-queries";
import {
  activeOrganizationId,
  can,
  roleOf,
} from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getMyOrganizations } from "../organization-queries";
import { LeaveOrganizationButton } from "./leave-organization-button";
import { OrganizationForm } from "./organization-form";
import { OrganizationSettingsForm } from "./organization-settings-form";

/** Render inside `<Suspense>`; the fallback is `OrganizationGeneralSkeleton`. */
export async function OrganizationGeneral() {
  const session = await getSession();
  const organizationId = activeOrganizationId(session);
  if (!organizationId) return null;
  const [organizations, settings, t] = await Promise.all([
    getMyOrganizations(),
    getOrganizationSettings(organizationId),
    getExtracted("organization"),
  ]);
  const organization = organizations.find(
    (entry) => entry.id === organizationId,
  );
  if (!organization) return null;
  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>{t("General")}</CardTitle>
          <CardDescription>
            {t("Managed by the organizations module.")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <OrganizationForm
            name={organization.name}
            slug={organization.slug}
            canEdit={can(session, "organization.update")}
          />
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>{t("Defaults")}</CardTitle>
        </CardHeader>
        <CardContent>
          <OrganizationSettingsForm
            defaultRole={settings.defaultRole}
            weekStart={settings.weekStart}
            canEdit={can(session, "settings.update")}
          />
        </CardContent>
      </Card>
      {roleOf(session) === "owner" ? null : (
        <Card>
          <CardHeader>
            <CardTitle>{t("Leave organization")}</CardTitle>
            <CardDescription>
              {t("Owners transfer ownership before they can leave.")}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <LeaveOrganizationButton name={organization.name} />
          </CardContent>
        </Card>
      )}
    </>
  );
}

export function OrganizationGeneralSkeleton() {
  return (
    <div className="space-y-6" aria-busy="true">
      <Skeleton className="h-72 rounded-xl" />
      <Skeleton className="h-56 rounded-xl" />
    </div>
  );
}
