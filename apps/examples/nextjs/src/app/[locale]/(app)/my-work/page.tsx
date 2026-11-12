import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MyReminders,
  MyRemindersSkeleton,
} from "@/features/my-work/components/my-reminders";
import {
  MyWorkList,
  MyWorkListSkeleton,
} from "@/features/my-work/components/my-work-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

export default function MyWorkPage() {
  const t = useExtracted("myWork");

  return (
    <>
      <PageHeader
        title={t("My work")}
        description={t("What waits on you in this organization.")}
      />
      <Suspense fallback={<MyWorkListSkeleton />}>
        <MyWorkList />
      </Suspense>
      <Suspense fallback={<MyRemindersSkeleton />}>
        <PermissionGate permission="reminders.manage">
          <MyReminders />
        </PermissionGate>
      </Suspense>
    </>
  );
}
