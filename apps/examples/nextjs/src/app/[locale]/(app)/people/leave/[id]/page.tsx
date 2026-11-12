import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  LeaveDetail,
  LeaveDetailSkeleton,
} from "@/features/leave/components/leave-detail";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the request streams in.
export const instant = true;

export default function LeaveRequestPage({
  params,
}: PageProps<"/[locale]/people/leave/[id]">) {
  const t = useExtracted("people");

  return (
    <>
      <Link
        href="/people/leave"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All leave")}
      </Link>
      <Suspense fallback={<LeaveDetailSkeleton />}>
        {params.then(({ id }) => (
          <LeaveDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
