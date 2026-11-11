import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  QueueDetail,
  SalesDetailSkeleton,
} from "@/features/sales/components/crm-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the queue streams in.
export const instant = true;

export default function QueueDetailPage({
  params,
}: PageProps<"/[locale]/crm/queues/[id]">) {
  const t = useExtracted("sales");

  return (
    <>
      <Link
        href="/crm/queues"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All queues")}
      </Link>
      <Suspense fallback={<SalesDetailSkeleton />}>
        {params.then(({ id }) => (
          <QueueDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
