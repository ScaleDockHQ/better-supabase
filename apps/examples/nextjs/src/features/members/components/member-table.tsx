// #region recipe:members-table
"use client";

import type { CellContext, ColumnDef } from "@tanstack/react-table";

import { useTable } from "@tanstack/react-table";
import { DbException } from "better-supabase";
import { UserMinusIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { createContext, use, useCallback, useMemo, useState } from "react";
import { toast } from "sonner";
import * as v from "valibot";

import type { DataGridFeatures } from "@/components/reui/data-grid/data-grid";
import type { Member } from "@/features/organization/organization-queries";

import {
  DataGrid,
  DataGridContainer,
  dataGridFeatures,
} from "@/components/reui/data-grid/data-grid";
import { DataGridScrollArea } from "@/components/reui/data-grid/data-grid-scroll-area";
import { DataGridTable } from "@/components/reui/data-grid/data-grid-table";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  loadMembers,
  memberChanged,
} from "@/features/organization/organization-actions";
import { useRoleLabel } from "@/features/organization/use-role-label";
import { RoleBadge } from "@/features/user/components/role-badge";
import { useMembers } from "@/hooks/use-organizations";
import { Link } from "@/i18n/navigation";
import { Role } from "@/lib/claims";
import { initials } from "@/lib/initials";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

async function loadOrganizationMembers(): Promise<readonly Member[]> {
  const result = await loadMembers({});

  if (!result.ok) {
    throw new DbException(result.error);
  }

  return result.data;
}

/** A team as the members table shows it: its name and who is on it. */
export interface MemberTeam {
  readonly id: string;
  readonly name: string;
  readonly memberIds: readonly string[];
}

type MemberRow = Member & {
  readonly teams: readonly MemberTeam[];
  readonly you: boolean;
  /** The roles the caller may pick here, empty when the role is fixed. */
  readonly roleChoices: readonly Role[];
  readonly removable: boolean;
  readonly busy: boolean;
};

type MemberCell = CellContext<DataGridFeatures, MemberRow>;

const ALL_ROLES = "all";

function MemberCellView({ row }: MemberCell) {
  const t = useExtracted("members");
  const member = row.original;

  return (
    <div className="flex items-center gap-3">
      <Avatar className="size-8">
        {member.avatarUrl ? (
          <AvatarImage src={member.avatarUrl} alt="" />
        ) : null}
        <AvatarFallback>{initials(member.name, member.email)}</AvatarFallback>
      </Avatar>
      <div className="grid min-w-0 leading-tight">
        <Link
          href={`/settings/members/${member.userId}`}
          prefetch
          className="truncate font-medium hover:underline"
        >
          {member.name ?? member.email}
          {member.you ? (
            <span className="font-normal text-muted-foreground">
              {" "}
              ({t("you")})
            </span>
          ) : null}
        </Link>
        <span className="truncate text-xs text-muted-foreground">
          {member.email}
        </span>
      </div>
    </div>
  );
}

function TeamsCell({ row }: MemberCell) {
  const { teams } = row.original;

  if (teams.length === 0) {
    return <span className="text-muted-foreground">–</span>;
  }

  return (
    <div className="flex flex-wrap gap-1">
      {teams.map((team) => (
        <Badge key={team.id} variant="outline">
          {team.name}
        </Badge>
      ))}
    </div>
  );
}

function JoinedCell({ row }: MemberCell) {
  const format = useFormatter();
  const { joinedAt } = row.original;

  return (
    <span className="text-muted-foreground tabular-nums">
      {joinedAt
        ? format.dateTime(new Date(joinedAt), { dateStyle: "medium" })
        : "–"}
    </span>
  );
}

interface MemberActions {
  readonly changeRole: (member: Member, role: Role) => Promise<void>;
  readonly removeMember: (member: Member) => Promise<void>;
}

const MemberActionsContext = createContext<MemberActions | null>(null);

function useMemberActions(): MemberActions {
  const actions = use(MemberActionsContext);

  if (actions === null) {
    throw new Error("Render member cells inside <MemberTable>.");
  }

  return actions;
}

