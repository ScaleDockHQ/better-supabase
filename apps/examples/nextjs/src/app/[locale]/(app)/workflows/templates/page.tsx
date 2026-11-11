import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { TemplateGallery } from "@/features/workflows/builder/components/template-gallery";
import { Link } from "@/i18n/navigation";

// The gallery is fixed content, so a navigation here paints it at once.
export const instant = true;

export default function WorkflowTemplatesPage() {
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
      <PageHeader
        title={t("Workflow templates")}
        description={t(
          "Start from a graph that already runs. Each template becomes a draft you can change.",
        )}
      />
      <Suspense fallback={null}>
        <PermissionGate permission="workflow_editor.write">
          <TemplateGallery />
        </PermissionGate>
      </Suspense>
    </>
  );
}
