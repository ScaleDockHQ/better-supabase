import { Suspense } from "react";

import {
  RolesSectionSkeleton,
  RolesSection,
} from "@/features/roles/components/roles-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function RolesSettingsPage() {
  return (
    <Suspense fallback={<RolesSectionSkeleton />}>
      <PermissionGate permission="members.read">
        <RolesSection />
      </PermissionGate>
    </Suspense>
  );
}
