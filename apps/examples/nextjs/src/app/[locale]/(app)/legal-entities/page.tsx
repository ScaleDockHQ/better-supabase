import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { FinanceOverviewPage } from "@/components/finance-pages/finance-pages";
import { PageHeader } from "@/components/page-header";
import {
  LegalEntityListSection,
  LegalEntityListSectionSkeleton,
} from "@/features/legal-entities/components/legal-entity-sections";
import { PermissionGate } from "@/features/user/components/permission-gate";

// instant: this overview keeps its own header and sections (the page reads
// the signed-in user's permissions), so it doesn't export `instant`; the
// list and detail pages beside it do.

export default function LegalEntitiesPage() {
  const t = useExtracted("legal-entities");

  return (
    <>
      <PageHeader
        title={t("Legal entities")}
        description={t(
          "The companies inside this organization, each with its own VAT number, currency and tax period.",
        )}
      />
      <Suspense fallback={<LegalEntityListSectionSkeleton />}>
        <PermissionGate permission="legal_entities.read">
          <LegalEntityListSection />
        </PermissionGate>
      </Suspense>
      <FinanceOverviewPage entity="legal-entities" embedded />
    </>
  );
}
