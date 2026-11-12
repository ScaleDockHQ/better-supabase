import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  AnnouncementDetail,
  AnnouncementDetailSkeleton,
} from "@/features/announcements/components/announcement-detail";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function AnnouncementPage({
  params,
}: PageProps<"/[locale]/announcements/[id]">) {
  const t = useExtracted("announcements");

  return (
    <>
      <Link
        href="/announcements"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All announcements")}
      </Link>
      <Suspense fallback={<AnnouncementDetailSkeleton />}>
        {params.then(({ id }) => (
          <AnnouncementDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
