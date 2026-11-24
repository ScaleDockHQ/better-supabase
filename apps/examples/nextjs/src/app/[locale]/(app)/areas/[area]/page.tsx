import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { KpiBandSkeleton } from "@/components/record-list/kpi-band";
import { buttonVariants } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { AREA_IDS, AREAS } from "@/features/areas/areas";
import { AreaFlow, AreaKpis } from "@/features/areas/components/area-hub";
import { Link } from "@/i18n/navigation";

// The thirteen hubs are known at build time, so the header is static.
export function generateStaticParams(): { area: string }[] {
  return AREA_IDS.map((area) => ({ area }));
}

// A navigation here shows the header and the frames at once; the figures
// stream in (tests/sales-flow.spec.ts).
export const instant = true;

export default function AreaPage({
  params,
}: PageProps<"/[locale]/areas/[area]">) {
  const t = useExtracted("areas");

  return (
    <>
      <Link
        href="/areas"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All areas")}
      </Link>
      <Suspense fallback={<Skeleton className="h-16 rounded-xl" />}>
        {params.then(({ area: id }) => {
          const area = AREAS.find((candidate) => candidate.id === id);

          if (!area) {
            notFound();
          }

          return (
            <>
              <PageHeader title={area.name} description={area.flow} />
              <Suspense fallback={<KpiBandSkeleton />}>
                <AreaKpis id={id} />
              </Suspense>
              <Suspense fallback={<Skeleton className="h-40 rounded-xl" />}>
                <AreaFlow id={id} />
              </Suspense>
            </>
          );
        })}
      </Suspense>
    </>
  );
}
