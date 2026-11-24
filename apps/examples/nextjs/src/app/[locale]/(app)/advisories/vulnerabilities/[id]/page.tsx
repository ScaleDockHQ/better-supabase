import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  VulnerabilityDetail,
  VulnerabilityDetailSkeleton,
} from "@/features/advisories/components/vulnerability-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the vulnerability streams in.
export const instant = true;

export default function VulnerabilityPage({
  params,
  searchParams,
}: PageProps<"/[locale]/advisories/vulnerabilities/[id]">) {
  const t = useExtracted("advisories");

  return (
    <>
      <Link
        href="/advisories/vulnerabilities"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All vulnerabilities")}
      </Link>
      <Suspense fallback={<VulnerabilityDetailSkeleton />}>
        <PermissionGate permission="advisories.read">
          {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
            <VulnerabilityDetail
              id={id}
              tab={activeTab(raw, ["overview", "activity", "related"])}
            />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
