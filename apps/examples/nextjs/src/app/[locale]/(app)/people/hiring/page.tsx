import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  HiringBoard,
  HiringBoardSkeleton,
} from "@/features/people/components/hiring-board";

export default function HiringPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("people");

  return (
    <>
      <PageHeader
        title={t("Hiring")}
        description={t("Openings and their candidates by interview stage.")}
      />
      <Suspense fallback={<HiringBoardSkeleton />}>
        <HiringBoard searchParams={searchParams} />
      </Suspense>
    </>
  );
}
