import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  FrameworkDetail,
  FrameworkDetailSkeleton,
} from "@/features/compliance/components/framework-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function FrameworkPage({
  params,
}: PageProps<"/[locale]/compliance/[framework]">) {
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
      <Suspense fallback={<FrameworkDetailSkeleton />}>
        <PermissionGate permission="compliance.read">
          {params.then(({ framework }) => (
            <FrameworkDetail frameworkId={framework} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
