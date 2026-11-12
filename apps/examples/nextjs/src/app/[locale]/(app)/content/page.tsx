import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ContentList,
  ContentListSkeleton,
} from "@/features/content/components/content-list";
import { CreateEntryDialog } from "@/features/content/components/create-entry-dialog";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function ContentPage() {
  const t = useExtracted("content");

  return (
    <>
      <PageHeader
        title={t("Content")}
        description={t(
          "Pages and posts with locales and scheduled publishing. Only published entries reach the public site.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="content.write">
              <CreateEntryDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<ContentListSkeleton />}>
        <PermissionGate permission="content.read">
          <ContentList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
