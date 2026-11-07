import { io } from "next/cache";
import * as v from "valibot";

import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import {
  MeetingMinutes,
  MeetingMinutesPicker,
} from "@/features/meetings/components/meeting-minutes";
import { getMeetingMinutes } from "@/features/meetings/meetings-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

const MeetingParam = v.pipe(v.string(), v.uuid());

export async function MeetingMinutesSection({
  query,
}: {
  query: Record<string, string | string[] | undefined>;
}) {
  const [permissions] = await Promise.all([getPermissions(), io()]);

  const picked = v.safeParse(MeetingParam, query["meeting"]);

  if (!picked.success) {
    return <MeetingMinutesPicker />;
  }

  return (
    <MeetingMinutes
      state={await getMeetingMinutes(picked.output)}
      canRun={can(permissions, "meetings.write")}
    />
  );
}

export function MeetingMinutesSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-48" />
        <Skeleton className="h-4 w-32" />
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-32" />
      </FramePanel>
    </Frame>
  );
}
