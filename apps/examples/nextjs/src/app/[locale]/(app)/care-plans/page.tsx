import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { getCarePlan } from "@/features/care-plans/care-plans-queries";
import {
  CarePlanEditor,
  CarePlanEditorSkeleton,
} from "@/features/care-plans/components/care-plan-editor";
import {
  CarePlanEvaluations,
  CarePlanEvaluationsSkeleton,
} from "@/features/care-plans/components/care-plan-evaluations";
import { PermissionGate } from "@/features/user/components/permission-gate";

async function Editor() {
  return <CarePlanEditor state={await getCarePlan()} />;
}

async function Evaluations() {
  return <CarePlanEvaluations state={await getCarePlan()} />;
}

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
      <Suspense fallback={<CarePlanEditorSkeleton />}>
        <PermissionGate permission="care_plans.read">
          <Editor />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<CarePlanEvaluationsSkeleton />}>
        <PermissionGate permission="care_plans.read">
          <Evaluations />
        </PermissionGate>
      </Suspense>
    </>
  );
}
