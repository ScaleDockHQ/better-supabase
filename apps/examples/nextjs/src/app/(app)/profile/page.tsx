import { Suspense } from 'react';

import { DeleteAccountButton } from '@/features/user/components/delete-account-button';
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
      <DeleteAccountButton />
    </>
  );
}
