import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { CreateDefinitionForm } from "@/features/workflows/builder/components/create-definition-form";
import {
  DefinitionList,
  DefinitionListSkeleton,
} from "@/features/workflows/builder/components/definition-list";

export const instant = true;

export default function WorkflowBuilderPage() {
  const t = useExtracted("workflows");
  return (
    <>
      <PageHeader
        title={t("Workflow builder")}
        description={t(
          "Workflows the organization draws on a canvas, published in versions and run on the Workflow SDK.",
        )}
        actions={<CreateDefinitionForm />}
      />
      <Suspense fallback={<DefinitionListSkeleton />}>
        <DefinitionList />
      </Suspense>
    </>
  );
}
