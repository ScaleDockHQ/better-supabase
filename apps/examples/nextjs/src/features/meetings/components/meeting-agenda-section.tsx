import { MeetingAgenda } from "@/features/meetings/components/meeting-agenda";
import { getMeetings } from "@/features/meetings/meetings-queries";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function MeetingAgendaSection() {
  return <MeetingAgenda state={await getMeetings()} />;
}
