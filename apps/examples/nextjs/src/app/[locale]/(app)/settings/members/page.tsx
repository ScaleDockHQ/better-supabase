import { Suspense } from "react";

import {
  MembersSectionSkeleton,
  MembersSection,
} from "@/features/members/components/members-section";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function MembersSettingsPage() {
  return (
    <Suspense fallback={<MembersSectionSkeleton />}>
      <MembersSection />
    </Suspense>
  );
}
