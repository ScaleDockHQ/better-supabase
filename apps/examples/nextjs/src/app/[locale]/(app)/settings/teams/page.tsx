import { Suspense } from "react";

import {
  TeamsSectionSkeleton,
  TeamsSection,
} from "@/features/teams/components/teams-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function TeamsSettingsPage() {
  return (
    <Suspense fallback={<TeamsSectionSkeleton />}>
      <PermissionGate permission="teams.read">
        <TeamsSection />
      </PermissionGate>
    </Suspense>
  );
}
