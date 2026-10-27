import { Suspense } from "react";

import {
  RolesSection,
  RolesSectionSkeleton,
} from "@/features/roles/components/roles-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

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
