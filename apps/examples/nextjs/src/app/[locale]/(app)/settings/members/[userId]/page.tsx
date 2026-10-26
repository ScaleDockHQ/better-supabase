import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  MemberDetail,
  MemberDetailSkeleton,
} from "@/features/members/components/member-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

/** The back link is the static shell; the member streams in. */
export default function MemberPage({
  params,
}: PageProps<"/[locale]/settings/members/[userId]">) {
  const t = useExtracted("members");

  return (
    <div className="flex flex-col gap-4">
      <Link
        href="/settings/members"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All members")}
      </Link>
      <Suspense fallback={<MemberDetailSkeleton />}>
        <PermissionGate permission="members.read">
          <MemberDetail params={params} />
        </PermissionGate>
      </Suspense>
    </div>
  );
}
