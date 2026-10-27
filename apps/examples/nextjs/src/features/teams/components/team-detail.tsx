import { tenantOf } from "better-supabase/next";
import { getExtracted } from "next-intl/server";
import { notFound } from "next/navigation";

import { Badge } from "@/components/reui/badge";
import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { CustomerStatus } from "@/features/customers/components/customer-status";
import { getMembers } from "@/features/organization/organization-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { Link } from "@/i18n/navigation";

import { getTeam, getTeamCustomers } from "../teams-queries";
import { EditTeamDialog } from "./team-dialogs";
import { TeamMembers } from "./team-members";
import { TeamStatusActions } from "./team-status-actions";

/**
 * Render inside `<Suspense>`: one team with its members and the customers it
 * owns. The members come from the teams block, the customers from an app view
 * over the app's own table. A team of another organization is a 404.
 */
export async function TeamDetail({
  params,
}: {
  params: Promise<{ teamId: string }>;
}) {
  const [{ teamId }, session, permissions] = await Promise.all([
    params,
    getSession(),
    getPermissions(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [team, members, customers, t] = await Promise.all([
    getTeam(teamId),
    getMembers(organizationId),
    getTeamCustomers(teamId),
    getExtracted("teams"),
  ]);

  if (!team) {
    notFound();
  }

  const canManage = can(permissions, "teams.manage");
  const archived = team.status === "archived";

  return (
    <div className="flex flex-col gap-6" data-testid="team-detail">
      <Frame spacing="sm">
        <FrameHeader className="flex-row flex-wrap items-center justify-between gap-3">
          <div className="flex min-w-0 flex-col gap-0.5">
            <div className="flex items-center gap-2">
              <FrameTitle className="truncate">{team.name}</FrameTitle>
              {archived ? (
                <Badge variant="secondary">{t("Archived")}</Badge>
              ) : null}
            </div>
            <FrameDescription>
              {team.description ?? t("No description")}
            </FrameDescription>
          </div>
          {canManage ? (
            <div className="flex items-center gap-2">
              <EditTeamDialog
                id={team.id}
                name={team.name}
                description={team.description}
              />
              <TeamStatusActions
                id={team.id}
                name={team.name}
                archived={archived}
              />
            </div>
          ) : null}
        </FrameHeader>
        <FramePanel>
          <TeamMembers
            teamId={team.id}
            memberIds={team.memberIds}
            people={members.map((member) => ({
              userId: member.userId,
              name: member.name,
              email: member.email,
              avatarUrl: member.avatarUrl,
            }))}
            canManage={canManage && !archived}
          />
        </FramePanel>
      </Frame>
      <Frame spacing="sm">
        <FrameHeader>
          <FrameTitle>{t("Owned customers")}</FrameTitle>
          <FrameDescription>
            {t(
              "{count, plural, =0 {No customers} one {# customer} other {# customers}} name this team as their owner",
              { count: customers.length },
            )}
          </FrameDescription>
        </FrameHeader>
        <FramePanel>
          {customers.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyTitle>{t("No owned customers")}</EmptyTitle>
                <EmptyDescription>
                  {t("Set a customer's owner team on its page.")}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          ) : (
            <ul className="flex flex-col divide-y" data-testid="team-customers">
              {customers.map((customer) => (
                <li
                  key={customer.id}
                  className="flex items-center justify-between gap-3 py-2"
                >
                  <Link
                    href={`/customers/${customer.id}`}
                    prefetch
                    className="truncate text-sm font-medium hover:underline"
                  >
                    {customer.name}
                  </Link>
                  <CustomerStatus status={customer.status} />
                </li>
              ))}
            </ul>
          )}
        </FramePanel>
      </Frame>
    </div>
  );
}

export function TeamDetailSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Frame spacing="sm">
        <FrameHeader className="gap-1">
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-4 w-56" />
        </FrameHeader>
        <FramePanel>
          <Skeleton className="h-32" />
        </FramePanel>
      </Frame>
      <Frame spacing="sm">
        <FrameHeader>
          <Skeleton className="h-4 w-40" />
        </FrameHeader>
        <FramePanel>
          <Skeleton className="h-20" />
        </FramePanel>
      </Frame>
    </div>
  );
}
