import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  TemplateOverview,
  TemplateOverviewSkeleton,
} from "@/features/document-templates/components/template-overview";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work.
export const instant = true;

export default function DocumentTemplatesPage() {
  const t = useExtracted("documents");

  return (
    <>
      <PageHeader
        title={t("Document templates")}
        description={t(
          "The layout of invoices, quotes and other documents, per language.",
        )}
      />
      <Suspense fallback={<TemplateOverviewSkeleton />}>
        <TemplateOverview />
      </Suspense>
    </>
  );
}
