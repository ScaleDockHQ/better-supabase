import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getAgent } from "../agents-queries";
import { AgentEditor } from "./agent-editor";
import { AgentPublish } from "./agent-publish";

/** Render inside `<Suspense>`: reads the `id` param and the agent. */
export async function AgentDetail({ id }: { id: string }) {
  const [agent, permissions, t] = await Promise.all([
    getAgent(id),
    getPermissions(),
    getExtracted("agents"),
  ]);

  if (agent === undefined) {
    notFound();
  }

  const canWrite = can(permissions, "agents.write");
  const canPublish = can(permissions, "agents.publish");

  return (
    <RecordDetailFrame
      title={agent.name}
      description={agent.description === "" ? agent.slug : agent.description}
      status={
        <Badge
          variant={
            agent.visibility === "private" ? "secondary" : "success-light"
          }
        >
          {agent.visibility}
        </Badge>
      }
      aside={
        <>
          <Card size="sm">
            <CardHeader>
              <CardTitle>{t("Overview")}</CardTitle>
              <CardDescription>{t("How the agent is used.")}</CardDescription>
            </CardHeader>
            <CardContent>
              <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
                <dt className="text-muted-foreground">{t("Installs")}</dt>
                <dd className="tabular-nums">{agent.installs}</dd>
                <dt className="text-muted-foreground">{t("Rating")}</dt>
                <dd className="tabular-nums">
                  {agent.rating === undefined ? "–" : agent.rating.toFixed(1)}
                </dd>
                <dt className="text-muted-foreground">{t("Skills")}</dt>
                <dd className="tabular-nums">{agent.skills}</dd>
                <dt className="text-muted-foreground">{t("Connectors")}</dt>
                <dd className="tabular-nums">{agent.connectors}</dd>
                <dt className="text-muted-foreground">{t("Knowledge")}</dt>
                <dd>
                  {agent.knowledgeScopes.length === 0
                    ? "–"
                    : agent.knowledgeScopes.join(", ")}
                </dd>
              </dl>
            </CardContent>
          </Card>
          <AgentPublish
            id={agent.id}
            visibility={agent.visibility}
            installed={agent.installed}
            canPublish={canPublish}
            canWrite={canWrite}
          />
        </>
      }
    >
      <AgentEditor agent={agent} canWrite={canWrite} />
    </RecordDetailFrame>
  );
}

export function AgentDetailSkeleton() {
  return (
    <div className="grid items-start gap-6 lg:grid-cols-3" aria-busy="true">
      <div className="flex flex-col gap-4 lg:col-span-2">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-64 w-full" />
      </div>
      <Skeleton className="h-48 w-full" />
    </div>
  );
}
