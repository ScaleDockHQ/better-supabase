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
  const owned = (filter: string): string => `select 1 from ${n.m} m
    where m.${n.user} = v_member${filter}`;

  return `-- The organizations whose last owner the member is: removing their
-- memberships (leaving, or deleting the account) would fail the owner check.
-- A member reads their own and the service role any member's. Another member's
-- list needs the remove permission (blocks.organizations.permissions.removeMember
-- or options.soleOwnedPermission) in every organization the list would name, and
-- in at least one organization of the member, so an offboarding run by HR can ask
-- first. Without it the call raises instead of returning a partial list.
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
  v_ids ${id}[];
begin
  if v_member is null then
    ${fail("ORGANIZATION_FORBIDDEN", "Only the member or the service role can read this")}
  end if;
  if not v_all and not exists (${owned(`
      and coalesce(better_supabase.member_can(auth.uid(), m.${n.tenant}, ${remove}), false)`)}) then
    ${fail("ORGANIZATION_FORBIDDEN", "Not allowed to read this member's organizations")}
  end if;
  v_ids := coalesce((
    select array_agg(m.${n.tenant} order by m.${n.tenant})
    from ${n.m} m
    where m.${n.user} = v_member and ${isOwner("m")}
      and exists (select 1 from ${n.organization} o where o.${n.id} = m.${n.tenant})
      and not exists (
        select 1 from ${n.m} y
        where y.${n.tenant} = m.${n.tenant} and y.${n.user} <> v_member and ${isOwner("y")}${activeMembership(ctx, "y")}
      )
  ), '{}');
  if not v_all and exists (
    select 1 from unnest(v_ids) t (id)
    where not coalesce(better_supabase.member_can(auth.uid(), t.id, ${remove}), false)
  ) then
    ${fail("ORGANIZATION_FORBIDDEN", "Not allowed to read this member's organizations")}
  end if;
  return v_ids;
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
