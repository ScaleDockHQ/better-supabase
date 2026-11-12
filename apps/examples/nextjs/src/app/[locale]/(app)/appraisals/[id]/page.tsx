import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  AppraisalDetail,
  AppraisalDetailSkeleton,
} from "@/features/appraisals/components/appraisal-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the appraisal streams in.
export const instant = true;

export default function AppraisalPage({
  params,
}: PageProps<"/[locale]/appraisals/[id]">) {
  const t = useExtracted("appraisals");

  return (
    <>
      <Link
        href="/appraisals"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All appraisals")}
      </Link>
      <Suspense fallback={<AppraisalDetailSkeleton />}>
        <PermissionGate permission="appraisals.review">
          {params.then(({ id }) => (
            <AppraisalDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
