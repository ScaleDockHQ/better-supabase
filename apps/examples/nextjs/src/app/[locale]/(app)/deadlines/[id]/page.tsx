import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  DeadlineDetail,
  DeadlineDetailSkeleton,
} from "@/features/deadlines/components/deadline-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function DeadlinePage({
  params,
}: PageProps<"/[locale]/deadlines/[id]">) {
  const t = useExtracted("work");

  return (
    <>
      <Link
        href="/deadlines"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All deadlines")}
      </Link>
      <Suspense fallback={<DeadlineDetailSkeleton />}>
        <PermissionGate permission="deadlines.read">
          {params.then(({ id }) => (
            <DeadlineDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
