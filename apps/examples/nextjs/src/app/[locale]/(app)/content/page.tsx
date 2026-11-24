import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import {
  ContentKpis,
  ContentKpisSkeleton,
  ContentOverview,
} from "@/features/content/components/content-overview";
import { CreateEntryDialog } from "@/features/content/components/create-entry-dialog";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/block-overview-query";

// A navigation here shows the header, the figure band and the list frame at
// once; the figures and the rows render on navigation.
export const instant = true;

export default function ContentPage({
  searchParams,
}: PageProps<"/[locale]/content">) {
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
      <Suspense fallback={<ContentKpisSkeleton />}>
        <ContentKpis />
      </Suspense>
      <Suspense fallback={<RecordListSkeleton rows={4} />}>
        {searchParams.then((raw) => (
          <ContentOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
