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
  // oxlint-disable-next-line react-doctor/nextjs-async-dynamic-api-not-awaited -- mapped with then and passed on unawaited, so the page renders without waiting for the request.
  const id = params.then((value) => value.id);
  // oxlint-disable-next-line react-doctor/nextjs-async-dynamic-api-not-awaited -- mapped with then and passed on unawaited, so the page renders without waiting for the request.
  const on = searchParams.then((query) => query["on"]);

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
        <ShiftDetail id={id} on={on} />
      </Suspense>
    </>
  );
}
