import { Suspense } from "react";

import {
  TeamsSectionSkeleton,
  TeamsSection,
} from "@/features/teams/components/teams-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function TeamsSettingsPage() {
  return (
    <Suspense fallback={<TeamsSectionSkeleton />}>
      <PermissionGate permission="teams.read">
        <TeamsSection />
      </PermissionGate>
    </Suspense>
  );
}
