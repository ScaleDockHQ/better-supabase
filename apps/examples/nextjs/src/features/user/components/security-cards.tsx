import { Skeleton } from "@/components/ui/skeleton";

import { getOAuthGrants, getTotpFactorId } from "../security-queries";
import { ConnectedAgentsCard } from "./connected-agents-card";
import { TwoFactorCard } from "./two-factor-card";

/** Render inside `<Suspense>`; the fallback is `SecurityCardsSkeleton`. */
export async function SecurityCards() {
  const [factor, grants] = await Promise.all([
    getTotpFactorId(),
    getOAuthGrants(),
  ]);
  return (
    <>
      <TwoFactorCard initial={factor} />
      <ConnectedAgentsCard initial={grants} />
    </>
  );
}

export function SecurityCardsSkeleton() {
  return (
    <div className="space-y-6" aria-busy="true">
      <Skeleton className="h-36 rounded-xl" />
      <Skeleton className="h-36 rounded-xl" />
    </div>
  );
}
