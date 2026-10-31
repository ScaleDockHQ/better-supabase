import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";
import * as v from "valibot";

import { PageHeader } from "@/components/page-header";
import {
  MeetingAgenda,
  MeetingAgendaSkeleton,
} from "@/features/meetings/components/meeting-agenda";
import {
  MeetingMinutes,
  MeetingMinutesPicker,
  MeetingMinutesSkeleton,
} from "@/features/meetings/components/meeting-minutes";
import {
  getMeetingMinutes,
  getMeetings,
} from "@/features/meetings/meetings-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

const MeetingParam = v.pipe(v.string(), v.uuid());

async function Agenda() {
  return <MeetingAgenda state={await getMeetings()} />;
}

async function Minutes({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [query, permissions] = await Promise.all([
    searchParams,
    getPermissions(),
    connection(),
  ]);

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

export default function MeetingsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("meetings");

  return (
    <>
      <PageHeader
        title={t("Meetings")}
        description={t(
          "The organization's meetings, and the agenda, decisions and action items of the one you open.",
        )}
      />
      <Suspense fallback={<MeetingAgendaSkeleton />}>
        <PermissionGate permission="meetings.read">
          <Agenda />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<MeetingMinutesSkeleton />}>
        <PermissionGate permission="meetings.read">
          <Minutes searchParams={searchParams} />
        </PermissionGate>
      </Suspense>
    </>
  );
}
