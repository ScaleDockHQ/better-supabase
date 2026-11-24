import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  WebhookDetail,
  WebhookDetailSkeleton,
} from "@/features/webhooks/components/webhook-detail";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the endpoint streams in.
export const instant = true;

export default function WebhookPage({
  params,
}: PageProps<"/[locale]/settings/webhooks/[id]">) {
  const t = useExtracted("webhooks");

  return (
    <div className="flex flex-col gap-4">
      <Link
        href="/settings/webhooks"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All webhooks")}
      </Link>
      <Suspense fallback={<WebhookDetailSkeleton />}>
        {params.then(({ id }) => (
          <WebhookDetail id={id} />
        ))}
      </Suspense>
    </div>
  );
}
