import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  ModerationDetail,
  ModerationDetailSkeleton,
} from "@/features/moderation/components/moderation-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function ModerationItemPage({
  params,
}: PageProps<"/[locale]/moderation/[type]/[id]">) {
  const t = useExtracted("moderation");

  return (
    <>
      <Link
        href="/moderation"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("Back to the queue")}
      </Link>
      <Suspense fallback={<ModerationDetailSkeleton />}>
        <PermissionGate permission="moderation.read">
          {params.then(({ type, id }) => (
            <ModerationDetail type={type} id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
