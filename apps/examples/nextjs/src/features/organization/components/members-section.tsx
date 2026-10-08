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
import { can, roleOf } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getInvitations, getMembers } from "../organization-queries";
import { InvitationList } from "./invitation-list";
import { InviteMemberDialog } from "./invite-member-dialog";
import { MemberTable } from "./member-table";

/** Render inside `<Suspense>`; the fallback is `MembersSectionSkeleton`. */
export async function MembersSection() {
  const session = await getSession();
  const organizationId = tenantOf(session);
  const role = roleOf(session);
  if (!organizationId || !role || session.kind !== "user") return null;
  const canInvite = can(session, "members.invite");
  const [members, invitations, t] = await Promise.all([
    getMembers(organizationId),
    canInvite ? getInvitations(organizationId) : Promise.resolve([]),
    getExtracted("organization"),
  ]);
  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>{t("Members")}</CardTitle>
          <CardDescription>
            {t("{count, number} people in this organization", {
              count: members.length,
            })}
          </CardDescription>
          {canInvite ? (
            <CardAction>
              <InviteMemberDialog myRole={role} />
            </CardAction>
          ) : null}
        </CardHeader>
        <CardContent>
          <MemberTable
            members={members}
            currentUserId={session.user.id}
            myRole={role}
            canUpdateRole={can(session, "members.update_role")}
            canRemove={can(session, "members.remove")}
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
