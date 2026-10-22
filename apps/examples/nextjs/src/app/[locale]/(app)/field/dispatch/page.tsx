import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  DispatchBoard,
  DispatchBoardSkeleton,
} from "@/features/field/components/dispatch-board";

export const instant = true;

export default function DispatchPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("field");

  return (
    <>
      <PageHeader
        title={t("Dispatch")}
        description={t(
          "Schedule work orders into technicians' days and keep the backlog moving.",
        )}
      />
      <Suspense fallback={<DispatchBoardSkeleton />}>
        <DispatchBoard searchParams={searchParams} />
      </Suspense>
    </>
  );
}
