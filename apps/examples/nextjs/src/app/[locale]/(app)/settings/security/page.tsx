import { Suspense } from "react";

import {
  IdentitiesCard,
  IdentitiesCardSkeleton,
} from "@/features/identities/components/identities-card";
import {
  SessionsCard,
  SessionsCardSkeleton,
} from "@/features/sessions/components/sessions-card";
import { DeleteAccountCard } from "@/features/user/components/delete-account-button";
import {
  SecurityCards,
  SecurityCardsSkeleton,
} from "@/features/user/components/security-cards";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function SecuritySettingsPage() {
  return (
    <>
      <Suspense fallback={<SecurityCardsSkeleton />}>
        <SecurityCards />
      </Suspense>
      <Suspense fallback={<IdentitiesCardSkeleton />}>
        <IdentitiesCard />
      </Suspense>
      <Suspense fallback={<SessionsCardSkeleton />}>
        <SessionsCard />
      </Suspense>
      <DeleteAccountCard />
    </>
  );
}
