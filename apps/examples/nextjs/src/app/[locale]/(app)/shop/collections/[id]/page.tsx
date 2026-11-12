import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  CollectionDetail,
  CollectionDetailSkeleton,
} from "@/features/collections/components/collection-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation shows the back link at once; the collection streams in.
export const instant = true;

export default function CollectionPage({
  params,
}: PageProps<"/[locale]/shop/collections/[id]">) {
  const t = useExtracted("collections");

  return (
    <>
      <Link
        href="/shop/collections"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All collections")}
      </Link>
      <Suspense fallback={<CollectionDetailSkeleton />}>
        <PermissionGate permission="collections.read">
          {params.then(({ id }) => (
            <CollectionDetail id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
