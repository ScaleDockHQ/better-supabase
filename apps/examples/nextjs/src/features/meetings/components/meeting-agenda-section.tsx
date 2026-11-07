import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import { MeetingAgenda } from "@/features/meetings/components/meeting-agenda";
import { getMeetings } from "@/features/meetings/meetings-queries";

export async function MeetingAgendaSection() {
  return <MeetingAgenda state={await getMeetings()} />;
}

export function MeetingAgendaSectionSkeleton() {
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
