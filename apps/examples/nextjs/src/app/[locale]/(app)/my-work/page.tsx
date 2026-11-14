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

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

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
