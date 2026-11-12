import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import { PermissionGate } from "@/features/user/components/permission-gate";
import {
  ClaimDetail,
  ClaimDetailSkeleton,
} from "@/features/warranty/components/claim-detail";
import { Link } from "@/i18n/navigation";

// A navigation shows the back link at once; the claim streams in.
export const instant = true;

export default function ClaimPage({
  params,
}: PageProps<"/[locale]/shop/warranty/[id]">) {
  const t = useExtracted("warranty");

  return (
    <>
      <Link
        href="/shop/warranty"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All claims")}
      </Link>
      <Suspense fallback={<ClaimDetailSkeleton />}>
        <PermissionGate permission="warranty.read">
          {params.then(({ id }) => (
            <ClaimDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
