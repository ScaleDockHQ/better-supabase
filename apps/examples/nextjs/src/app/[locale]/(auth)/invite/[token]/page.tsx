import { Suspense } from "react";

import {
  InvitationCard,
  InvitationCardSkeleton,
} from "@/features/organization/components/invitation-card";

export default function InvitePage({
  params,
}: PageProps<"/[locale]/invite/[token]">) {
  return (
    <Suspense fallback={<InvitationCardSkeleton />}>
      {params.then(({ token }) => (
        <InvitationCard token={token} />
      ))}
    </Suspense>
  );
}
