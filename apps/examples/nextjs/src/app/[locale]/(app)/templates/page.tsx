import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  TemplateManagerActions,
  TemplatesGallery,
  TemplatesGallerySkeleton,
} from "@/features/templates/components/templates-gallery";
import { PermissionGate } from "@/features/user/components/permission-gate";

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
