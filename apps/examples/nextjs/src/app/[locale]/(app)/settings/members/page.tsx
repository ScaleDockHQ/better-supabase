import { Suspense } from "react";

import {
  MembersSection,
  MembersSectionSkeleton,
} from "@/features/members/components/members-section";

export default function MembersSettingsPage() {
  return (
    <Suspense fallback={<MembersSectionSkeleton />}>
      <MembersSection />
    </Suspense>
  );
}
