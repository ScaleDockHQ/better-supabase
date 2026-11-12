import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  ShiftDetail,
  ShiftDetailSkeleton,
} from "@/features/shifts/components/shift-detail";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the shift streams in.
export const instant = true;

export default function ShiftPage({
  params,
  searchParams,
}: PageProps<"/[locale]/shifts/[id]">) {
  const t = useExtracted("shifts");

  return (
    <>
      <Link
        href="/shifts"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All shifts")}
      </Link>
      <Suspense fallback={<ShiftDetailSkeleton />}>
        <ShiftDetail params={params} searchParams={searchParams} />
      </Suspense>
    </>
  );
}
