import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  RoleDetail,
  RoleDetailSkeleton,
} from "@/features/roles/components/role-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

/** The back link is the static shell; the role's matrix streams in. */
export default function RolePage({
  params,
}: PageProps<"/[locale]/settings/roles/[roleId]">) {
  const t = useExtracted("roles");

  return (
    <div className="flex flex-col gap-4">
      <Link
        href="/settings/roles"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All roles")}
      </Link>
      <Suspense fallback={<RoleDetailSkeleton />}>
        <PermissionGate permission="members.read">
          <RoleDetail params={params} />
        </PermissionGate>
      </Suspense>
    </div>
  );
}
