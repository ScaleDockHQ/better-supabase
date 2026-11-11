import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  activeTab,
  RecordDetailTabs,
} from "@/components/record-detail/record-detail-tabs";
import { SalesListSkeleton } from "@/features/sales/components/crm-overviews";
import {
  CreateCodeDialog,
  ReferralOverview,
} from "@/features/sales/components/revenue-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

const TABS = ["referrals", "codes"] as const;

export default function ReferralsPage({
  searchParams,
}: PageProps<"/[locale]/crm/referrals">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Referrals")}
        description={t(
          "Referral codes your customers share, and what they bring in.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="referrals.write">
              <CreateCodeDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => {
          const tab = activeTab(raw, TABS);

          return (
            <>
              <RecordDetailTabs
                base="/crm/referrals"
                active={tab}
                tabs={[
                  { value: "referrals", label: t("Referrals") },
                  { value: "codes", label: t("Codes") },
                ]}
              />
              <ReferralOverview
                query={parseBlockList(raw)}
                tab={tab === "codes" ? "codes" : "referrals"}
              />
            </>
          );
        })}
      </Suspense>
    </>
  );
}
