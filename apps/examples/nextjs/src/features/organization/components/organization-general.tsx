import { tenantOf } from "better-supabase/next";
import { getExtracted } from "next-intl/server";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can, roleOf } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getMyOrganizations } from "../organization-queries";
import { LeaveOrganizationButton } from "./leave-organization-button";
import { OrganizationForm } from "./organization-form";

/** Render inside `<Suspense>`; the fallback is `OrganizationGeneralSkeleton`. */
export async function OrganizationGeneral() {
  const [session, permissions] = await Promise.all([
    getSession(),
    getPermissions(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [organizations, t] = await Promise.all([
    getMyOrganizations(),
    getExtracted("organization"),
  ]);

  const organization = organizations.find(
    (entry) => entry.id === organizationId,
  );

  if (!organization) {
    return null;
  }

  return (
    <>
      <Card data-recipe="workspace-url-field">
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
            canEdit={can(permissions, "organization.update")}
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
