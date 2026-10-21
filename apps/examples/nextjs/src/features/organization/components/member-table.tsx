// #region recipe:members-table
"use client";

import { DbException } from "better-supabase";
import { useMembers } from "better-supabase/blocks/organizations/react";
import { UserMinusIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";
import * as v from "valibot";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { RoleBadge } from "@/features/user/components/role-badge";
import { assignableRoles } from "@/features/user/user-permissions";
import { Role } from "@/lib/claims";
import { initials } from "@/lib/initials";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

import type { Member } from "../organization-queries";

import { loadMembers, memberChanged } from "../organization-actions";
import { useRoleLabel } from "../use-role-label";

async function loadOrganizationMembers(): Promise<readonly Member[]> {
  const result = await loadMembers({});

  if (!result.ok) {
    throw new DbException(result.error);
  }

  return result.data;
}

/**
 * The organization's members. The server renders the rows; a role change shows
 * at once and goes through `update_member_role` in the browser.
 */
export function MemberTable({
  organizationId,
  initial,
  currentUserId,
  myRole,
  canUpdateRole,
  canRemove,
}: {
  organizationId: string;
  initial: readonly Member[];
  currentUserId: string;
  myRole: Role;
  canUpdateRole: boolean;
  canRemove: boolean;
}) {
  const t = useExtracted("organization");
  const roleLabel = useRoleLabel();
  const errorMessage = useErrorMessage();
  const format = useFormatter();

  const { members, pending, setRole, remove } = useMembers({
    organizationId,
    load: loadOrganizationMembers,
    initial,
    schema: blockConfig.organizations.api,
    onChanged: async ({ userId }) => {
      await memberChanged({ userId });
    },
  });

  const assignable = assignableRoles(myRole);

  const roleItems = assignable.map((role) => ({
    value: role,
    label: roleLabel(role),
  }));

  // Nobody changes their own role or an owner's here; ownership moves by transfer.
  const editable = (member: Member) =>
    member.userId !== currentUserId &&
    member.role !== "owner" &&
    assignable.includes(member.role);

  const busy = (member: Member) => pending.includes(member.userId);

  const changeRole = async (member: Member, role: Role) => {
    const result = await setRole(member.userId, role);

    if (result.ok) {
      toast.success(t("Role updated"));
    } else {
      toast.error(errorMessage(result.error));
    }
  };

  const removeMember = async (member: Member) => {
    const result = await remove(member.userId);

    if (result.ok) {
      toast.success(t("Member removed"));
    } else {
      toast.error(errorMessage(result.error));
    }
  };

  return (
    <Table data-testid="members">
      <TableHeader>
        <TableRow>
          <TableHead>{t("Member")}</TableHead>
          <TableHead>{t("Role")}</TableHead>
          <TableHead className="hidden sm:table-cell">{t("Joined")}</TableHead>
          <TableHead className="w-10" />
        </TableRow>
      </TableHeader>
      <TableBody>
        {(members ?? initial).map((member) => (
          <TableRow
            key={member.userId}
            aria-busy={busy(member) ? true : undefined}
            className={busy(member) ? "opacity-50" : undefined}
          >
            <TableCell>
              <div className="flex items-center gap-3">
                <Avatar className="size-8">
                  {member.avatarUrl ? (
                    <AvatarImage src={member.avatarUrl} alt="" />
                  ) : null}
                  <AvatarFallback>
                    {initials(member.name, member.email)}
                  </AvatarFallback>
                </Avatar>
                <div className="grid leading-tight">
                  <span className="font-medium">
                    {member.name ?? member.email}
                    {member.userId === currentUserId ? (
                      <span className="font-normal text-muted-foreground">
                        {" "}
                        ({t("you")})
                      </span>
                    ) : null}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {member.email}
                  </span>
                </div>
              </div>
            </TableCell>
            <TableCell>
              {canUpdateRole && editable(member) ? (
                <Select
                  value={member.role}
                  items={roleItems}
                  disabled={busy(member)}
                  onValueChange={(value) => {
                    if (v.is(Role, value)) {
                      void changeRole(member, value);
                    }
                  }}
                >
                  <SelectTrigger
                    size="sm"
                    className="w-32"
                    aria-label={t("Role")}
                  >
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {roleItems.map((item) => (
                      <SelectItem key={item.value} value={item.value}>
                        {item.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <RoleBadge role={member.role} />
              )}
            </TableCell>
            <TableCell className="hidden text-muted-foreground sm:table-cell">
              {member.joinedAt
                ? format.dateTime(new Date(member.joinedAt), {
                    dateStyle: "medium",
                  })
                : "–"}
            </TableCell>
            <TableCell>
              {canRemove && editable(member) ? (
                <Button
                  variant="ghost"
                  size="icon-sm"
                  disabled={busy(member)}
                  aria-label={t("Remove {name}", {
                    name: member.name ?? member.email ?? "",
                  })}
                  onClick={() => {
                    void removeMember(member);
                  }}
                >
                  <UserMinusIcon />
                </Button>
              ) : null}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
// #endregion recipe:members-table
