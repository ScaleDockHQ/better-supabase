import { io } from "next/cache";
import * as v from "valibot";

import {
  MeetingMinutes,
  MeetingMinutesPicker,
} from "@/features/meetings/components/meeting-minutes";
import { getMeetingMinutes } from "@/features/meetings/meetings-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

const MeetingParam = v.pipe(v.string(), v.uuid());

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
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
