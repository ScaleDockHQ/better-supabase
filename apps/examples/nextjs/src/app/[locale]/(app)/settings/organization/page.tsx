import { Suspense } from "react";

import {
  OrganizationGeneral,
  OrganizationGeneralSkeleton,
} from "@/features/organization/components/organization-general";

export const instant = true;

export default function OrganizationSettingsPage() {
  return (
    <Suspense fallback={<OrganizationGeneralSkeleton />}>
      <OrganizationGeneral />
    </Suspense>
  );
}
