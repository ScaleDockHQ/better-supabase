import { Suspense } from "react";

import {
  WebhookEndpoints,
  WebhookEndpointsSkeleton,
} from "@/features/webhooks/components/webhook-endpoints";

export default function WebhooksSettingsPage() {
  return (
    <Suspense fallback={<WebhookEndpointsSkeleton />}>
      <WebhookEndpoints />
    </Suspense>
  );
}
