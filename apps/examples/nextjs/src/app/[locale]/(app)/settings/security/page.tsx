import { Suspense } from "react";

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
      <DeleteAccountCard />
    </>
  );
}
