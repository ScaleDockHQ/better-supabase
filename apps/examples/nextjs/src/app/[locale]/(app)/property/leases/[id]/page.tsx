import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { AfterNavigation } from "@/components/record-detail/after-navigation";
import { buttonVariants } from "@/components/ui/button";
import {
  LeaseDetail,
  LeaseDetailSkeleton,
  LeaseCharges,
  LeaseChargesSkeleton,
} from "@/features/leases/components/lease-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation shows the back link and the head at once; the rent periods wait
// for `navigation()`.
export const instant = true;

export default function LeasePage({
  params,
}: PageProps<"/[locale]/property/leases/[id]">) {
  const t = useExtracted("leases");

  return (
    <>
      <Link
        href="/property/leases"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All leases")}
      </Link>
      <Suspense fallback={<LeaseDetailSkeleton />}>
        <PermissionGate permission="leases.read">
          {params.then(({ id }) => (
            <LeaseDetail
              id={id}
              history={
                <Suspense fallback={<LeaseChargesSkeleton />}>
                  <AfterNavigation>
                    <LeaseCharges id={id} />
                  </AfterNavigation>
                </Suspense>
              }
            />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
