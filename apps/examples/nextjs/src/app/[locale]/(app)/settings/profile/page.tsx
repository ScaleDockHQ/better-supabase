import { Suspense } from "react";

import {
  ProfileDetails,
  ProfileDetailsSkeleton,
} from "@/features/user/components/profile-details";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ProfileSettingsPage() {
  return (
    <Suspense fallback={<ProfileDetailsSkeleton />}>
      <ProfileDetails />
    </Suspense>
  );
}
