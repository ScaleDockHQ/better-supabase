import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { AdminBackLink } from "@/features/admin-lists/admin-detail-page";
import {
  SecurityEventDetail,
  SecurityEventDetailSkeleton,
} from "@/features/security-events/components/security-event-detail";

// A navigation here shows the back link at once; the stream streams in.
export const instant = true;

export default function SecurityEventPage({
  params,
}: PageProps<"/[locale]/settings/security/events/[id]">) {
  const t = useExtracted("securityEvents");

  return (
    <>
      <AdminBackLink href="/settings/security/events">
        {t("All streams")}
      </AdminBackLink>
      <Suspense fallback={<SecurityEventDetailSkeleton />}>
        {params.then(({ id }) => (
          <SecurityEventDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
