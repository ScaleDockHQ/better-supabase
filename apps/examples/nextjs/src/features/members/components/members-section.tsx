import { tenantOf } from "better-supabase/next";
import { getExtracted } from "next-intl/server";

import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { Skeleton } from "@/components/ui/skeleton";
import {
  getInvitations,
  getMembers,
} from "@/features/organization/organization-queries";
import { assignableRoles, getRoles } from "@/features/roles/roles-queries";
import { getTeams } from "@/features/teams/teams-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can, roleOf } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { InvitationList } from "./invitation-list";
import { InviteMemberDialog } from "./invite-member-dialog";
import { MemberTable } from "./member-table";

/** Render inside `<Suspense>`; the fallback is `MembersSectionSkeleton`. */
export async function MembersSection() {
  const [session, permissions] = await Promise.all([
    getSession(),
    getPermissions(),
  ]);

  const organizationId = tenantOf(session);
  const role = roleOf(session);

  if (!organizationId || !role || session.kind !== "user") {
    return null;
  }

  const canInvite = can(permissions, "members.invite");

  const [members, invitations, roles, teams, t] = await Promise.all([
    getMembers(organizationId),
    canInvite ? getInvitations(organizationId) : Promise.resolve([]),
    getRoles(),
    can(permissions, "teams.read") ? getTeams() : Promise.resolve([]),
    getExtracted("members"),
  ]);

  const assignable = assignableRoles(roles ?? [], permissions);

  return (
    <div className="flex flex-col gap-6">
      <Frame spacing="sm" data-recipe="members-table">
        <FrameHeader className="flex-row items-center justify-between gap-3">
          <div className="flex flex-col gap-0.5">
            <FrameTitle>{t("Members")}</FrameTitle>
            <FrameDescription>
              {t("{count, number} people in this organization", {
                count: members.length,
              })}
            </FrameDescription>
          </div>
          {canInvite ? (
            <InviteMemberDialog
              organizationId={organizationId}
              assignable={assignable}
            />
          ) : null}
        </FrameHeader>
        <FramePanel>
          <MemberTable
            organizationId={organizationId}
            initial={members}
            teams={teams.filter((team) => team.status === "active")}
            currentUserId={session.user.id}
            assignable={assignable}
            canUpdateRole={can(permissions, "members.update_role")}
            canRemove={can(permissions, "members.remove")}
          />
        </FramePanel>
      </Frame>
      {canInvite ? (
        <Frame spacing="sm">
          <FrameHeader>
            <FrameTitle>{t("Pending invitations")}</FrameTitle>
            <FrameDescription>
              {t(
                "There is no mailer in this example: copy the link and send it yourself.",
              )}
            </FrameDescription>
          </FrameHeader>
          <FramePanel>
            <InvitationList invitations={invitations} />
          </FramePanel>
        </Frame>
      ) : null}
    </div>
  );
}

export function MembersSectionSkeleton() {
  return (
    <div className="flex flex-col gap-6" aria-busy="true">
      <Frame spacing="sm">
        <FrameHeader className="gap-1">
          <Skeleton className="h-4 w-24" />
          <Skeleton className="h-4 w-48" />
        </FrameHeader>
        <FramePanel className="flex flex-col gap-3">
          <Skeleton className="h-8 w-72" />
          <Skeleton className="h-64" />
        </FramePanel>
      </Frame>
    </div>
  );
}
