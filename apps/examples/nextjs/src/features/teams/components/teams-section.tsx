import { GroupIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getTeams } from "../teams-queries";
import { CreateTeamDialog } from "./team-dialogs";
import { TeamsGrid } from "./teams-grid";

/** Render inside `<Suspense>`; the fallback is `TeamsSectionSkeleton`. */
export async function TeamsSection() {
  const [teams, permissions, t] = await Promise.all([
    getTeams(),
    getPermissions(),
    getExtracted("teams"),
  ]);

  const canManage = can(permissions, "teams.manage");
  const active = teams.filter((team) => team.status === "active").length;

  return (
    <Frame spacing="sm">
      <FrameHeader className="flex-row items-center justify-between gap-3">
        <div className="flex flex-col gap-0.5">
          <FrameTitle>{t("Teams")}</FrameTitle>
          <FrameDescription>
            {t("{count, plural, one {# active team} other {# active teams}}", {
              count: active,
            })}
          </FrameDescription>
        </div>
        {canManage ? <CreateTeamDialog /> : null}
      </FrameHeader>
      <FramePanel>
        {teams.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <GroupIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No teams yet")}</EmptyTitle>
              <EmptyDescription>
                {t("Group members into teams so they can own customers.")}
              </EmptyDescription>
            </EmptyHeader>
            {canManage ? (
              <EmptyContent>
                <CreateTeamDialog />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <TeamsGrid
            teams={teams.map((team) => ({
              id: team.id,
              name: team.name,
              description: team.description,
              status: team.status,
              memberCount: team.memberIds.length,
            }))}
          />
        )}
      </FramePanel>
    </Frame>
  );
}

export function TeamsSectionSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="gap-1">
        <Skeleton className="h-4 w-20" />
        <Skeleton className="h-4 w-32" />
      </FrameHeader>
      <FramePanel className="flex flex-col gap-3">
        <Skeleton className="h-8 w-72" />
        <Skeleton className="h-48" />
      </FramePanel>
    </Frame>
  );
}
