import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  TeamDetail,
  TeamDetailSkeleton,
} from "@/features/teams/components/team-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

/** The back link is the static shell; the team streams in. */
export default function TeamPage({
  params,
}: PageProps<"/[locale]/settings/teams/[teamId]">) {
  const t = useExtracted("teams");

  return (
    <div className="flex flex-col gap-4">
      <Link
        href="/settings/teams"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All teams")}
      </Link>
      <Suspense fallback={<TeamDetailSkeleton />}>
        <PermissionGate permission="teams.read">
          <TeamDetail params={params} />
        </PermissionGate>
      </Suspense>
    </div>
  );
}
