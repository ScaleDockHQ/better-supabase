import type { ModuleContext } from "../context.ts";

import { MODULE_PERMISSIONS } from "./access-model.ts";

/** Columns `reads` needs from `namesOf`. */
export interface OrganizationReadNames {
  readonly organization: string;
  readonly id: string;
  readonly m: string;
  readonly tenant: string;
  readonly user: string;
  readonly role: string;
}

export function organizationReads(
  ctx: ModuleContext,
  n: OrganizationReadNames,
): string {
  const name = ctx.col("organizations", "name");
  const slug = ctx.has("organizations", "slug")
    ? ctx.col("organizations", "slug")
    : undefined;
  const flags = (["deletedAt", "disabledAt"] as const)
    .filter((logical) => ctx.has("organizations", logical))
    .map((logical) => ` and o.${ctx.col("organizations", logical)} is null`)
    .join("");
  const invites = ctx.installed("invitations") ? invitationsRead(ctx) : "";
  return `
create or replace function ${ctx.fn("list_my_organizations")}()
returns table (
  id ${ctx.idType},
  name text${slug === undefined ? "" : ",\n  slug text"},
  role text
)
language sql
stable
security definer
set search_path = ''
as $$
  select o.${n.id}, o.${name}${slug === undefined ? "" : `, o.${slug}`}, m.${n.role}::text
  from ${n.m} m
  join ${n.organization} o on o.${n.id} = m.${n.tenant}
  where m.${n.user} = (select auth.uid())${flags}
    and not better_supabase.tenant_disabled(o.${n.id})
  order by o.${name}
$$;

create or replace function ${ctx.fn("list_members")}(organization ${ctx.idType})
returns table (user_id uuid, role text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'members.read'), false) then
    raise exception 'Not allowed to list members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select m.${n.user}, m.${n.role}::text
  from ${n.m} m
  where m.${n.tenant} = organization
  order by m.${n.user};
end;
$$;
${invites}`;
}

function invitationsRead(ctx: ModuleContext): string {
  const invitations = ctx.of("invitations");
  const table = invitations.table("invitations");
  const id = invitations.col("invitations", "id");
  const tenant = invitations.col("invitations", "tenant");
  const email = invitations.col("invitations", "email");
  const role = invitations.col("invitations", "role");
  const open = ["acceptedAt", "declinedAt", "revokedAt"]
    .filter((logical) => invitations.has("invitations", logical))
    .map((logical) => `i.${invitations.col("invitations", logical)} is null`)
    .join(" and ");
  const expires = invitations.has("invitations", "expiresAt")
    ? invitations.col("invitations", "expiresAt")
    : undefined;
  return `
create or replace function ${ctx.fn("list_organization_invitations")}(organization ${ctx.idType})
returns table (
  id uuid,
  email text,
  role text${expires === undefined ? "" : ",\n  expires_at timestamptz"}
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, ${ctx.of("invitations").permission("view", MODULE_PERMISSIONS.invitations.view)}), false) then
    raise exception 'Not allowed to list invitations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select i.${id}, i.${email}, i.${role}::text${expires === undefined ? "" : `, i.${expires}`}
  from ${table} i
  where i.${tenant} = organization${open === "" ? "" : ` and ${open}`}${expires === undefined ? "" : ` and i.${expires} >= now()`}
  order by ${expires === undefined ? `i.${id}` : `i.${expires}`} desc;
end;
$$;
`;
}
