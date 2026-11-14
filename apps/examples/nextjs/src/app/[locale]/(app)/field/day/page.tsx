import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  TechnicianDay,
  TechnicianDaySkeleton,
} from "@/features/field/components/technician-day";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

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
        {searchParams.then((query) => (
          <TechnicianDay query={query} />
        ))}
      </Suspense>
    </>
  );
}
