import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  TechnicianDay,
  TechnicianDaySkeleton,
} from "@/features/field/components/technician-day";

export default function MyDayPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("field");

  return (
    <>
      <PageHeader
        title={t("My day")}
        description={t("Your stops for the day and the next step of each.")}
      />
      <Suspense fallback={<TechnicianDaySkeleton />}>
        <TechnicianDay searchParams={searchParams} />
      </Suspense>
    </>
  );
}
