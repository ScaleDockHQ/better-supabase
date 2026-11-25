import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  ControlDetail,
  ControlDetailSkeleton,
} from "@/features/compliance/components/control-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function ControlPage({
  params,
}: PageProps<"/[locale]/compliance/controls/[id]">) {
  const t = useExtracted("compliance");

  return (
    <>
      <Link
        href="/compliance"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All frameworks")}
      </Link>
      <Suspense fallback={<ControlDetailSkeleton />}>
        <PermissionGate permission="compliance.read">
          {params.then(({ id }) => (
            <ControlDetail controlId={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
