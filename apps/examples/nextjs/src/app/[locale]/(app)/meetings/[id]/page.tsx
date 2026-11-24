import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  MeetingDetail,
  MeetingMinutesSectionSkeleton,
} from "@/features/meetings/components/meeting-minutes-section";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function MeetingPage({
  params,
}: PageProps<"/[locale]/meetings/[id]">) {
  const t = useExtracted("meetings");

  return (
    <>
      <Link
        href="/meetings"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All meetings")}
      </Link>
      <Suspense fallback={<MeetingMinutesSectionSkeleton />}>
        <PermissionGate permission="meetings.read">
          {params.then(({ id }) => (
            <MeetingDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
