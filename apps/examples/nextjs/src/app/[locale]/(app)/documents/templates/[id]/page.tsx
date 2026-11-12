import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  TemplateDetail,
  TemplateDetailSkeleton,
} from "@/features/document-templates/components/template-detail";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the template streams in.
export const instant = true;

export default function DocumentTemplatePage({
  params,
}: PageProps<"/[locale]/documents/templates/[id]">) {
  const t = useExtracted("documents");

  return (
    <>
      <Link
        href="/documents/templates"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All templates")}
      </Link>
      <Suspense fallback={<TemplateDetailSkeleton />}>
        {params.then(({ id }) => (
          <TemplateDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
