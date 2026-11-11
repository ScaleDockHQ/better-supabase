import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import { SalesDetailSkeleton } from "@/features/sales/components/crm-details";
import { ContractDetail } from "@/features/sales/components/revenue-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the contract streams in.
export const instant = true;

export default function ContractDetailPage({
  params,
}: PageProps<"/[locale]/crm/contracts/[id]">) {
  const t = useExtracted("sales");

  return (
    <>
      <Link
        href="/crm/contracts"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All contracts")}
      </Link>
      <Suspense fallback={<SalesDetailSkeleton />}>
        {params.then(({ id }) => (
          <ContractDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
