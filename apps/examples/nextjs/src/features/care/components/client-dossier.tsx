import { getExtracted } from "next-intl/server";
import { Suspense } from "react";

import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { getCarePlan } from "@/features/care-plans/care-plans-queries";
import {
  CarePlanEditor,
  CarePlanEditorSkeleton,
} from "@/features/care-plans/components/care-plan-editor";
import {
  CarePlanEvaluations,
  CarePlanEvaluationsSkeleton,
} from "@/features/care-plans/components/care-plan-evaluations";
import {
  ActivityTimeline,
  ActivityTimelineSkeleton,
} from "@/features/crm/components/activity-timeline";
import {
  MedicationChart,
  MedicationChartSkeleton,
} from "@/features/medications/components/medication-chart";
import {
  ObservationChart,
  ObservationChartSkeleton,
} from "@/features/observations/components/observation-chart";
import { PermissionGate } from "@/features/user/components/permission-gate";

import {
  CareSectionSkeleton,
  ClientAccessLog,
  ClientConsents,
  ClientHeading,
  ClientHeadingSkeleton,
} from "./care-sections";

async function PlanEditor({ clientId }: { clientId: string }) {
  return <CarePlanEditor state={await getCarePlan(clientId)} />;
}

async function PlanEvaluations({ clientId }: { clientId: string }) {
  return <CarePlanEvaluations state={await getCarePlan(clientId)} />;
}

/**
 * Render inside `<Suspense>`: the client's name over one tab per part of the
 * dossier. Every tab streams in on its own and checks its own permission.
 */
export async function ClientDossier({
  params,
}: {
  params: Promise<{ clientId: string }>;
}) {
  const [{ clientId }, t] = await Promise.all([params, getExtracted("care")]);

  return (
    <div className="flex flex-col gap-6">
      <Suspense fallback={<ClientHeadingSkeleton />}>
        <ClientHeading clientId={clientId} />
      </Suspense>
      <Tabs defaultValue="notes" className="gap-4">
        <div className="overflow-x-auto">
          <TabsList>
            <TabsTrigger value="notes">{t("Notes")}</TabsTrigger>
            <TabsTrigger value="plan">{t("Care plan")}</TabsTrigger>
            <TabsTrigger value="observations">{t("Observations")}</TabsTrigger>
            <TabsTrigger value="medication">{t("Medication")}</TabsTrigger>
            <TabsTrigger value="consents">{t("Consents")}</TabsTrigger>
            <TabsTrigger value="access">{t("Access log")}</TabsTrigger>
          </TabsList>
        </div>
        <TabsContent value="notes">
          <Suspense fallback={<ActivityTimelineSkeleton />}>
            <ActivityTimeline subject={{ type: "customer", id: clientId }} />
          </Suspense>
        </TabsContent>
        <TabsContent value="plan" className="flex flex-col gap-6">
          <Suspense fallback={<CarePlanEditorSkeleton />}>
            <PermissionGate permission="care_plans.read">
              <PlanEditor clientId={clientId} />
            </PermissionGate>
          </Suspense>
          <Suspense fallback={<CarePlanEvaluationsSkeleton />}>
            <PermissionGate permission="care_plans.read">
              <PlanEvaluations clientId={clientId} />
            </PermissionGate>
          </Suspense>
        </TabsContent>
        <TabsContent value="observations">
          <Suspense fallback={<ObservationChartSkeleton />}>
            <PermissionGate permission="observations.read">
              <ObservationChart clientId={clientId} />
            </PermissionGate>
          </Suspense>
        </TabsContent>
        <TabsContent value="medication">
          <Suspense fallback={<MedicationChartSkeleton />}>
            <PermissionGate permission="medications.read">
              <MedicationChart clientId={clientId} />
            </PermissionGate>
          </Suspense>
        </TabsContent>
        <TabsContent value="consents">
          <Suspense fallback={<CareSectionSkeleton />}>
            <PermissionGate permission="consents.read">
              <ClientConsents clientId={clientId} />
            </PermissionGate>
          </Suspense>
        </TabsContent>
        <TabsContent value="access">
          <Suspense fallback={<CareSectionSkeleton />}>
            <PermissionGate permission="audit.read">
              <ClientAccessLog clientId={clientId} />
            </PermissionGate>
          </Suspense>
        </TabsContent>
      </Tabs>
    </div>
  );
}
