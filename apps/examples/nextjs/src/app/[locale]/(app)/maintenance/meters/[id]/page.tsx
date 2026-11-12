import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  MaintenanceDetailSkeleton,
  MeterDetail,
} from "@/features/maintenance/components/maintenance-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the meter streams in behind it.
export const instant = true;

export default function MaintenanceMeterPage({
  params,
}: PageProps<"/[locale]/maintenance/meters/[id]">) {
  const t = useExtracted("maintenance");

  return (
    <>
      <Link
        href="/maintenance?tab=meters"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All meters")}
      </Link>
      <Suspense fallback={<MaintenanceDetailSkeleton />}>
        {params.then(({ id }) => (
          <MeterDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
