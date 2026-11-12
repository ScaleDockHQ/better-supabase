import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ToolAccess,
  ToolAccessSkeleton,
} from "@/features/agents/components/tool-access";

export const ensureStatic = "prefetch";
export const instant = true;

export default function ToolAccessPage() {
  const t = useExtracted("agents");

  return (
    <>
      <PageHeader
        title={t("Tool access")}
        description={t(
          "What happens when the model calls a tool: run it, ask first or refuse. Rules apply to the whole organization.",
        )}
      />
      <Suspense fallback={<ToolAccessSkeleton />}>
        <ToolAccess />
      </Suspense>
    </>
  );
}
