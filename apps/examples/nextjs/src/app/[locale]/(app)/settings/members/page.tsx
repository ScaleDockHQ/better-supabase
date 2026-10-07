import { Suspense } from "react";

import {
  MembersSection,
  MembersSectionSkeleton,
} from "@/features/organization/components/members-section";

export const instant = true;

export default function MembersSettingsPage() {
  return (
    <Suspense fallback={<MembersSectionSkeleton />}>
      <MembersSection />
    </Suspense>
  );
}
