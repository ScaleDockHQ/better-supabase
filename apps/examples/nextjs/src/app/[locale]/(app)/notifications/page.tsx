import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { NotificationActions } from "@/features/notifications/components/notification-actions";
import {
  NotificationHistory,
  NotificationHistorySkeleton,
} from "@/features/notifications/components/notification-history";
import { UnreadSummary } from "@/features/notifications/components/unread-badge";
import { loadNotificationFilters } from "@/features/notifications/notifications-search-params";

export default function NotificationsPage({
  searchParams,
}: PageProps<"/[locale]/notifications">) {
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
      <div data-recipe="notification-list">
        <Suspense fallback={<NotificationHistorySkeleton />}>
          <NotificationHistory
            filters={searchParams.then(loadNotificationFilters)}
          />
        </Suspense>
      </div>
    </>
  );
}
