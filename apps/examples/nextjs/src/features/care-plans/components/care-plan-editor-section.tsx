import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { getCarePlan } from "@/features/care-plans/care-plans-queries";
import { CarePlanEditor } from "@/features/care-plans/components/care-plan-editor";

export async function CarePlanEditorSection() {
  return <CarePlanEditor state={await getCarePlan()} />;
}

export function CarePlanEditorSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-40" />
        <Skeleton className="h-4 w-72" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-56" />
      </FramePanel>
    </Frame>
  );
}
