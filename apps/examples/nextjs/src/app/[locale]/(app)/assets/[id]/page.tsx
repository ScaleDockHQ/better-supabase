import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { AfterNavigation } from "@/components/record-detail/after-navigation";
import { buttonVariants } from "@/components/ui/button";
import {
  AssetDetail,
  AssetDetailSkeleton,
  AssetHistory,
  AssetHistorySkeleton,
} from "@/features/assets/components/asset-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation shows the back link and the head at once; the history waits
// for `navigation()`.
export const instant = true;

export default function AssetPage({
  params,
}: PageProps<"/[locale]/assets/[id]">) {
  const t = useExtracted("assets");

  return (
    <>
      <Link
        href="/assets"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All assets")}
      </Link>
      <Suspense fallback={<AssetDetailSkeleton />}>
        <PermissionGate permission="assets.read">
          {params.then(({ id }) => (
            <AssetDetail
              id={id}
              history={
                <Suspense fallback={<AssetHistorySkeleton />}>
                  <AfterNavigation>
                    <AssetHistory id={id} />
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
