import { Suspense } from "react";

import {
  WebhookEndpoints,
  WebhookEndpointsSkeleton,
} from "@/features/webhooks/components/webhook-endpoints";
import {
  WebhooksKpiBand,
  WebhooksKpiBandSkeleton,
} from "@/features/webhooks/components/webhooks-kpi-band";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function WebhooksSettingsPage() {
  return (
    <>
      <Suspense fallback={<WebhooksKpiBandSkeleton />}>
        <WebhooksKpiBand />
      </Suspense>
      <Suspense fallback={<WebhookEndpointsSkeleton />}>
        <WebhookEndpoints />
      </Suspense>
    </>
  );
}
