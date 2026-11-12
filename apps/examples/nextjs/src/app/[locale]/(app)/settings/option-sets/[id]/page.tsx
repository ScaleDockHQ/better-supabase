import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  OptionSetDetail,
  OptionSetDetailSkeleton,
} from "@/features/option-sets/components/option-set-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the option set streams in.
export const instant = true;

export default function OptionSetPage({
  params,
}: PageProps<"/[locale]/settings/option-sets/[id]">) {
  const t = useExtracted("optionSets");

  return (
    <>
      <Link
        href="/settings/option-sets"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All option sets")}
      </Link>
      <Suspense fallback={<OptionSetDetailSkeleton />}>
        {params.then(({ id }) => (
          <OptionSetDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
