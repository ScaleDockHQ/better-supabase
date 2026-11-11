import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { loadOpsList } from "@/components/ops-list/ops-list-params";
import { PageHeader } from "@/components/page-header";
import {
  PromptList,
  PromptListSkeleton,
} from "@/features/prompts/components/prompt-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const ensureStatic = "prefetch";
export const instant = true;

export default function PromptsPage({
  searchParams,
}: PageProps<"/[locale]/assistant/prompts">) {
  const t = useExtracted("prompts");

  return (
    <>
      <PageHeader
        title={t("Prompts")}
        description={t(
          "Versioned instructions behind labels. The assistant reads assistant.system at its production label before every answer.",
        )}
      />
      <Suspense fallback={<PromptListSkeleton />}>
        <PermissionGate permission="ai_chat.manage">
          <PromptList query={loadOpsList(searchParams)} />
        </PermissionGate>
      </Suspense>
    </>
  );
}
