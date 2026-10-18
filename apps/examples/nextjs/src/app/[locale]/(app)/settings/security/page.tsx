import { Suspense } from "react";

import {
  SessionsCard,
  SessionsCardSkeleton,
} from "@/features/sessions/components/sessions-card";
import { DeleteAccountCard } from "@/features/user/components/delete-account-button";
import {
  SecurityCards,
  SecurityCardsSkeleton,
} from "@/features/user/components/security-cards";

export const instant = true;

export default function SecuritySettingsPage() {
  return (
    <>
      <Suspense fallback={<SecurityCardsSkeleton />}>
        <SecurityCards />
      </Suspense>
      <Suspense fallback={<SessionsCardSkeleton />}>
        <SessionsCard />
      </Suspense>
      <DeleteAccountCard />
    </>
  );
}
