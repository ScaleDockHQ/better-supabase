import { Suspense } from "react";

import {
  WebhookEndpoints,
  WebhookEndpointsSkeleton,
} from "@/features/webhooks/components/webhook-endpoints";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function WebhooksSettingsPage() {
  return (
    <Suspense fallback={<WebhookEndpointsSkeleton />}>
      <WebhookEndpoints />
    </Suspense>
  );
}
