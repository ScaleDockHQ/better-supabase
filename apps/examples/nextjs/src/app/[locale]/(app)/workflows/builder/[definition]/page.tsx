import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  BuilderEditor,
  BuilderEditorSkeleton,
} from "@/features/workflows/builder/components/builder-editor";
import { Link } from "@/i18n/navigation";

export const instant = true;

/** The back link is the static shell; the canvas loads with the definition. */
export default function WorkflowDefinitionPage({
  params,
}: PageProps<"/[locale]/workflows/builder/[definition]">) {
  const t = useExtracted("workflows");
  return (
    <>
      <Link
        href="/workflows/builder"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All workflows")}
      </Link>
      <Suspense fallback={<BuilderEditorSkeleton />}>
        <BuilderEditor params={params} />
      </Suspense>
    </>
  );
}
