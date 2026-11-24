import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  ApiKeyDetail,
  ApiKeyDetailSkeleton,
} from "@/features/api-keys/components/api-key-detail";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the key streams in.
export const instant = true;

export default function ApiKeyPage({
  params,
}: PageProps<"/[locale]/settings/api-keys/[id]">) {
  const t = useExtracted("apiKeys");

  return (
    <div className="flex flex-col gap-4">
      <Link
        href="/settings/api-keys"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All API keys")}
      </Link>
      <Suspense fallback={<ApiKeyDetailSkeleton />}>
        {params.then(({ id }) => (
          <ApiKeyDetail id={id} />
        ))}
      </Suspense>
    </div>
  );
}
