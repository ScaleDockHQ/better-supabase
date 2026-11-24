import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";

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
