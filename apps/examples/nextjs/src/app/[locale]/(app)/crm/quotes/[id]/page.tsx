import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  QuoteBuilder,
  QuoteBuilderSkeleton,
} from "@/features/crm/components/quote-builder";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the quote streams in.
export const instant = true;

/** The back link is the static shell; the quote streams in. */
export default function QuotePage({
  params,
}: PageProps<"/[locale]/crm/quotes/[id]">) {
  const t = useExtracted("crm");

  return (
    <>
      <Link
        href="/crm/quotes"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All quotes")}
      </Link>
      <Suspense fallback={<QuoteBuilderSkeleton />}>
        {params.then(({ id }) => (
          <QuoteBuilder id={id} />
        ))}
      </Suspense>
    </>
  );
}
