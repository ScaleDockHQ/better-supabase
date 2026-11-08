import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  CustomerDetail,
  CustomerDetailSkeleton,
} from "@/features/customers/components/customer-detail";
import { ConnectivityFallback } from "@/features/offline/components/connectivity-fallback";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link and the customer head at once; the
// side sections wait for `navigation()` (tests/loading-sequences.spec.ts).
export const instant = true;

/** The back link is the static shell; the customer streams in. */
export default function CustomerPage({
  params,
}: PageProps<"/[locale]/customers/[id]">) {
  const t = useExtracted("customers");

  return (
    <>
      <Link
        href="/customers"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All customers")}
      </Link>
      <Suspense
        fallback={
          <ConnectivityFallback>
            <CustomerDetailSkeleton />
          </ConnectivityFallback>
        }
      >
        {params.then(({ id }) => (
          <CustomerDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
