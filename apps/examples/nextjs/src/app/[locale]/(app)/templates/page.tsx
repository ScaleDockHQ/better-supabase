import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  TemplateManagerActions,
  TemplatesGallery,
  TemplatesGallerySkeleton,
} from "@/features/templates/components/templates-gallery";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function TemplatesPage() {
  const t = useExtracted("templates");

  return (
    <>
      <PageHeader
        title={t("Templates")}
        description={t("Start new customers from a saved setup.")}
        actions={
          <Suspense fallback={null}>
            <TemplateManagerActions />
          </Suspense>
        }
      />
      <Suspense fallback={<TemplatesGallerySkeleton />}>
        <PermissionGate permission="templates.read">
          <TemplatesGallery />
        </PermissionGate>
      </Suspense>
    </>
  );
}
