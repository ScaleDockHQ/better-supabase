import { Suspense } from "react";

import {
  AccessRequestsInbox,
  AccessRequestsInboxSkeleton,
} from "@/features/access-requests/components/access-requests-inbox";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function AccessRequestsSettingsPage() {
  return (
    <Suspense fallback={<AccessRequestsInboxSkeleton />}>
      <AccessRequestsInbox />
    </Suspense>
  );
}
