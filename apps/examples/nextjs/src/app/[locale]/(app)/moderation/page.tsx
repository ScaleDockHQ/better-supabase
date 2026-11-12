import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ModerationQueue,
  ModerationQueueSkeleton,
} from "@/features/moderation/components/moderation-queue";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function ModerationPage() {
  const t = useExtracted("moderation");

  return (
    <>
      <PageHeader
        title={t("Moderation")}
        description={t(
          "Reported and pending content from reviews, comments and posts, and the members who are banned.",
        )}
      />
      <Suspense fallback={<ModerationQueueSkeleton />}>
        <PermissionGate permission="moderation.read">
          <ModerationQueue />
        </PermissionGate>
      </Suspense>
    </>
  );
}
