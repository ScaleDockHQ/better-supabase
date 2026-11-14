import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  RuleEditor,
  RuleEditorSkeleton,
} from "@/features/rules/components/rule-editor";
import { Link } from "@/i18n/navigation";

/** The back link is the static shell; the editor loads with the session. */
// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

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
      <Suspense fallback={<RuleEditorSkeleton />}>
        {params.then(({ rule }) => (
          <RuleEditor rule={rule} />
        ))}
      </Suspense>
    </>
  );
}
