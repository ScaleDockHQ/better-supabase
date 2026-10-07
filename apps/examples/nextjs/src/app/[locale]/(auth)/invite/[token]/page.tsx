import { Suspense } from "react";

import {
  InvitationCard,
  InvitationCardSkeleton,
} from "@/features/organization/components/invitation-card";

export const instant = true;

export default function InvitePage({
  params,
}: PageProps<"/[locale]/invite/[token]">) {
  return (
    <Suspense fallback={<InvitationCardSkeleton />}>
      <InvitationCard params={params} />
    </Suspense>
  );
}
