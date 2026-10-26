import { tenantOf } from "better-supabase/next";
import { getExtracted } from "next-intl/server";

import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { assignableRoles, getRoles } from "@/features/roles/roles-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can, roleOf } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getInvitations, getMembers } from "../organization-queries";
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

  const [members, invitations, roles, t] = await Promise.all([
    getMembers(organizationId),
    canInvite ? getInvitations(organizationId) : Promise.resolve([]),
    getRoles(),
    getExtracted("organization"),
  ]);

  const assignable = assignableRoles(roles ?? [], permissions);

  return (
    <>
      <Card data-recipe="members-table">
        <CardHeader>
          <CardTitle>{t("Members")}</CardTitle>
          <CardDescription>
            {t("{count, number} people in this organization", {
              count: members.length,
            })}
          </CardDescription>
          {canInvite ? (
            <CardAction>
              <InviteMemberDialog
                organizationId={organizationId}
                assignable={assignable}
              />
            </CardAction>
          ) : null}
        </CardHeader>
        <CardContent>
          <MemberTable
            organizationId={organizationId}
            initial={members}
            currentUserId={session.user.id}
            assignable={assignable}
            canUpdateRole={can(permissions, "members.update_role")}
            canRemove={can(permissions, "members.remove")}
          />
        </CardContent>
      </Card>
      {canInvite ? (
        <Card>
          <CardHeader>
            <CardTitle>{t("Pending invitations")}</CardTitle>
            <CardDescription>
              {t(
                "There is no mailer in this example: copy the link and send it yourself.",
              )}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <InvitationList invitations={invitations} />
          </CardContent>
        </Card>
      ) : null}
    </>
  );
}

export function MembersSectionSkeleton() {
  return (
    <div className="space-y-6" aria-busy="true">
      <Skeleton className="h-80 rounded-xl" />
      <Skeleton className="h-40 rounded-xl" />
    </div>
  );
}
