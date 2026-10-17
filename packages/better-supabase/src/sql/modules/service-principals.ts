import type { ServicePrincipalsEvents } from "../../blocks/service-principals/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import {
  addExtraColumns,
  columnsObject,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";
import { checkRole, roleValue } from "./organizations.ts";

/** The `app_metadata` key that marks an `auth.users` row as a service principal. */
const SERVICE_PRINCIPAL_CLAIM = "bs_service_principal";

const EVENTS: ModuleEvents<ServicePrincipalsEvents> = {
  "service_principal.created": {
    subject: "service-principals",
    payload: ["organizationId", "id", "name", "role"],
  },
  "service_principal.role_changed": {
    subject: "service-principals",
    payload: ["organizationId", "id", "role"],
  },
  "service_principal.disabled": {
    subject: "service-principals",
    payload: ["organizationId", "id"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    principals: {
      name: "service_principals",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        role: "role",
        isDefault: "is_default",
        createdBy: "created_by",
        createdAt: "created_at",
        disabledAt: "disabled_at",
      },
    },
  },
};

/** `options.extraColumns`, added to a managed principals table. */
const extrasOf = (ctx: ModuleContext) => ctx.extraColumns("principals");

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const extras = extrasOf(ctx);
  const t = ctx.table("principals");
  const c = (column: string): string => ctx.col("principals", column);
  const fn = (name: string): string => ctx.fn(name);
  const id = ctx.idType;
  const read = ctx.permission("read", OPERATIONS["service-principals.read"]);
  const manage = ctx.permission(
    "manage",
    OPERATIONS["service-principals.manage"],
  );
  const tenant = ctx.of("tenant");
  const memberships = tenant.mode !== "custom";
  const m = tenant.table("memberships");
  const mt = tenant.col("memberships", "tenant");
  const mu = tenant.col("memberships", "user");
  const mr = tenant.col("memberships", "role");
  const tables = ctx.manages
    ? `create table if not exists ${t} (
  ${c("id")} uuid primary key references auth.users (id) on delete cascade,
  ${c("tenant")} ${id} not null,
  ${c("name")} text not null check (length(${c("name")}) between 1 and 120),
  ${c("role")} text not null check (length(${c("role")}) between 1 and 200),
  ${c("isDefault")} boolean not null default false,
  ${c("createdBy")} uuid references auth.users (id) on delete set null,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("disabledAt")} timestamptz,
  unique (${c("tenant")}, ${c("name")})
);
create index if not exists service_principals_tenant_idx on ${t} (${c("tenant")});
create index if not exists service_principals_created_by_idx on ${t} (${c("createdBy")});
create unique index if not exists service_principals_default_idx on ${t} (${c("tenant")})
  where ${c("isDefault")} and ${c("disabledAt")} is null;${addExtraColumns(t, extras)}
${lockTable(t, { read: true })}
`
    : "";
  // Only the caller check differs between the service and a member who
  // holds the manage permission and may assign the role.
  const mayManage = (
    args: string,
    tenant: string,
    role: string,
  ): string => `if not (${SERVICE_CALLER}) then
    ${fail("SERVICE_PRINCIPAL_FORBIDDEN", "Service principals are managed by the service", "42501")}
  end if;
  if ${args}.created_by is not null and not (
    coalesce(better_supabase.member_can(${args}.created_by, ${tenant}, ${manage}), false)
    and coalesce(better_supabase.can_assign_as(${args}.created_by, ${tenant}, ${role}), false)
  ) then
    ${fail("SERVICE_PRINCIPAL_FORBIDDEN", "You may not manage service principals with this role", "42501")}
  end if;`;
  const addMembership = memberships
    ? `
  insert into ${m} (${mt}, ${mu}, ${mr})
  values (register_service_principal.tenant, register_service_principal.principal, ${roleValue(ctx, "register_service_principal.role", "register_service_principal.tenant")});`
    : "";
  const setMembership = memberships
    ? `
  update ${m} set ${mr} = ${roleValue(ctx, "set_service_principal_role.role", `v_row.${c("tenant")}`)}
  where ${mt} = v_row.${c("tenant")} and ${mu} = v_row.${c("id")};`
    : "";
  const dropMembership = memberships
    ? `
  delete from ${m} where ${mt} = v_row.${c("tenant")} and ${mu} = v_row.${c("id")};`
    : "";
  return `${schemaPreamble(ctx)}
-- Non-human members of a tenant. Each row is an auth.users row that can't
-- sign in (no password, banned, app_metadata.${SERVICE_PRINCIPAL_CLAIM}),
-- created through the Auth admin API, and holds its role through a tenant
-- membership like any member. Organization-owned workflow versions and
-- service webhook endpoints run as the tenant's default principal.
${tables}
drop policy if exists service_principals_read on ${t};
create policy service_principals_read on ${t} for select to authenticated
using (${c("tenant")} in (select ${ctx.scope.ids(read)}));

-- Registers an auth.users row the service created for a principal and adds
-- its membership with role. The user must carry
-- app_metadata.${SERVICE_PRINCIPAL_CLAIM} and be banned, so a real account
-- never becomes one. With created_by, that member needs the manage
-- permission and may assign role. Service role only.
${extraFieldsArg(extras).drop(fn("register_service_principal"), `uuid, ${id}, text, text, boolean, uuid`)}
create or replace function ${fn("register_service_principal")}(principal uuid, tenant ${id}, name text, role text, is_default boolean default false, created_by uuid default null${extraFieldsArg(extras).param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  ${mayManage("register_service_principal", "register_service_principal.tenant", "register_service_principal.role")}
  if not exists (
    select 1 from auth.users u
    where u.id = register_service_principal.principal
      and coalesce((u.raw_app_meta_data ->> '${SERVICE_PRINCIPAL_CLAIM}')::boolean, false)
      and u.banned_until > now() + interval '50 years'
  ) then
    ${fail("SERVICE_PRINCIPAL_USER", "The user is not a service principal: create it with createServicePrincipals().create", "22023")}
  end if;${checkRole(ctx, "register_service_principal.role", "register_service_principal.tenant")}
  if register_service_principal.is_default then
    update ${t} set ${c("isDefault")} = false
    where ${c("tenant")} = register_service_principal.tenant and ${c("isDefault")};
  end if;
  insert into ${t} (${c("id")}, ${c("tenant")}, ${c("name")}, ${c("role")}, ${c("isDefault")}, ${c("createdBy")})
  values (register_service_principal.principal, register_service_principal.tenant, register_service_principal.name,
    register_service_principal.role, coalesce(register_service_principal.is_default, false), register_service_principal.created_by);${writeExtraColumns(t, extras, "register_service_principal.fields", `x.${c("id")} = register_service_principal.principal`)}${addMembership}
  ${ctx.record({
    type: "service_principal.created",
    payload: `jsonb_build_object('organizationId', register_service_principal.tenant::text, 'id', register_service_principal.principal, 'name', register_service_principal.name, 'role', register_service_principal.role)`,
    subject: `'service-principals/' || register_service_principal.principal::text`,
    tenant: "register_service_principal.tenant",
    audit: {
      category: "access",
      targetType: "service_principal",
      recordId: "register_service_principal.principal::text",
      targetLabel: "register_service_principal.name",
      actor: "coalesce(register_service_principal.created_by, auth.uid())",
    },
  })}
  return jsonb_build_object('id', register_service_principal.principal, 'tenant', register_service_principal.tenant,
    'name', register_service_principal.name, 'role', register_service_principal.role,
    'isDefault', coalesce(register_service_principal.is_default, false)${
      extras.length === 0
        ? ""
        : `,
    'fields', (select ${columnsObject(
      "p",
      extras.map((extra) => extra.name),
    )} from ${t} p where p.${c("id")} = register_service_principal.principal)`
    });
end;
$$;
${serviceGrant(`${fn("register_service_principal")}(uuid, ${id}, text, text, boolean, uuid${extraFieldsArg(extras).type})`)}

-- Changes a principal's role and its membership. Service role only; with
-- created_by, that member needs the manage permission and may assign role.
create or replace function ${fn("set_service_principal_role")}(principal uuid, role text, created_by uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${t};
begin
  select * into v_row from ${t} p where p.${c("id")} = set_service_principal_role.principal and p.${c("disabledAt")} is null for update;
  if not found then
    ${fail("SERVICE_PRINCIPAL_NOT_FOUND", "No such service principal", "P0002")}
  end if;
  ${mayManage("set_service_principal_role", `v_row.${c("tenant")}`, "set_service_principal_role.role")}${checkRole(ctx, "set_service_principal_role.role", `v_row.${c("tenant")}`)}
  update ${t} set ${c("role")} = set_service_principal_role.role where ${c("id")} = v_row.${c("id")};${setMembership}
  ${ctx.record({
    type: "service_principal.role_changed",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}::text, 'id', v_row.${c("id")}, 'role', set_service_principal_role.role)`,
    subject: `'service-principals/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "access",
      targetType: "service_principal",
      recordId: `v_row.${c("id")}::text`,
      targetLabel: `v_row.${c("name")}`,
      actor: "coalesce(set_service_principal_role.created_by, auth.uid())",
    },
  })}
  return true;
end;
$$;
${serviceGrant(`${fn("set_service_principal_role")}(uuid, text, uuid)`)}

-- Switches a principal off: it loses its membership and stops being the
-- default, so workflow steps and deliveries that resolve to it are refused.
-- The auth.users row stays for the audit trail. Service role only.
create or replace function ${fn("disable_service_principal")}(principal uuid, created_by uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${t};
begin
  select * into v_row from ${t} p where p.${c("id")} = disable_service_principal.principal and p.${c("disabledAt")} is null for update;
  if not found then
    return false;
  end if;
  ${mayManage("disable_service_principal", `v_row.${c("tenant")}`, `v_row.${c("role")}`)}
  update ${t} set ${c("disabledAt")} = now(), ${c("isDefault")} = false where ${c("id")} = v_row.${c("id")};${dropMembership}
  ${ctx.record({
    type: "service_principal.disabled",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}::text, 'id', v_row.${c("id")})`,
    subject: `'service-principals/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "access",
      targetType: "service_principal",
      recordId: `v_row.${c("id")}::text`,
      targetLabel: `v_row.${c("name")}`,
      actor: "coalesce(disable_service_principal.created_by, auth.uid())",
    },
  })}
  return true;
end;
$$;
${serviceGrant(`${fn("disable_service_principal")}(uuid, uuid)`)}

-- The tenant's default principal, or null. Workflow builder and webhook
-- delivery resolve organization-owned work to it.
create or replace function ${fn("default_service_principal")}(tenant ${id})
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.${c("id")} from ${t} p
  where p.${c("tenant")} = default_service_principal.tenant and p.${c("isDefault")} and p.${c("disabledAt")} is null
$$;
${serviceGrant(`${fn("default_service_principal")}(${id})`)}

-- The tenant's principals the caller may read, through the read policy.
create or replace function ${fn("service_principals_list")}(tenant ${id})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.${c("id")}, 'name', p.${c("name")}, 'role', p.${c("role")}, 'isDefault', p.${c("isDefault")},
    'createdBy', p.${c("createdBy")}, 'createdAt', p.${c("createdAt")}, 'disabledAt', p.${c("disabledAt")}${extraFieldsJson("p", extras)}
  ) order by p.${c("name")}), '[]'::jsonb)
  from ${t} p
  where p.${c("tenant")} = service_principals_list.tenant
$$;
${userGrant(`${fn("service_principals_list")}(${id})`)}
`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  return [
    {
      name: "register_service_principal",
      args: [
        "uuid",
        "{id}",
        "text",
        "text",
        "boolean",
        "uuid",
        ...extraFieldsArg(extrasOf(ctx)).contract,
      ],
      returns: "jsonb",
    },
    {
      name: "set_service_principal_role",
      args: ["uuid", "text", "uuid"],
      returns: "boolean",
    },
    {
      name: "disable_service_principal",
      args: ["uuid", "uuid"],
      returns: "boolean",
    },
    { name: "default_service_principal", args: ["{id}"], returns: "uuid" },
    { name: "service_principals_list", args: ["{id}"], returns: "jsonb" },
  ];
}

export const SERVICE_PRINCIPALS: ModuleDefinition = {
  name: "service-principals",
  scopes: ["tenant"],
  title: "Service principals",
  description:
    "Non-human tenant members backed by auth.users rows that can't sign in, with roles through memberships. Organization-owned workflow versions and service webhook endpoints run as the tenant's default principal.",
  requires: ["tenant", "access"],
  integrates: ["audit"],
  target: "schema",
  version: 1,
  modes: ["managed", "adopt", "custom"],
  names: NAMES,
  contract,
  build,
};
