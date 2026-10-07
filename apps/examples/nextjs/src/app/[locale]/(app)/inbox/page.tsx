import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { InboxActions } from "@/features/inbox/components/inbox-actions";
import {
  NotificationList,
  NotificationListSkeleton,
} from "@/features/inbox/components/notification-list";
import { UnreadCount } from "@/features/inbox/components/unread-count";

export const instant = true;

export default function InboxPage() {
  const t = useExtracted("inbox");
  return (
    <>
      <PageHeader
        title={t("Inbox")}
        description={t(
          "Every signed-in user has one. The count stays live over Realtime.",
        )}
        actions={<InboxActions />}
      />
      <Suspense fallback={<Skeleton className="h-5 w-24" />}>
        <UnreadCount />
      </Suspense>
      <Suspense fallback={<NotificationListSkeleton />}>
        <NotificationList />
      </Suspense>
    </>
  );
}
