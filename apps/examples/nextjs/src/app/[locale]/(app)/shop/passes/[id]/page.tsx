import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { AfterNavigation } from "@/components/record-detail/after-navigation";
import { buttonVariants } from "@/components/ui/button";
import {
  PassDetail,
  PassDetailSkeleton,
  PassCheckIns,
  PassCheckInsSkeleton,
} from "@/features/passes/components/pass-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation shows the back link and the head at once; the check-ins wait
// for `navigation()`.
export const instant = true;

export default function PassPage({
  params,
}: PageProps<"/[locale]/shop/passes/[id]">) {
  const t = useExtracted("passes");

  return (
    <>
      <Link
        href="/shop/passes"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All passes")}
      </Link>
      <Suspense fallback={<PassDetailSkeleton />}>
        <PermissionGate permission="passes.read">
          {params.then(({ id }) => (
            <PassDetail
              id={id}
              history={
                <Suspense fallback={<PassCheckInsSkeleton />}>
                  <AfterNavigation>
                    <PassCheckIns id={id} />
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
