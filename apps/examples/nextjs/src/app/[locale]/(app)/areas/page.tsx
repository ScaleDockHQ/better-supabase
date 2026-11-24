import { useExtracted } from "next-intl";

import { PageHeader } from "@/components/page-header";
import { AreaCards } from "@/features/areas/components/area-cards";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function AreasPage() {
  const t = useExtracted("areas");

  return (
    <>
      <PageHeader
        title={t("Product areas")}
        description={t(
          "Thirteen products in one app. Each row is the flow its presets prove together.",
        )}
      />
      <AreaCards />
    </>
  );
}
