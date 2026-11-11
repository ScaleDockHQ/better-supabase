import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getAgentPage } from "../agents-queries";
import { AgentTable } from "./agent-table";

/** Render inside `<Suspense>`: the filtered page of agents for the URL's state. */
export async function AgentList({ query }: { query: Promise<OpsListQuery> }) {
  const [page, permissions] = await Promise.all([
    query.then(getAgentPage),
    getPermissions(),
  ]);

  return (
    <AgentTable
      items={page.items}
      nextCursor={page.nextCursor}
      canWrite={can(permissions, "agents.write")}
    />
  );
}

export function AgentListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
