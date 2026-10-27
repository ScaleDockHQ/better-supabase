import { tenantOf } from "better-supabase/next";

import { Skeleton } from "@/components/ui/skeleton";
import { getSession } from "@/features/user/user-queries";

import { getMyOrganizations } from "../organization-queries";

/** Render inside `<Suspense>`; the fallback is `ActiveOrganizationNameSkeleton`. */
export async function ActiveOrganizationName() {
  const [session, organizations] = await Promise.all([
    getSession(),
    getMyOrganizations(),
  ]);

  const tenant = tenantOf(session);

  const name = organizations.find(
    (organization) => organization.id === tenant,
  )?.name;

  return name ? (
    <span className="truncate" data-testid="header-organization">
      {name}
    </span>
  ) : null;
}

export function ActiveOrganizationNameSkeleton() {
  return <Skeleton className="h-4 w-24" />;
}
