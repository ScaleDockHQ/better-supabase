import { SquareKanbanIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import {
  KitchenDisplay,
  KitchenDisplaySkeleton,
} from "@/features/shop/components/kitchen-display";
import { Link } from "@/i18n/navigation";

export default function KitchenPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("shop");

  return (
    <>
      <PageHeader
        title={t("Kitchen")}
        description={t(
          "The open tickets at each station. Move a ticket along as it's prepared.",
        )}
        actions={
          <Link
            href="/shop/kitchen/board"
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            <SquareKanbanIcon />
            {t("Order board")}
          </Link>
        }
      />
      <Suspense fallback={<KitchenDisplaySkeleton />}>
        <KitchenDisplay searchParams={searchParams} />
      </Suspense>
    </>
  );
}
