import { Suspense } from "react";

import {
  FeatureFlagList,
  FeatureFlagListSkeleton,
} from "@/features/flags/components/feature-flag-list";
import {
  OrganizationGeneral,
  OrganizationGeneralSkeleton,
} from "@/features/organization/components/organization-general";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function OrganizationSettingsPage() {
  return (
    <>
      <Suspense fallback={<OrganizationGeneralSkeleton />}>
        <OrganizationGeneral />
      </Suspense>
      <Suspense fallback={<FeatureFlagListSkeleton />}>
        <FeatureFlagList />
      </Suspense>
    </>
  );
}
