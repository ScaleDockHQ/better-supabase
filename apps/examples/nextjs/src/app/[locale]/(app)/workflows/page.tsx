import { LayoutTemplateIcon, WaypointsIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { buttonVariants } from "@/components/ui/button";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { CreateDefinitionForm } from "@/features/workflows/builder/components/create-definition-form";
import {
  DefinitionList,
  DefinitionListSkeleton,
} from "@/features/workflows/builder/components/definition-list";
import { Link } from "@/i18n/navigation";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// A navigation here paints the header and the list skeleton at once
// (tests/loading-sequences.spec.ts).
export const instant = true;

export default function WorkflowsPage() {
  const t = useExtracted("workflows");

  return (
    <>
      <PageHeader
        title={t("Workflows")}
        description={t(
          "Workflows the organization draws on a canvas, published in versions and run on the Workflow SDK.",
        )}
        actions={
          <>
            <Link
              href="/workflows/templates"
              className={buttonVariants({ variant: "outline" })}
            >
              <LayoutTemplateIcon />
              {t("Templates")}
            </Link>
            <Link
              href="/workflows/runs"
              className={buttonVariants({ variant: "outline" })}
            >
              <WaypointsIcon />
              {t("Runs")}
            </Link>
            <Suspense fallback={null}>
              <PermissionGate permission="workflow_editor.write">
                <CreateDefinitionForm />
              </PermissionGate>
            </Suspense>
          </>
        }
      />
      <Suspense fallback={<DefinitionListSkeleton />}>
        <PermissionGate permission="workflow_editor.read">
          <DefinitionList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
