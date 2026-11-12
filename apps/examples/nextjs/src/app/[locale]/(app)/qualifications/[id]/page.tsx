import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  QualificationTypeDetail,
  QualificationTypeDetailSkeleton,
} from "@/features/qualifications/components/qualification-type-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the type streams in.
export const instant = true;

export default function QualificationTypePage({
  params,
}: PageProps<"/[locale]/qualifications/[id]">) {
  const t = useExtracted("qualifications");

  return (
    <>
      <Link
        href="/qualifications"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All qualifications")}
      </Link>
      <Suspense fallback={<QualificationTypeDetailSkeleton />}>
        <PermissionGate permission="qualifications.read">
          {params.then(({ id }) => (
            <QualificationTypeDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
