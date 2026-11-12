import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  ReviewDetail,
  ReviewDetailSkeleton,
} from "@/features/reviews/components/review-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation shows the back link at once; the review streams in.
export const instant = true;

export default function ReviewPage({
  params,
}: PageProps<"/[locale]/shop/reviews/[id]">) {
  const t = useExtracted("reviews");

  return (
    <>
      <Link
        href="/shop/reviews"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All reviews")}
      </Link>
      <Suspense fallback={<ReviewDetailSkeleton />}>
        <PermissionGate permission="reviews.manage">
          {params.then(({ id }) => (
            <ReviewDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
