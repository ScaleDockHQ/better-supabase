import { tenantOf } from "better-supabase/next";
import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembers } from "@/features/organization/organization-queries";
import { getTeams } from "@/features/teams/teams-queries";
import { RoleBadge } from "@/features/user/components/role-badge";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";
import { initials } from "@/lib/initials";

/**
 * Render inside `<Suspense>`: one member of the active organization with their
 * role, join date and teams. A user outside the organization is a 404.
 */
export async function MemberDetail({
  params,
}: {
  params: Promise<{ userId: string }>;
}) {
  const [{ userId }, session, permissions] = await Promise.all([
    params,
    getSession(),
    getPermissions(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [members, teams, t, format] = await Promise.all([
    getMembers(organizationId),
    can(permissions, "teams.read") ? getTeams() : Promise.resolve([]),
    getExtracted("members"),
    getFormatter(),
  ]);

  const member = members.find((each) => each.userId === userId);

  if (!member) {
    notFound();
  }

  const memberTeams = teams.filter(
    (team) => team.status === "active" && team.memberIds.includes(userId),
  );

  return (
    <Frame spacing="sm" data-testid="member-detail">
      <FrameHeader className="flex-row items-center gap-3">
        <Avatar className="size-10">
          {member.avatarUrl ? (
            <AvatarImage src={member.avatarUrl} alt="" />
          ) : null}
          <AvatarFallback>{initials(member.name, member.email)}</AvatarFallback>
        </Avatar>
        <div className="flex min-w-0 flex-col gap-0.5">
          <FrameTitle className="truncate">
            {member.name ?? member.email}
          </FrameTitle>
          <FrameDescription className="truncate">
            {member.email}
          </FrameDescription>
        </div>
      </FrameHeader>
      <FramePanel>
        <dl className="grid gap-4 text-sm sm:grid-cols-[10rem_1fr]">
          <dt className="text-muted-foreground">{t("Role")}</dt>
          <dd>
            <RoleBadge role={member.role} />
          </dd>
          <dt className="text-muted-foreground">{t("Joined")}</dt>
          <dd className="tabular-nums">
            {member.joinedAt
              ? format.dateTime(new Date(member.joinedAt), {
                  dateStyle: "long",
                })
              : "–"}
          </dd>
          <dt className="text-muted-foreground">{t("Teams")}</dt>
          <dd>
            {memberTeams.length === 0 ? (
              <span className="text-muted-foreground">
                {t("Not on a team")}
              </span>
            ) : (
              <ul className="flex flex-wrap gap-1">
                {memberTeams.map((team) => (
                  <li key={team.id}>
                    <Badge
                      variant="outline"
                      render={
                        <Link href={`/settings/teams/${team.id}`} prefetch />
                      }
                    >
                      {team.name}
                    </Badge>
                  </li>
                ))}
              </ul>
            )}
          </dd>
        </dl>
      </FramePanel>
    </Frame>
  );
}

export function MemberDetailSkeleton() {
  return (
    <Frame spacing="sm" aria-busy="true">
      <FrameHeader className="flex-row items-center gap-3">
        <Skeleton className="size-10 rounded-full" />
        <div className="flex flex-col gap-1">
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-4 w-48" />
        </div>
      </FrameHeader>
      <FramePanel>
        <Skeleton className="h-24" />
      </FramePanel>
    </Frame>
  );
}
