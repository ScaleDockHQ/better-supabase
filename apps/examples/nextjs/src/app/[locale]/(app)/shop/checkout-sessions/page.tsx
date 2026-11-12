import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  SessionList,
  SessionListSkeleton,
} from "@/features/checkout-sessions/components/session-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function CheckoutSessionsPage() {
  const t = useExtracted("checkoutSessions");

  return (
    <>
      <PageHeader
        title={t("Checkout sessions")}
        description={t("Purchases AI agents start on a cart, over ACP or UCP.")}
      />
      <Suspense fallback={<SessionListSkeleton />}>
        <PermissionGate permission="agent_checkout.read">
          <SessionList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
