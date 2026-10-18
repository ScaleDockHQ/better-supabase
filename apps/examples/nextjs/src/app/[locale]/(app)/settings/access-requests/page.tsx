import { Suspense } from "react";

import {
  AccessRequestsInbox,
  AccessRequestsInboxSkeleton,
} from "@/features/access-requests/components/access-requests-inbox";

export const instant = true;

export default function AccessRequestsSettingsPage() {
  return (
    <Suspense fallback={<AccessRequestsInboxSkeleton />}>
      <AccessRequestsInbox />
    </Suspense>
  );
}
