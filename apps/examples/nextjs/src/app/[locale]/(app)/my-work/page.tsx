import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MyWorkList,
  MyWorkListSkeleton,
} from "@/features/my-work/components/my-work-list";

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
    </>
  );
}
