import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CarePlanEditorSectionSkeleton,
  CarePlanEditorSection,
} from "@/features/care-plans/components/care-plan-editor-section";
import {
  CarePlanEvaluationsSectionSkeleton,
  CarePlanEvaluationsSection,
} from "@/features/care-plans/components/care-plan-evaluations-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function CarePlansPage() {
  const t = useExtracted("care-plans");

  return (
    <>
      <PageHeader
        title={t("Care plans")}
        description={t(
          "A client's problems, goals and actions in the active plan, and what each goal evaluation found.",
        )}
      />
      <Suspense fallback={<CarePlanEditorSectionSkeleton />}>
        <PermissionGate permission="care_plans.read">
          <CarePlanEditorSection />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<CarePlanEvaluationsSectionSkeleton />}>
        <PermissionGate permission="care_plans.read">
          <CarePlanEvaluationsSection />
        </PermissionGate>
      </Suspense>
    </>
  );
}
