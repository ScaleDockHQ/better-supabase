import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import { RuleBuilderSkeleton } from "@/features/rules/components/rule-builder";
import { RuleEditor } from "@/features/rules/components/rule-editor";
import { Link } from "@/i18n/navigation";

export const instant = true;

/** The back link is the static shell; the editor loads with the session. */
export default function RulePage({
  params,
}: PageProps<"/[locale]/rules/[rule]">) {
  const t = useExtracted("rules");

  return (
    <>
      <Link
        href="/rules"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All rules")}
      </Link>
      <Suspense fallback={<RuleBuilderSkeleton />}>
        <RuleEditor params={params} />
      </Suspense>
    </>
  );
}
