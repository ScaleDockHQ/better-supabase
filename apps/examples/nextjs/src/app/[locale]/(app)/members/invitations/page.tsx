import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  InvitationsOverview,
  InvitationsOverviewSkeleton,
} from "@/features/organization/components/invitations-overview";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/instant-routes.spec.ts).
export const instant = true;

export default function InvitationsPage() {
  const t = useExtracted("organization");

  return (
    <>
      <PageHeader
        title={t("Invitations")}
        description={t(
          "The invitations that are still open, and when they expire.",
        )}
      />
      <Suspense fallback={<InvitationsOverviewSkeleton />}>
        <InvitationsOverview />
      </Suspense>
    </>
  );
}
