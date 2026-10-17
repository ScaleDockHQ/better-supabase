import type { ModuleContext } from "../context.ts";
import type { OrganizationReadNames } from "./organizations-reads.ts";

import { sqlString } from "../../core/template.ts";
import { membershipDisabledAt, SERVICE_CALLER, fail } from "../shared.ts";
import { OPERATIONS, modulePermission } from "./access-model.ts";

export interface SuspensionHelpers {
  readonly isOwner: (alias: string) => string;
  readonly activeOrganization: (organization: string) => string;
  readonly platformOverride: string;
  readonly assignableRole: (stored: string) => string;
  readonly event: (organization: string, user: string) => string;
}

export function memberSuspension(
  ctx: ModuleContext,
  n: OrganizationReadNames,
  helpers: SuspensionHelpers,
): string {
  const id = ctx.idType;
  const disabledAt = membershipDisabledAt(ctx);

  if (disabledAt === undefined) {
    return `
drop function if exists ${ctx.fn("suspend_member")}(${id}, uuid);
drop function if exists ${ctx.fn("resume_member")}(${id}, uuid);
`;
  }

  const allowed = `(${SERVICE_CALLER} or coalesce(better_supabase.member_can(auth.uid(), organization, ${modulePermission(ctx, "suspendMember", OPERATIONS["organizations.suspendMember"])}), false))`;
  const subject = "'organizations/' || organization::text";

  const body = (suspend: boolean): string => {
    const kind = suspend ? "suspended" : "resumed";
    const type = `organization.member_${kind}`;

    const lastOwner = suspend
      ? `
  if is_owner and not exists (
    select 1 from ${n.m} o
    where o.${n.tenant} = organization and o.${n.user} <> member and ${helpers.isOwner("o")} and o.${disabledAt} is null
  ) then
    ${fail("ORGANIZATION_OWNER_REQUIRED", "An organization needs an owner", "23514")}
  end if;`
      : "";

    return `
create or replace function ${ctx.fn(suspend ? "suspend_member" : "resume_member")}(organization ${id}, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  current_role_value text;
  is_owner boolean;
begin
  if member = auth.uid() then
    ${fail("ORGANIZATION_SELF", `You cannot ${suspend ? "suspend" : "resume"} yourself`, "22023")}
  end if;
  if not ${allowed}${helpers.platformOverride} then
    ${fail("ORGANIZATION_FORBIDDEN", `Not allowed to ${suspend ? "suspend" : "resume"} members`)}
  end if;
  if not (${helpers.activeOrganization("organization")}) then
    ${fail("ORGANIZATION_DISABLED", "The organization is unavailable")}
  end if;
  perform 1 from ${n.organization} o where o.${n.id} = organization for update;
  select ${helpers.assignableRole(`m.${n.role}`)}, ${helpers.isOwner("m")} into current_role_value, is_owner
  from ${n.m} m where m.${n.tenant} = organization and m.${n.user} = member;
  if not found then
    ${fail("ORGANIZATION_NOT_MEMBER", "Not a member", "P0002")}
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    ${fail("ORGANIZATION_ROLE_CEILING", "That member's role is above your own")}
  end if;${lastOwner}
  update ${n.m} set ${disabledAt} = ${suspend ? "now()" : "null"}
  where ${n.tenant} = organization and ${n.user} = member and ${disabledAt} is ${suspend ? "" : "not "}null;
  if not found then
    return false;
  end if;
  ${ctx.hook("after_member_change", [
    [id, "organization"],
    ["uuid", "member"],
    ["text", sqlString(kind)],
  ])}
  ${ctx.record({
    type,
    payload: helpers.event("organization", "member"),
    subject,
    tenant: "organization",
    audit: {
      category: "membership",
      targetType: "user",
      recordId: "member::text",
      metadata: "jsonb_build_object('userId', member)",
    },
  })}
  return true;
end;
$$;
`;
  };

  return `${body(true)}${body(false)}`;
}
