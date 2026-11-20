import type { BlockSqlContext } from "../context.ts";

import { activeMembership, fail, SERVICE_CALLER } from "../shared.ts";

/** The table and column names `soleOwnedSql` reads. */
interface OwnerNames {
  readonly m: string;
  readonly organization: string;
  readonly id: string;
  readonly tenant: string;
  readonly user: string;
}

/**
 * `sole_owned_organizations(member)`: the organizations the deferred owner
 * check would refuse to leave without `member`. `remove` is the permission key,
 * as SQL, that lets the caller ask about another member of an organization.
 */
export function soleOwnedSql(
  ctx: BlockSqlContext,
  n: OwnerNames,
  id: string,
  isOwner: (alias: string) => string,
  remove: string,
): string {
  return `-- The organizations whose last owner the member is: removing their
-- memberships (leaving, or deleting the account) would fail the owner check.
-- A member reads their own and the service role any member's; for another
-- member, the caller gets the organizations where they may remove members
-- (blocks.organizations.permissions.removeMember), so an offboarding run by
-- HR can ask first. It never raises for another member.
create or replace function ${ctx.fn("sole_owned_organizations")}(member uuid default null)
returns ${id}[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member uuid := coalesce(member, auth.uid());
  v_all boolean := ${SERVICE_CALLER} or v_member = auth.uid();
begin
  if v_member is null then
    ${fail("ORGANIZATION_FORBIDDEN", "Only the member or the service role can read this")}
  end if;
  return coalesce((
    select array_agg(m.${n.tenant} order by m.${n.tenant})
    from ${n.m} m
    where m.${n.user} = v_member and ${isOwner("m")}
      and (v_all or coalesce(better_supabase.member_can(auth.uid(), m.${n.tenant}, ${remove}), false))
      and exists (select 1 from ${n.organization} o where o.${n.id} = m.${n.tenant})
      and not exists (
        select 1 from ${n.m} y
        where y.${n.tenant} = m.${n.tenant} and y.${n.user} <> v_member and ${isOwner("y")}${activeMembership(ctx, "y")}
      )
  ), '{}');
end;
$$;
`;
}

/** What a function of the organizations module's contract returns. */
export function organizationReturns(name: string): string {
  if (name === "create_organization") {
    return "{id}";
  }

  if (name === "sole_owned_organizations") {
    return "{id}[]";
  }

  if (
    name === "switch_organization" ||
    name === "update_member_roles" ||
    name === "page_organization_invitations" ||
    name === "page_organization_members"
  ) {
    return "jsonb";
  }

  return name.startsWith("list_") ? "record" : "boolean";
}
