import { Suspense } from 'react';

import {
  AccountSection,
  AccountSectionSkeleton,
} from '../../../../features/account/components/account-section';

/** The page owns the boundary and hands the feature a plain section name. */
export default function AccountPage({
  params,
}: {
  params: Promise<{ section: string }>;
}) {
  return (
    <Suspense fallback={<AccountSectionSkeleton />}>
      {params.then(({ section }) => (
        <AccountSection section={section} />
      ))}
    </Suspense>
  );
}
