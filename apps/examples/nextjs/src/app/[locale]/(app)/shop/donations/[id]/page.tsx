import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  GiftDetail,
  GiftDetailSkeleton,
} from "@/features/donations/components/gift-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation shows the back link at once; the gift streams in.
export const instant = true;

export default function GiftPage({
  params,
}: PageProps<"/[locale]/shop/donations/[id]">) {
  const t = useExtracted("donations");

  return (
    <>
      <Link
        href="/shop/donations"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All gifts")}
      </Link>
      <Suspense fallback={<GiftDetailSkeleton />}>
        <PermissionGate permission="donations.read">
          {params.then(({ id }) => (
            <GiftDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
