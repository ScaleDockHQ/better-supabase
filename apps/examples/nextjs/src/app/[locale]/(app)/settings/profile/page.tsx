import { Suspense } from "react";

import {
  ProfileDetails,
  ProfileDetailsSkeleton,
} from "@/features/user/components/profile-details";

export default function ProfileSettingsPage() {
  return (
    <Suspense fallback={<ProfileDetailsSkeleton />}>
      <ProfileDetails />
    </Suspense>
  );
}
