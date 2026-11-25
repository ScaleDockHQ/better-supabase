import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { raise } from "./invitations-tables.ts";
import { OPERATIONS } from "./permissions-model.ts";

/**
 * `invite_within_seats`: `saas.inviteWithinSeats` as one atomic function (ADR
 * 1235). It counts the members, reads the `seats` entitlement and invites in
 * the caller's transaction, so the three steps cost one call and a concurrent
 * invite cannot slip past the count. Without the entitlements module there is
 * no cap, as in the client helper.
 */
export function inviteWithinSeats(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const members = ctx.of("memberships");
  const m = members.table("memberships");
  const mt = members.col("memberships", "tenant");
  const validFor = sqlString(ctx.text("validFor", "7 days"));

  const cap = ctx.installed("entitlements")
    ? "cap := better_supabase.tenant_entitlement_value(tenant, 'seats');"
    : "cap := null;";

  return `
-- Invites like invite_member when the tenant has a seat left: members counted
-- against the numeric \`seats\` entitlement, in one transaction. A plan without
-- a numeric seats value has no cap. Pending invitations do not count.
create or replace function ${ctx.fn("invite_within_seats")}(
  tenant ${id},
  invitee_email text,
  invitee_role text,
  valid_for interval default ${validFor}
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := ${SERVICE_CALLER};
  used integer;
  cap jsonb;
begin
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, ${ctx.permission("invite", OPERATIONS["invitations.invite"])}), false) then
    ${raise("INVITATION_FORBIDDEN", "Not allowed to invite members")}
  end if;
  ${cap}
  select count(*) into used from ${m} m where m.${mt} = tenant;
  if cap is not null and jsonb_typeof(cap) = 'number' and used >= (cap #>> '{}')::numeric then
    ${raise("INVITATION_NO_SEAT", "The plan has no seat left")}
  end if;
  return ${ctx.fn("invite_member")}(tenant, invitee_email, invitee_role, valid_for);
end;
$$;
`;
}
