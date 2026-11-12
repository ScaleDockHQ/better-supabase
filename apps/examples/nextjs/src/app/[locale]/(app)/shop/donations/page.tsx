import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  GiftList,
  GiftListSkeleton,
} from "@/features/donations/components/gift-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function DonationsPage() {
  const t = useExtracted("donations");

  return (
    <>
      <PageHeader
        title={t("Donations")}
        description={t(
          "Gifts to your funds and campaigns, with their status and receipts.",
        )}
      />
      <Suspense fallback={<GiftListSkeleton />}>
        <PermissionGate permission="donations.read">
          <GiftList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
