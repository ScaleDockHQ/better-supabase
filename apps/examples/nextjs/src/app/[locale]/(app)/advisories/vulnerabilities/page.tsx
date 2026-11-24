import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { buttonVariants } from "@/components/ui/button";
import { TrackVulnerabilityDialog } from "@/features/advisories/components/track-vulnerability-dialog";
import {
  VulnerabilityKpis,
  VulnerabilityKpisSkeleton,
  VulnerabilityOverview,
} from "@/features/advisories/components/vulnerability-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";
import { parseBlockList } from "@/lib/block-overview-query";

// A navigation here shows the header, the figure band and the list frame at
// once; the figures and the rows render on navigation.
export const instant = true;

export default function VulnerabilitiesPage({
  searchParams,
}: PageProps<"/[locale]/advisories/vulnerabilities">) {
  const t = useExtracted("advisories");

  return (
    <>
      <Link
        href="/advisories"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All advisories")}
      </Link>
      <PageHeader
        title={t("Vulnerabilities")}
        description={t(
          "Every vulnerability the organization tracks, with its severity, scores and whether it is exploited.",
        )}
        actions={
          <Suspense>
            <PermissionGate permission="advisories.write">
              <TrackVulnerabilityDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<VulnerabilityKpisSkeleton />}>
        <VulnerabilityKpis />
      </Suspense>
      <Suspense fallback={<RecordListSkeleton rows={4} />}>
        {searchParams.then((raw) => (
          <VulnerabilityOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
