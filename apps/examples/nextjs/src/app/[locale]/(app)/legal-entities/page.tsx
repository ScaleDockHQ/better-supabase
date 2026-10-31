import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  LegalEntityListSection,
  LegalEntityListSkeleton,
} from "@/features/legal-entities/components/legal-entity-sections";
import { PermissionGate } from "@/features/user/components/permission-gate";

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
      <Suspense fallback={<LegalEntityListSkeleton />}>
        <PermissionGate permission="legal_entities.read">
          <LegalEntityListSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