function RoleCell({ row }: MemberCell) {
  const t = useExtracted("members");
  const roleLabel = useRoleLabel();
  const { changeRole } = useMemberActions();
  const member = row.original;

  if (member.roleChoices.length === 0) {
    return <RoleBadge role={member.role} />;
  }

  const items = member.roleChoices.map((role) => ({
    value: role,
    label: roleLabel(role),
  }));

  return (
    <Select
      value={member.role}
      items={items}
      disabled={member.busy}
      onValueChange={(value) => {
        if (v.is(Role, value)) {
          void changeRole(member, value);
        }
      }}
    >
      <SelectTrigger size="sm" className="w-32" aria-label={t("Role")}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {items.map((item) => (
          <SelectItem key={item.value} value={item.value}>
            {item.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function ActionsCell({ row }: MemberCell) {
  const t = useExtracted("members");
  const { removeMember } = useMemberActions();
  const member = row.original;

  if (!member.removable) {
    return null;
  }

  return (
    <Button
      variant="ghost"
      size="icon-sm"
      disabled={member.busy}
      aria-label={t("Remove {name}", {
        name: member.name ?? member.email ?? "",
      })}
      onClick={() => {
        void removeMember(member);
      }}
    >
      <UserMinusIcon />
    </Button>
  );
}

/**
 * The organization's members in a ReUI data grid, with a search and a role
 * filter. The server renders the rows; a role change shows at once and goes
 * through `update_member_role` in the browser.
 */
export function MemberTable({
  organizationId,
  initial,
  teams,
  currentUserId,
  assignable,
  canUpdateRole,
  canRemove,
}: {
  organizationId: string;
  initial: readonly Member[];
  teams: readonly MemberTeam[];
  currentUserId: string;
  assignable: readonly Role[];
  canUpdateRole: boolean;
  canRemove: boolean;
}) {
  const t = useExtracted("members");
  const roleLabel = useRoleLabel();
  const errorMessage = useErrorMessage();
  const [search, setSearch] = useState("");

  const [roleFilter, setRoleFilter] = useState<Role | typeof ALL_ROLES>(
    ALL_ROLES,
  );

  const { members, pending, setRole, remove } = useMembers({
    organizationId,
    load: loadOrganizationMembers,
    initial,
    schema: blockConfig.organizations.api,
    onChanged: async ({ userId }) => {
      await memberChanged({ userId });
    },
  });

  const filterItems = [
    { value: ALL_ROLES, label: t("All roles") },
    ...Role.options.map((role) => ({ value: role, label: roleLabel(role) })),
  ];

  // Nobody changes their own role or an owner's here; ownership moves by transfer.
  const editable = (member: Member) =>
    member.userId !== currentUserId &&
    member.role !== "owner" &&
    assignable.includes(member.role);

  const changeRole = useCallback(
    async (member: Member, role: Role) => {
      const result = await setRole({ userId: member.userId, role });

      if (result.ok) {
        toast.success(t("Role updated"));
      } else {
        toast.error(errorMessage(result.error));
      }
    },
    [setRole, t, errorMessage],
  );

  const removeMember = useCallback(
    async (member: Member) => {
      const result = await remove(member.userId);

      if (result.ok) {
        toast.success(t("Member removed"));
      } else {
        toast.error(errorMessage(result.error));
      }
    },
    [remove, t, errorMessage],
  );

  const actions = useMemo(
    () => ({ changeRole, removeMember }),
    [changeRole, removeMember],
  );

  const columns: ColumnDef<DataGridFeatures, MemberRow>[] = [
    { id: "member", header: t("Member"), cell: MemberCellView, size: 280 },
    { accessorKey: "role", header: t("Role"), cell: RoleCell, size: 150 },
    { id: "teams", header: t("Teams"), cell: TeamsCell, size: 200 },
    {
      accessorKey: "joinedAt",
      header: t("Joined"),
      cell: JoinedCell,
      size: 140,
    },
    { id: "actions", header: "", cell: ActionsCell, size: 56 },
  ];

  const needle = search.trim().toLowerCase();
  const all = members ?? initial;

  const data: MemberRow[] = all
    .filter(
      (member) =>
        (roleFilter === ALL_ROLES || member.role === roleFilter) &&
        (needle === "" ||
          [member.name, member.email].some((text) =>
            text?.toLowerCase().includes(needle),
          )),
    )
    .map((member) => ({
      ...member,
      teams: teams.filter((team) => team.memberIds.includes(member.userId)),
      you: member.userId === currentUserId,
      roleChoices: canUpdateRole && editable(member) ? assignable : [],
      removable: canRemove && editable(member),
      busy: pending.includes(member.userId),
    }));

  const table = useTable({
    features: dataGridFeatures,
    columns,
    data,
    getRowId: (row) => row.userId,
  });

  const clearFilters = () => {
    setSearch("");
    setRoleFilter(ALL_ROLES);
  };

  return (
    <MemberActionsContext value={actions}>
      <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Input
            type="search"
            className="w-56"
            value={search}
            placeholder={t("Search members")}
            aria-label={t("Search members")}
            onChange={(event) => {
              setSearch(event.target.value);
            }}
          />
          <Select
            value={roleFilter}
            items={filterItems}
            onValueChange={(value) => {
              setRoleFilter(v.is(Role, value) ? value : ALL_ROLES);
            }}
          >
            <SelectTrigger size="sm" className="w-36" aria-label={t("Role")}>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {filterItems.map((item) => (
                <SelectItem key={item.value} value={item.value}>
                  {item.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div data-testid="members">
          <DataGrid
            table={table}
            recordCount={data.length}
            tableLayout={{ dense: true }}
            emptyMessage={
              <Empty>
                <EmptyHeader>
                  <EmptyTitle>{t("No members match")}</EmptyTitle>
                  <EmptyDescription>
                    {t("Try another name or role.")}
                  </EmptyDescription>
                </EmptyHeader>
                <EmptyContent>
                  <Button size="sm" variant="outline" onClick={clearFilters}>
                    {t("Clear filters")}
                  </Button>
                </EmptyContent>
              </Empty>
            }
          >
            <DataGridContainer>
              <DataGridScrollArea>
                <DataGridTable />
              </DataGridScrollArea>
            </DataGridContainer>
          </DataGrid>
        </div>
      </div>
    </MemberActionsContext>
  );
}
// #endregion recipe:members-table
