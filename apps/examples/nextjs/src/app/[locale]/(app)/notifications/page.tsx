import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { NotificationActions } from "@/features/notifications/components/notification-actions";
import {
  NotificationList,
  NotificationListSkeleton,
} from "@/features/notifications/components/notification-list";
import { UnreadSummary } from "@/features/notifications/components/unread-badge";

export const instant = true;

export default function NotificationsPage() {
  const t = useExtracted("notifications");
  return (
    <>
      <PageHeader
        title={t("Notifications")}
        description={t(
          "Sent by the notifications block. The count stays live over Realtime.",
        )}
        actions={<NotificationActions />}
      />
      <UnreadSummary />
      <Suspense fallback={<NotificationListSkeleton />}>
        <NotificationList />
      </Suspense>
    </>
  );
}
