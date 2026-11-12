import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AnnouncementList,
  AnnouncementListSkeleton,
} from "@/features/announcements/components/announcement-list";

export const instant = true;

export default function AnnouncementsPage() {
  const t = useExtracted("announcements");

  return (
    <>
      <PageHeader
        title={t("Announcements")}
        description={t(
          "Notices for your organization: product news, maintenance windows and changes that need your attention.",
        )}
      />
      <Suspense fallback={<AnnouncementListSkeleton />}>
        <AnnouncementList />
      </Suspense>
    </>
  );
}
