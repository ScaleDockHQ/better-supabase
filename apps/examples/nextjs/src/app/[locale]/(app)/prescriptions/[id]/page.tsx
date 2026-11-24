import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  PrescriptionDetail,
  PrescriptionDetailSkeleton,
} from "@/features/e-prescribing/components/prescription-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the prescription streams in.
export const instant = true;

export default function PrescriptionPage({
  params,
}: PageProps<"/[locale]/prescriptions/[id]">) {
  const t = useExtracted("prescriptions");

  return (
    <>
      <Link
        href="/prescriptions"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All prescriptions")}
      </Link>
      <Suspense fallback={<PrescriptionDetailSkeleton />}>
        <PermissionGate permission="e_prescribing.read">
          {params.then(({ id }) => (
            <PrescriptionDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
