import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import { SalesDetailSkeleton } from "@/features/sales/components/crm-details";
import { StatementDetail } from "@/features/sales/components/revenue-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the statement streams in.
export const instant = true;

export default function StatementPage({
  params,
}: PageProps<"/[locale]/crm/commissions/statements/[id]">) {
  const t = useExtracted("sales");

  return (
    <>
      <Link
        href="/crm/commissions?tab=statements"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All statements")}
      </Link>
      <Suspense fallback={<SalesDetailSkeleton />}>
        {params.then(({ id }) => (
          <StatementDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
