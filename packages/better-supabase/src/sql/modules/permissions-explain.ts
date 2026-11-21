import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";
import { capFor } from "./permissions-delegation.ts";
import { OPERATIONS, accessModel } from "./permissions-model.ts";

const SERVICE = `coalesce(auth.jwt() ->> 'role', '') = 'service_role'`;

/** The membership table and columns `explain_permission` reads. */
export interface ExplainNames {
  readonly m: string;
  readonly tenant: string;
  readonly user: string;
  readonly role: string;
}

/**
 * `explain_permission`: why a member does or doesn't hold one key in a tenant.
 * Callers read their own answer, and members with the members read key read
 * anyone's in the tenant. It reads the answer from `member_can`, so it can't
 * disagree with a check.
 */
export function explainSql(
  ctx: BlockSqlContext,
  n: ExplainNames,
  active: string,
): string {
  const id = ctx.idType;

  // A provider's functions list no key for this, so with `model: "provider"`
  // the members read key is not checked: only the service role and a member's
  // own answer pass.
  const reader =
    accessModel(ctx) === "provider"
      ? ""
      : `\n    or coalesce(better_supabase.member_can(auth.uid(), explain_permission.tenant, ${ctx.permission("explain", OPERATIONS["permissions.explain"])}), false)`;

  const override =
    accessModel(ctx) === "catalog" && ctx.hasTable("overrides")
      ? `(select bool_and(ov.${ctx.col("overrides", "granted")}) from ${ctx.table("overrides")} ov
        join ${ctx.table("permissions")} p on p.${ctx.col("permissions", "id")} = ov.${ctx.col("overrides", "permission")}
        join ${n.m} m on m.${n.tenant} = explain_permission.tenant and m.${n.user} = explain_permission.member and m.${n.role} = ov.${ctx.col("overrides", "role")}
        where ov.${ctx.col("overrides", "tenant")} = explain_permission.tenant
          and p.${ctx.col("permissions", "key")} = explain_permission.permission)`
      : "null::boolean";

  return `
-- Why a member does or doesn't hold one key in a tenant: the answer member_can
-- gives, the roles the member holds, the granted keys that match and a reason.
create or replace function better_supabase.explain_permission(tenant ${id}, member uuid, permission text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_allowed boolean;
  v_member boolean;
  v_roles jsonb;
  v_matched text[];
  v_override boolean;
  v_reason text;
begin
  if not (${SERVICE} or explain_permission.member is not distinct from auth.uid()${reader}) then
    ${fail("PERMISSIONS_FORBIDDEN", "Not allowed to explain this member's permissions")}
  end if;
  v_allowed := coalesce(better_supabase.member_can(explain_permission.member, explain_permission.tenant, explain_permission.permission), false);
  select count(*) > 0, coalesce(jsonb_agg(m.${n.role}::text), '[]'::jsonb) into v_member, v_roles
  from ${n.m} m
  where m.${n.tenant} = explain_permission.tenant and m.${n.user} = explain_permission.member${active};
  v_matched := coalesce((
    select array_agg(k.key order by k.key)
    from unnest(better_supabase.member_permissions(explain_permission.member, explain_permission.tenant)) k(key)
    where better_supabase.permission_matches(k.key, explain_permission.permission)
  ), '{}'::text[]);
  v_override := ${override};
  v_reason := case
    when v_allowed then case when v_override is true then 'granted_by_override' else 'granted_by_role' end
    when better_supabase.user_disabled(explain_permission.member) then 'member_disabled'
    when better_supabase.tenant_disabled(explain_permission.tenant) then 'organization_disabled'
    when not v_member then 'not_a_member'
    when v_override is false then 'denied_by_override'
    when ${capFor("explain_permission.member", "explain_permission.permission")} is not true then 'not_in_scope'
    else 'role_lacks_key'
  end;
  return jsonb_build_object(
    'permission', explain_permission.permission,
    'userId', explain_permission.member,
    'organizationId', explain_permission.tenant,
    'allowed', v_allowed,
    'reason', v_reason,
    'roles', v_roles,
    'matchedBy', to_jsonb(v_matched),
    'override', v_override
  );
end;
$$;
${userGrant(`better_supabase.explain_permission(${id}, uuid, text)`)}`;
}
