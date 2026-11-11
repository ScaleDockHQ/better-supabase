import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import { BuilderEditor } from "@/features/workflows/builder/components/builder-editor";
import { BuilderEditorSkeleton } from "@/features/workflows/builder/components/builder-editor-skeleton";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link and the editor frame at once; the
// canvas loads when the editor opens.
export const instant = true;

/** The back link is the static shell; the canvas loads with the definition. */
export default function WorkflowDefinitionPage({
  params,
}: PageProps<"/[locale]/workflows/builder/[definition]">) {
  const t = useExtracted("workflows");

  return (
    <>
      <Link
        href="/workflows"
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
        {params.then(({ definition }) => (
          <BuilderEditor definition={definition} />
        ))}
      </Suspense>
    </>
  );
}
