"use client";

import { UserMinusIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useTransition } from "react";
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
import { useErrorMessage } from "@/lib/use-error-message";

import type { Member } from "../organization-queries";

import { removeMember, updateMemberRole } from "../organization-actions";
import { useRoleLabel } from "../use-role-label";

export function MemberTable({
  members,
  currentUserId,
  myRole,
  canUpdateRole,
  canRemove,
}: {
  members: readonly Member[];
  currentUserId: string;
  myRole: Role;
  canUpdateRole: boolean;
  canRemove: boolean;
}) {
  const t = useExtracted("organization");
  const roleLabel = useRoleLabel();
  const errorMessage = useErrorMessage();
  const format = useFormatter();
  const [pending, startTransition] = useTransition();
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
        {members.map((member) => (
          <TableRow key={member.userId}>
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
                      <span className="text-muted-foreground font-normal">
                        {" "}
                        ({t("you")})
                      </span>
                    ) : null}
                  </span>
                  <span className="text-muted-foreground text-xs">
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
                  disabled={pending}
                  onValueChange={(value) => {
                    if (!v.is(Role, value)) return;
                    startTransition(async () => {
                      const result = await updateMemberRole({
                        userId: member.userId,
                        role: value,
                      });
                      if (result.ok) toast.success(t("Role updated"));
                      else toast.error(errorMessage(result.error));
                    });
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
            <TableCell className="text-muted-foreground hidden sm:table-cell">
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
                  disabled={pending}
                  aria-label={t("Remove {name}", {
                    name: member.name ?? member.email ?? "",
                  })}
                  onClick={() => {
                    startTransition(async () => {
                      const result = await removeMember({
                        userId: member.userId,
                      });
                      if (result.ok) toast.success(t("Member removed"));
                      else toast.error(errorMessage(result.error));
                    });
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
