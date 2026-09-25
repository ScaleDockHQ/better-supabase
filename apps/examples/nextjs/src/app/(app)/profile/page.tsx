import { Suspense } from 'react';

import {
  ProfileDetails,
  ProfileDetailsSkeleton,
} from '@/features/user/components/profile-details';

export const instant = true;

export default function ProfilePage() {
  return (
    <>
      <h1>Profile</h1>
      <Suspense fallback={<ProfileDetailsSkeleton />}>
        <ProfileDetails />
      </Suspense>
    </>
  );
}
