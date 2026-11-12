import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  MetricDetail,
  MetricDetailSkeleton,
} from "@/features/metrics/components/metric-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function MetricPage({
  params,
}: PageProps<"/[locale]/metrics/[key]">) {
  const t = useExtracted("metrics");

  return (
    <>
      <Link
        href="/metrics"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All metrics")}
      </Link>
      <Suspense fallback={<MetricDetailSkeleton />}>
        <PermissionGate permission="metrics.read">
          {params.then(({ key }) => (
            <MetricDetail metricKey={key} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
