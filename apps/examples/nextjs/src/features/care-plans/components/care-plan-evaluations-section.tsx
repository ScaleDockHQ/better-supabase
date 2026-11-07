import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { getCarePlan } from "@/features/care-plans/care-plans-queries";
import { CarePlanEvaluations } from "@/features/care-plans/components/care-plan-evaluations";

export async function CarePlanEvaluationsSection() {
  return <CarePlanEvaluations state={await getCarePlan()} />;
}

export function CarePlanEvaluationsSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-28" />
        <Skeleton className="h-4 w-80" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-40" />
      </FramePanel>
    </Frame>
  );
}
