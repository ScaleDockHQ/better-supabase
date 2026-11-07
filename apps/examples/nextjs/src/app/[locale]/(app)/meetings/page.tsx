import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MeetingAgendaSectionSkeleton,
  MeetingAgendaSection,
} from "@/features/meetings/components/meeting-agenda-section";
import {
  MeetingMinutesSectionSkeleton,
  MeetingMinutesSection,
} from "@/features/meetings/components/meeting-minutes-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

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
      <Suspense fallback={<MeetingAgendaSectionSkeleton />}>
        <PermissionGate permission="meetings.read">
          <MeetingAgendaSection />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<MeetingMinutesSectionSkeleton />}>
        <PermissionGate permission="meetings.read">
          {searchParams.then((query) => (
            <MeetingMinutesSection query={query} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
