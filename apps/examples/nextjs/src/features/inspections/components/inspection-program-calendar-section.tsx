import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { InspectionProgramCalendar } from "@/features/inspections/components/inspection-program-calendar";
import { getInspectionCalendar } from "@/features/inspections/inspections-queries";

export async function InspectionProgramCalendarSection() {
  return <InspectionProgramCalendar state={await getInspectionCalendar()} />;
}

export function InspectionProgramCalendarSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-36" />
        <Skeleton className="h-4 w-80" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-48" />
      </FramePanel>
    </Frame>
  );
}
