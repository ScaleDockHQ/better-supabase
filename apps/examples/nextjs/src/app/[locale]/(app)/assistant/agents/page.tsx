import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { loadOpsList } from "@/components/ops-list/ops-list-params";
import { PageHeader } from "@/components/page-header";
import {
  AgentList,
  AgentListSkeleton,
} from "@/features/agents/components/agent-list";
import { PlaybookWizard } from "@/features/agents/components/playbook-wizard";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch holds the header and the skeleton; the rows read the URL state.
export const ensureStatic = "prefetch";
export const instant = true;

export default function AgentsPage({
  searchParams,
}: PageProps<"/[locale]/assistant/agents">) {
  const t = useExtracted("agents");

  return (
    <>
      <PageHeader
        title={t("Agents")}
        description={t(
          "Assistants with their own instructions, tools and knowledge. Start from a playbook, then publish one to the store.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="agents.write">
              <PlaybookWizard />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<AgentListSkeleton />}>
        <PermissionGate permission="agents.read">
          <AgentList query={loadOpsList(searchParams)} />
        </PermissionGate>
      </Suspense>
    </>
  );
}
