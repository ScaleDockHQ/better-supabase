import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  RiskDetail,
  RiskDetailSkeleton,
} from "@/features/risks/components/risk-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the risk streams in behind it
// (tests/loading-sequences.spec.ts).
export const instant = true;

/** The back link is the static shell; the risk streams in. */
export default function RiskPage({
  params,
}: PageProps<"/[locale]/risks/[id]">) {
  const t = useExtracted("risks");

  return (
    <>
      <Link
        href="/risks"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All risks")}
      </Link>
      <Suspense fallback={<RiskDetailSkeleton />}>
        {params.then(({ id }) => (
          <PermissionGate permission="risks.read">
            <RiskDetail id={id} />
          </PermissionGate>
        ))}
      </Suspense>
    </>
  );
}
