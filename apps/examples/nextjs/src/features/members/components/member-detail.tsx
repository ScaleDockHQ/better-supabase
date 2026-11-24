import { tenantOf } from "better-supabase/next";
import { getExtracted, getFormatter } from "next-intl/server";
import { notFound } from "next/navigation";

import { PropertiesRail } from "@/components/record-detail/properties-rail";
import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { KpiBand } from "@/components/record-list/kpi-band";
import { Frame, FrameHeader, FramePanel } from "@/components/reui/frame";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembers } from "@/features/organization/organization-queries";
import { getRoles } from "@/features/roles/roles-queries";
import { getTeams } from "@/features/teams/teams-queries";
import { RoleBadge } from "@/features/user/components/role-badge";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";
import { initials } from "@/lib/initials";

import { loadSeatsLeft } from "../seats/seats-queries";

/**
 * Render inside `<Suspense>`: one member of the active organization with their
 * role, join date and teams. A user outside the organization is a 404.
 */
export async function MemberDetail({ userId }: { userId: string }) {
  const [session, permissions] = await Promise.all([
    getSession(),
    getPermissions(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [members, roles, teams, t, format] = await Promise.all([
    getMembers(organizationId),
    getRoles(),
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

  const grants = [
    ...(roles?.find((role) => role.key === member.role)?.permissions ?? []),
  ].toSorted();

  const seatsLeft = await loadSeatsLeft(members.length);

  return (
    <div data-testid="member-detail">
      <RecordDetailFrame
        leading={
          <Avatar className="size-10">
            {member.avatarUrl ? (
              <AvatarImage src={member.avatarUrl} alt="" />
            ) : null}
            <AvatarFallback>
              {initials(member.name, member.email)}
            </AvatarFallback>
          </Avatar>
        }
        title={member.name ?? member.email ?? ""}
        description={member.email ?? undefined}
        status={<RoleBadge role={member.role} />}
        aside={
          <PropertiesRail
            title={t("Properties")}
            properties={[
              {
                label: t("Joined"),
                value: member.joinedAt
                  ? format.dateTime(new Date(member.joinedAt), {
                      dateStyle: "long",
                    })
                  : undefined,
              },
              { label: t("Teams"), value: String(memberTeams.length) },
              { label: t("Grants"), value: String(grants.length) },
            ]}
          />
        }
      >
        <KpiBand
          kpis={[
            {
              label: t("Seats used"),
              value: String(members.length),
              hint: t("Members of the organization, this one included."),
            },
            {
              label: t("Seats left"),
              value:
                seatsLeft === undefined || seatsLeft === null
                  ? t("No limit")
                  : String(seatsLeft),
            },
            { label: t("Teams"), value: String(memberTeams.length) },
            { label: t("Grants"), value: String(grants.length) },
          ]}
        />
        <Card>
          <CardHeader>
            <CardTitle>{t("Teams")}</CardTitle>
          </CardHeader>
          <CardContent>
            {memberTeams.length === 0 ? (
              <span className="text-sm text-muted-foreground">
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
          </CardContent>
        </Card>
        <Card data-testid="member-grants">
          <CardHeader>
            <CardTitle>{t("Grants")}</CardTitle>
            <CardDescription>
              {t("The permissions this member holds through the {role} role.", {
                role: member.role,
              })}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {grants.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                {t("This role grants no permissions.")}
              </p>
            ) : (
              <ul className="flex flex-wrap gap-1">
                {grants.map((grant) => (
                  <li key={grant}>
                    <Badge variant="outline" className="font-mono text-xs">
                      {grant}
                    </Badge>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </RecordDetailFrame>
    </div>
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
