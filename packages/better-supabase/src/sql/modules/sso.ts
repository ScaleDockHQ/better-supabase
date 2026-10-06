import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, schemaPreamble } from "../shared.ts";
import { accessModel, MODULE_PERMISSIONS, roleNames } from "./access-model.ts";
import { roleValue } from "./organizations.ts";
import { type ScimSqlNames, scimSql } from "./sso-scim-sql.ts";
import { roleNameOf } from "./tenant.ts";

const NAMES: ModuleNames = {
  options: ["txtPrefix", "defaultRole", "roleOrder", "groupRoles"],
  hooks: [],
  tables: {
    domains: {
      name: "organization_domains",
      columns: {
        id: "id",
        tenant: "organization_id",
        domain: "domain",
        token: "verification_token",
        verifiedAt: "verified_at",
        autoJoinRole: "auto_join_role",
        enforceSso: "enforce_sso",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    providers: {
      name: "organization_sso_providers",
      columns: {
        id: "id",
        tenant: "organization_id",
        type: "type",
        metadataUrl: "metadata_url",
        domains: "domains",
        createdAt: "created_at",
      },
    },
    scimUsers: {
      name: "scim_users",
      columns: {
        id: "id",
        tenant: "organization_id",
        user: "user_id",
        externalId: "external_id",
        userName: "user_name",
        displayName: "display_name",
        givenName: "given_name",
        familyName: "family_name",
        email: "email",
        emails: "emails",
        active: "active",
        version: "version",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    scimGroups: {
      name: "scim_groups",
      columns: {
        id: "id",
        tenant: "organization_id",
        displayName: "display_name",
        externalId: "external_id",
        role: "role",
        version: "version",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    scimMembers: {
      name: "scim_group_members",
      columns: { group: "group_id", member: "scim_user_id" },
    },
  },
};

const PREFIX = /^_[a-z0-9][a-z0-9-]{0,61}$/;
const DOMAIN = "^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$";

interface Roles {
  readonly owner: string;
  /** Roles SCIM and auto-join may assign, highest first. */
  readonly order: readonly string[];
  readonly fallback: string;
  readonly groups: readonly (readonly [string, string])[];
}

function rolesFor(ctx: ModuleContext): Roles {
  const model = accessModel(ctx);
  if (model !== "roles" && model !== "catalog") {
    throw new TypeError(
      `sql.modules.sso assigns membership roles, which needs sql.modules.access.model "roles" or "catalog", not "${model}"`,
    );
  }
  const owner = ctx.installed("organizations")
    ? ctx.of("organizations").text("ownerRole", "owner")
    : "owner";
  const order = ctx.list(
    "roleOrder",
    roleNames(ctx).filter((role) => role !== owner),
  );
  if (order.includes(owner)) {
    throw new TypeError(
      `sql.modules.sso.options.roleOrder must not include the owner role "${owner}"`,
    );
  }
  const fallback = ctx.text("defaultRole", "member");
  const where = "sql.modules.sso.options";
  if (!order.includes(fallback)) {
    throw new TypeError(
      `${where}.defaultRole "${fallback}" must be one of roleOrder (${order.join(", ")})`,
    );
  }
  const option = ctx.option("groupRoles") ?? {};
  if (typeof option !== "object" || Array.isArray(option)) {
    throw new TypeError(
      `${where}.groupRoles must map SCIM group names to roles`,
    );
  }
  const groups = Object.entries(option).map(([name, role]) => {
    if (typeof role !== "string" || !order.includes(role)) {
      throw new TypeError(
        `${where}.groupRoles["${name}"] must be one of roleOrder (${order.join(", ")})`,
      );
    }
    return [name.toLowerCase(), role] as const;
  });
  return { owner, order, fallback, groups };
}

function prefixOf(ctx: ModuleContext): string {
  const prefix = ctx.text("txtPrefix", "_better-supabase");
  if (!PREFIX.test(prefix)) {
    throw new TypeError(
      "sql.modules.sso.options.txtPrefix must start with an underscore and hold lowercase letters, digits or dashes",
    );
  }
  return prefix;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const roles = rolesFor(ctx);
  const prefix = prefixOf(ctx);
  const fn = (name: string): string => ctx.fn(name);
  const d = ctx.table("domains");
  const p = ctx.table("providers");
  const u = ctx.table("scimUsers");
  const g = ctx.table("scimGroups");
  const gm = ctx.table("scimMembers");
  const cd = (c: string): string => ctx.col("domains", c);
  const cp = (c: string): string => ctx.col("providers", c);
  const cu = (c: string): string => ctx.col("scimUsers", c);
  const cg = (c: string): string => ctx.col("scimGroups", c);
  const cm = (c: string): string => ctx.col("scimMembers", c);
  const permissions = MODULE_PERMISSIONS.sso;
  const key = ctx.permission("manage", permissions.manage);
  const can = (tenant: string): string =>
    `coalesce(better_supabase.can('tenant', ${tenant}, ${key}), false)`;
  const actorCan = (tenant: string, actor: string): string =>
    `(${actor} is null or coalesce(better_supabase.member_can(${actor}, ${tenant}, ${key}), false))`;
  const tenant = ctx.of("tenant");
  const m = tenant.table("memberships");
  const mt = tenant.col("memberships", "tenant");
  const mu = tenant.col("memberships", "user");
  const mr = tenant.col("memberships", "role");
  const roleName = roleNameOf(tenant, "mm");
  const assignable = `array[${roles.order.map(sqlString).join(", ")}]::text[]`;
  const groupValues =
    roles.groups.length === 0
      ? "select null::text as name, null::text as role where false"
      : `values ${roles.groups.map(([name, role]) => `(${sqlString(name)}, ${sqlString(role)})`).join(", ")}`;
  const recordName = (domain: string): string =>
    `${sqlString(`${prefix}.`)} || ${domain}`;
  const withRecord = (row: string): string =>
    `to_jsonb(${row}) - ${sqlString(ctx.col("domains", "token").replaceAll('"', ""))} || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', ${recordName(`${row}.${cd("domain")}`)}, 'value', 'better-supabase-domain-verification=' || ${row}.${cd("token")}))`;
  const memberEvent = (type: string, extra = ""): string =>
    ctx.emit({
      type,
      payload: `jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user${extra})`,
      subject: "'organizations/' || v_tenant::text",
      tenant: "v_tenant",
    }) || "null;";
  const domainEvent = ctx.emit({
    type: "organization.domain_verified",
    payload: `jsonb_build_object('organizationId', v_row.${cd("tenant")}::text, 'domain', v_row.${cd("domain")}, 'userId', verify_organization_domain.actor)`,
    subject: `'organizations/' || v_row.${cd("tenant")}::text`,
    tenant: `v_row.${cd("tenant")}`,
  });
  const emailDomain = (email: string): string =>
    `lower(split_part(${email}, '@', 2))`;
  const verifiedFor = (tenantExpr: string, email: string): string =>
    `exists (select 1 from ${d} vd where vd.${cd("tenant")} = ${tenantExpr} and vd.${cd("verifiedAt")} is not null and vd.${cd("domain")} = ${emailDomain(email)})`;
  const serviceOnly = (what: string): string => `if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role ${what}' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;`;

  const names: ScimSqlNames = {
    id,
    fn,
    users: u,
    groups: g,
    members: gm,
    cu,
    cg,
    cm,
    serviceOnly,
    verifiedFor,
  };

  return `${schemaPreamble(ctx)}
grant usage on schema better_supabase to supabase_auth_admin;

-- Email domains an organization claims. A domain is verified once a DNS TXT
-- record ${prefix}.<domain> holds its token; one organization holds each
-- verified domain.
create table if not exists ${d} (
  ${cd("id")} uuid primary key default gen_random_uuid(),
  ${cd("tenant")} ${id} not null,
  ${cd("domain")} text not null check (${cd("domain")} ~ ${sqlString(DOMAIN)}),
  ${cd("token")} text not null default replace(gen_random_uuid()::text, '-', ''),
  ${cd("verifiedAt")} timestamptz,
  ${cd("autoJoinRole")} text check (${cd("autoJoinRole")} = any (${assignable})),
  ${cd("enforceSso")} boolean not null default false,
  ${cd("createdBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${cd("createdAt")} timestamptz not null default now(),
  unique (${cd("tenant")}, ${cd("domain")}),
  check (not ${cd("enforceSso")} or ${cd("verifiedAt")} is not null)
);
create unique index if not exists organization_domains_verified_idx on ${d} (${cd("domain")}) where ${cd("verifiedAt")} is not null;
alter table ${d} enable row level security;
revoke all on ${d} from anon, authenticated;
grant all on ${d} to service_role;

-- SAML identity providers registered with Supabase Auth for an organization.
create table if not exists ${p} (
  ${cp("id")} uuid primary key,
  ${cp("tenant")} ${id} not null,
  ${cp("type")} text not null default 'saml' check (${cp("type")} = 'saml'),
  ${cp("metadataUrl")} text,
  ${cp("domains")} text[] not null default '{}',
  ${cp("createdAt")} timestamptz not null default now()
);
create index if not exists organization_sso_providers_tenant_idx on ${p} (${cp("tenant")});
alter table ${p} enable row level security;
revoke all on ${p} from anon, authenticated;
grant all on ${p} to service_role;

-- SCIM 2.0 users and groups per organization, written by the SCIM handler.
-- A user links to an account whose confirmed email is at a verified domain
-- of the organization; groups map to roles.
create table if not exists ${u} (
  ${cu("id")} uuid primary key default gen_random_uuid(),
  ${cu("tenant")} ${id} not null,
  ${cu("user")} uuid references auth.users (id) on delete set null,
  ${cu("externalId")} text,
  ${cu("userName")} text not null check (length(${cu("userName")}) between 1 and 320),
  ${cu("displayName")} text,
  ${cu("givenName")} text,
  ${cu("familyName")} text,
  ${cu("email")} text,
  ${cu("emails")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${cu("emails")}) = 'array'),
  ${cu("active")} boolean not null default true,
  ${cu("version")} integer not null default 1,
  ${cu("createdAt")} timestamptz not null default now(),
  ${cu("updatedAt")} timestamptz not null default now()
);
create unique index if not exists scim_users_user_name_idx on ${u} (${cu("tenant")}, lower(${cu("userName")}));
create unique index if not exists scim_users_external_id_idx on ${u} (${cu("tenant")}, ${cu("externalId")}) where ${cu("externalId")} is not null;
create unique index if not exists scim_users_user_idx on ${u} (${cu("tenant")}, ${cu("user")}) where ${cu("user")} is not null;
create index if not exists scim_users_email_idx on ${u} (${cu("email")}) where ${cu("user")} is null;
alter table ${u} enable row level security;
revoke all on ${u} from anon, authenticated;
grant all on ${u} to service_role;

create table if not exists ${g} (
  ${cg("id")} uuid primary key default gen_random_uuid(),
  ${cg("tenant")} ${id} not null,
  ${cg("displayName")} text not null check (length(${cg("displayName")}) between 1 and 256),
  ${cg("externalId")} text,
  ${cg("role")} text,
  ${cg("version")} integer not null default 1,
  ${cg("createdAt")} timestamptz not null default now(),
  ${cg("updatedAt")} timestamptz not null default now()
);
create unique index if not exists scim_groups_display_name_idx on ${g} (${cg("tenant")}, lower(${cg("displayName")}));
create unique index if not exists scim_groups_external_id_idx on ${g} (${cg("tenant")}, ${cg("externalId")}) where ${cg("externalId")} is not null;
alter table ${g} enable row level security;
revoke all on ${g} from anon, authenticated;
grant all on ${g} to service_role;

create table if not exists ${gm} (
  ${cm("group")} uuid not null references ${g} (${cg("id")}) on delete cascade,
  ${cm("member")} uuid not null references ${u} (${cu("id")}) on delete cascade,
  primary key (${cm("group")}, ${cm("member")})
);
create index if not exists scim_group_members_member_idx on ${gm} (${cm("member")});
alter table ${gm} enable row level security;
revoke all on ${gm} from anon, authenticated;
grant all on ${gm} to service_role;

-- The role a SCIM group grants: groupRoles by name, else a group named
-- like an assignable role, else none.
create or replace function ${fn("scim_group_role")}(display_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    (select t.role from (${groupValues}) as t(name, role) where t.name = lower(scim_group_role.display_name)),
    case when lower(scim_group_role.display_name) = any (${assignable}) then lower(scim_group_role.display_name) end
  )
$$;

-- Brings one SCIM user's membership in line: removed when inactive, else
-- the highest role of its groups (roleOrder) or defaultRole. Owners are
-- never changed.
create or replace function ${fn("scim_sync_member")}(scim_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${u};
  v_tenant ${id};
  v_user uuid;
  v_current text;
  v_role text;
begin
  select * into v_row from ${u} x where x.${cu("id")} = scim_sync_member.scim_user;
  if v_row.${cu("user")} is null then
    return;
  end if;
  v_tenant := v_row.${cu("tenant")};
  v_user := v_row.${cu("user")};
  select ${roleName} into v_current from ${m} mm where mm.${mt} = v_tenant and mm.${mu} = v_user;
  if v_current = ${sqlString(roles.owner)} then
    return;
  end if;
  if not v_row.${cu("active")} then
    delete from ${m} mm where mm.${mt} = v_tenant and mm.${mu} = v_user;
    if found then
      ${memberEvent("organization.member_removed")}
    end if;
    return;
  end if;
  select coalesce((
    select sg.${cg("role")} from ${gm} sm join ${g} sg on sg.${cg("id")} = sm.${cm("group")}
    where sm.${cm("member")} = v_row.${cu("id")} and sg.${cg("role")} is not null
    order by array_position(${assignable}, sg.${cg("role")})
    limit 1
  ), ${sqlString(roles.fallback)}) into v_role;
  if v_current is null then
    insert into ${m} (${mt}, ${mu}, ${mr}) values (v_tenant, v_user, ${roleValue(ctx, "v_role")});
    ${memberEvent("organization.member_added", ", 'role', v_role")}
  elsif v_current is distinct from v_role then
    update ${m} mm set ${mr} = ${roleValue(ctx, "v_role")} where mm.${mt} = v_tenant and mm.${mu} = v_user;
    ${memberEvent("organization.role_changed", ", 'role', v_role, 'previousRole', v_current")}
  end if;
end;
$$;

-- Claims a domain for the organization (needs the manage permission).
-- Returns it with the TXT record to publish; adding it again returns it.
create or replace function ${fn("add_organization_domain")}(tenant ${id}, domain text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${d};
  v_domain text := lower(trim(trailing '.' from trim(add_organization_domain.domain)));
begin
  if not ${can("add_organization_domain.tenant")} then
    raise exception 'You may not manage this organization''s domains' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  if v_domain !~ ${sqlString(DOMAIN)} then
    raise exception 'Not a domain name: %', add_organization_domain.domain using errcode = '22023', hint = 'SSO_DOMAIN_INVALID';
  end if;
  insert into ${d} as x (${cd("tenant")}, ${cd("domain")}) values (add_organization_domain.tenant, v_domain)
  on conflict (${cd("tenant")}, ${cd("domain")}) do update set ${cd("domain")} = x.${cd("domain")}
  returning * into v_row;
  return ${withRecord("v_row")};
end;
$$;

create or replace function ${fn("list_organization_domains")}(tenant ${id})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER}) and not ${can("list_organization_domains.tenant")} then
    raise exception 'You may not manage this organization''s domains' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(${withRecord("x")} order by x.${cd("domain")}), '[]'::jsonb)
    from ${d} x where x.${cd("tenant")} = list_organization_domains.tenant
  );
end;
$$;

-- One domain with its record, for the service role or a manager.
create or replace function ${fn("organization_domain")}(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${d};
begin
  select * into v_row from ${d} x where x.${cd("id")} = organization_domain.id;
  if v_row.${cd("id")} is null or not (${SERVICE_CALLER} or ${can(`v_row.${cd("tenant")}`)}) then
    return null;
  end if;
  return ${withRecord("v_row")};
end;
$$;

-- Auto-join role and SSO enforcement for a domain; enforcing needs it verified.
create or replace function ${fn("update_organization_domain")}(id uuid, auto_join_role text default null, enforce_sso boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${d};
begin
  select * into v_row from ${d} x where x.${cd("id")} = update_organization_domain.id for update;
  if v_row.${cd("id")} is null or not ${can(`v_row.${cd("tenant")}`)} then
    raise exception 'No domain you manage has this id' using errcode = 'P0002', hint = 'SSO_DOMAIN_NOT_FOUND';
  end if;
  if update_organization_domain.auto_join_role is not null and not (update_organization_domain.auto_join_role = any (${assignable})) then
    raise exception 'Auto-join cannot assign role %', update_organization_domain.auto_join_role using errcode = '22023', hint = 'SSO_ROLE_INVALID';
  end if;
  if (update_organization_domain.enforce_sso or update_organization_domain.auto_join_role is not null) and v_row.${cd("verifiedAt")} is null then
    raise exception 'Verify the domain first' using errcode = '22023', hint = 'SSO_DOMAIN_NOT_VERIFIED';
  end if;
  update ${d} x set ${cd("autoJoinRole")} = update_organization_domain.auto_join_role, ${cd("enforceSso")} = update_organization_domain.enforce_sso
  where x.${cd("id")} = v_row.${cd("id")}
  returning * into v_row;
  return ${withRecord("v_row")};
end;
$$;

create or replace function ${fn("remove_organization_domain")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${d};
begin
  select * into v_row from ${d} x where x.${cd("id")} = remove_organization_domain.id;
  if v_row.${cd("id")} is null or not (${SERVICE_CALLER} or ${can(`v_row.${cd("tenant")}`)}) then
    return false;
  end if;
  if exists (select 1 from ${p} sp where sp.${cp("tenant")} = v_row.${cd("tenant")} and v_row.${cd("domain")} = any (sp.${cp("domains")})) then
    raise exception 'An SSO provider uses this domain; remove it first' using errcode = '23503', hint = 'SSO_DOMAIN_IN_USE';
  end if;
  delete from ${d} x where x.${cd("id")} = v_row.${cd("id")};
  return true;
end;
$$;

-- Marks a domain verified once the app has found its TXT record (service
-- role). \`actor\`, when set, must hold the manage permission.
create or replace function ${fn("verify_organization_domain")}(id uuid, actor uuid default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${d};
begin
  ${serviceOnly("verifies domains")}
  select * into v_row from ${d} x where x.${cd("id")} = verify_organization_domain.id for update;
  if v_row.${cd("id")} is null or not ${actorCan(`v_row.${cd("tenant")}`, "verify_organization_domain.actor")} then
    raise exception 'No domain you manage has this id' using errcode = 'P0002', hint = 'SSO_DOMAIN_NOT_FOUND';
  end if;
  if v_row.${cd("verifiedAt")} is not null then
    return ${withRecord("v_row")};
  end if;
  if exists (select 1 from ${d} x where x.${cd("domain")} = v_row.${cd("domain")} and x.${cd("verifiedAt")} is not null) then
    raise exception 'Another organization has verified %', v_row.${cd("domain")} using errcode = '23505', hint = 'SSO_DOMAIN_TAKEN';
  end if;
  update ${d} x set ${cd("verifiedAt")} = now() where x.${cd("id")} = v_row.${cd("id")} returning * into v_row;
  ${domainEvent}
  return ${withRecord("v_row")};
end;
$$;

-- Checks that \`actor\` may register a provider for these domains: all
-- verified and owned by the tenant (service role).
create or replace function ${fn("check_sso_provider")}(tenant ${id}, domains text[], actor uuid default null)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("registers SSO providers")}
  if not ${actorCan("check_sso_provider.tenant", "check_sso_provider.actor")} then
    raise exception 'You may not manage this organization''s SSO' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  if cardinality(check_sso_provider.domains) = 0 or exists (
    select 1 from unnest(check_sso_provider.domains) as w(domain)
    where not exists (
      select 1 from ${d} x where x.${cd("tenant")} = check_sso_provider.tenant and x.${cd("domain")} = lower(w.domain) and x.${cd("verifiedAt")} is not null
    )
  ) then
    raise exception 'Every SSO domain must be a verified domain of the organization' using errcode = '22023', hint = 'SSO_DOMAIN_NOT_VERIFIED';
  end if;
end;
$$;

-- Records a provider created in Supabase Auth (service role).
create or replace function ${fn("register_sso_provider")}(tenant ${id}, provider uuid, domains text[], metadata_url text default null, actor uuid default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${p};
begin
  perform ${fn("check_sso_provider")}(register_sso_provider.tenant, register_sso_provider.domains, register_sso_provider.actor);
  insert into ${p} as x (${cp("id")}, ${cp("tenant")}, ${cp("metadataUrl")}, ${cp("domains")})
  values (register_sso_provider.provider, register_sso_provider.tenant, register_sso_provider.metadata_url,
    (select array_agg(distinct lower(w.domain) order by lower(w.domain)) from unnest(register_sso_provider.domains) as w(domain)))
  on conflict (${cp("id")}) do update set ${cp("metadataUrl")} = excluded.${cp("metadataUrl")}, ${cp("domains")} = excluded.${cp("domains")}
  where x.${cp("tenant")} = excluded.${cp("tenant")}
  returning * into v_row;
  if v_row.${cp("id")} is null then
    raise exception 'The provider belongs to another organization' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- One provider (service role), or null; \`actor\`, when set, must hold the
-- manage permission in its organization.
create or replace function ${fn("sso_provider")}(provider uuid, actor uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row ${p};
begin
  ${serviceOnly("registers SSO providers")}
  select * into v_row from ${p} x where x.${cp("id")} = sso_provider.provider;
  if v_row.${cp("id")} is null then
    return null;
  end if;
  if not ${actorCan(`v_row.${cp("tenant")}`, "sso_provider.actor")} then
    raise exception 'You may not manage this organization''s SSO' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Forgets a provider (service role). Returns it, or null.
create or replace function ${fn("unregister_sso_provider")}(provider uuid, actor uuid default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${p};
begin
  ${serviceOnly("registers SSO providers")}
  select * into v_row from ${p} x where x.${cp("id")} = unregister_sso_provider.provider;
  if v_row.${cp("id")} is null then
    return null;
  end if;
  if not ${actorCan(`v_row.${cp("tenant")}`, "unregister_sso_provider.actor")} then
    raise exception 'You may not manage this organization''s SSO' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  delete from ${p} x where x.${cp("id")} = v_row.${cp("id")};
  return to_jsonb(v_row);
end;
$$;

create or replace function ${fn("list_sso_providers")}(tenant ${id})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER}) and not ${can("list_sso_providers.tenant")} then
    raise exception 'You may not manage this organization''s SSO' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x.*) order by x.${cp("createdAt")}), '[]'::jsonb)
    from ${p} x where x.${cp("tenant")} = list_sso_providers.tenant
  );
end;
$$;

-- The SSO provider for an email address, for the sign-in page: null unless
-- its domain is verified and has a provider.
create or replace function ${fn("sso_domain_for")}(email text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'domain', x.${cd("domain")},
    'organizationId', x.${cd("tenant")}::text,
    'providerId', sp.${cp("id")},
    'enforceSso', x.${cd("enforceSso")}
  )
  from ${d} x
  join ${p} sp on sp.${cp("tenant")} = x.${cd("tenant")} and x.${cd("domain")} = any (sp.${cp("domains")})
  where x.${cd("verifiedAt")} is not null
    and x.${cd("domain")} = ${emailDomain("sso_domain_for.email")}
  limit 1
$$;

-- Call from the custom access token hook. Returns the event unchanged, or
-- an error when the user's email domain enforces SSO and the session did
-- not sign in with SAML:
--   result := better_supabase.sso_access_token_check(event);
--   if result ? 'error' then return result; end if;
create or replace function ${fn("sso_access_token_check")}(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_email text;
begin
  select au.email into v_email from auth.users au where au.id = (sso_access_token_check.event ->> 'user_id')::uuid;
  if v_email is null or not exists (
    select 1 from ${d} x
    where x.${cd("verifiedAt")} is not null and x.${cd("enforceSso")} and x.${cd("domain")} = ${emailDomain("v_email")}
  ) then
    return sso_access_token_check.event;
  end if;
  if sso_access_token_check.event ->> 'authentication_method' = 'sso/saml'
    or exists (
      select 1 from jsonb_array_elements(coalesce(sso_access_token_check.event -> 'claims' -> 'amr', '[]'::jsonb)) a(entry)
      where a.entry ->> 'method' = 'sso/saml'
    ) then
    return sso_access_token_check.event;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 403,
    'message', 'Sign in with your organization''s single sign-on'
  ));
end;
$$;

-- On a confirmed email: links waiting SCIM users of organizations that
-- verified the domain, then adds the user to organizations whose domain
-- auto-joins. A failure warns instead of aborting the sign-up.
create or replace function ${fn("sso_on_auth_user")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scim record;
  v_join record;
  v_tenant ${id};
  v_user uuid := new.id;
begin
  if new.email is null or new.email_confirmed_at is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.email is not distinct from new.email and old.email_confirmed_at is not null then
    return new;
  end if;
  begin
    for v_scim in
      update ${u} x set ${cu("user")} = new.id
      where x.${cu("user")} is null and x.${cu("email")} = lower(new.email)
        and ${verifiedFor(`x.${cu("tenant")}`, "new.email")}
        and not exists (select 1 from ${u} y where y.${cu("tenant")} = x.${cu("tenant")} and y.${cu("user")} = new.id)
      returning x.${cu("id")} as id
    loop
      perform ${fn("scim_sync_member")}(v_scim.id);
    end loop;
    for v_join in
      select x.${cd("tenant")} as tenant, x.${cd("autoJoinRole")} as role from ${d} x
      where x.${cd("verifiedAt")} is not null and x.${cd("autoJoinRole")} is not null
        and x.${cd("domain")} = ${emailDomain("new.email")}
        and not exists (select 1 from ${u} y where y.${cu("tenant")} = x.${cd("tenant")} and y.${cu("user")} = new.id)
        and not exists (select 1 from ${m} mm where mm.${mt} = x.${cd("tenant")} and mm.${mu} = new.id)
    loop
      v_tenant := v_join.tenant;
      insert into ${m} (${mt}, ${mu}, ${mr}) values (v_tenant, v_user, ${roleValue(ctx, "v_join.role")});
      ${memberEvent("organization.member_added", ", 'role', v_join.role")}
    end loop;
  exception when others then
    raise warning 'SSO membership for user % failed: % (SQLSTATE %)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
drop trigger if exists ${ctx.trigger("sso_auth_user")} on auth.users;
create trigger ${ctx.trigger("sso_auth_user")} after insert or update of email, email_confirmed_at on auth.users
  for each row execute function ${fn("sso_on_auth_user")}();

${scimSql(names)}
revoke execute on function ${fn("scim_group_role")}(text) from public, anon, authenticated;
revoke execute on function ${fn("scim_sync_member")}(uuid) from public, anon, authenticated;
revoke execute on function ${fn("sso_on_auth_user")}() from public, anon, authenticated;
revoke execute on function ${fn("add_organization_domain")}(${id}, text) from public, anon;
revoke execute on function ${fn("list_organization_domains")}(${id}) from public, anon;
revoke execute on function ${fn("organization_domain")}(uuid) from public, anon;
revoke execute on function ${fn("update_organization_domain")}(uuid, text, boolean) from public, anon;
revoke execute on function ${fn("remove_organization_domain")}(uuid) from public, anon;
revoke execute on function ${fn("verify_organization_domain")}(uuid, uuid) from public, anon, authenticated;
revoke execute on function ${fn("check_sso_provider")}(${id}, text[], uuid) from public, anon, authenticated;
revoke execute on function ${fn("register_sso_provider")}(${id}, uuid, text[], text, uuid) from public, anon, authenticated;
revoke execute on function ${fn("sso_provider")}(uuid, uuid) from public, anon, authenticated;
revoke execute on function ${fn("unregister_sso_provider")}(uuid, uuid) from public, anon, authenticated;
revoke execute on function ${fn("list_sso_providers")}(${id}) from public, anon;
revoke execute on function ${fn("sso_domain_for")}(text) from public;
revoke execute on function ${fn("sso_access_token_check")}(jsonb) from public, anon, authenticated;
revoke execute on function ${fn("scim_list_users")}(${id}) from public, anon, authenticated;
revoke execute on function ${fn("scim_get_user")}(${id}, uuid) from public, anon, authenticated;
revoke execute on function ${fn("scim_save_user")}(${id}, uuid, jsonb, integer) from public, anon, authenticated;
revoke execute on function ${fn("scim_delete_user")}(${id}, uuid) from public, anon, authenticated;
revoke execute on function ${fn("scim_list_groups")}(${id}) from public, anon, authenticated;
revoke execute on function ${fn("scim_get_group")}(${id}, uuid) from public, anon, authenticated;
revoke execute on function ${fn("scim_save_group")}(${id}, uuid, jsonb, integer) from public, anon, authenticated;
revoke execute on function ${fn("scim_delete_group")}(${id}, uuid) from public, anon, authenticated;
grant execute on function ${fn("scim_group_role")}(text) to service_role;
grant execute on function ${fn("scim_sync_member")}(uuid) to service_role;
grant execute on function ${fn("add_organization_domain")}(${id}, text) to authenticated, service_role;
grant execute on function ${fn("list_organization_domains")}(${id}) to authenticated, service_role;
grant execute on function ${fn("organization_domain")}(uuid) to authenticated, service_role;
grant execute on function ${fn("update_organization_domain")}(uuid, text, boolean) to authenticated, service_role;
grant execute on function ${fn("remove_organization_domain")}(uuid) to authenticated, service_role;
grant execute on function ${fn("verify_organization_domain")}(uuid, uuid) to service_role;
grant execute on function ${fn("check_sso_provider")}(${id}, text[], uuid) to service_role;
grant execute on function ${fn("register_sso_provider")}(${id}, uuid, text[], text, uuid) to service_role;
grant execute on function ${fn("sso_provider")}(uuid, uuid) to service_role;
grant execute on function ${fn("unregister_sso_provider")}(uuid, uuid) to service_role;
grant execute on function ${fn("list_sso_providers")}(${id}) to authenticated, service_role;
grant execute on function ${fn("sso_domain_for")}(text) to anon, authenticated, service_role;
grant execute on function ${fn("sso_access_token_check")}(jsonb) to service_role, supabase_auth_admin;
grant execute on function ${fn("scim_list_users")}(${id}) to service_role;
grant execute on function ${fn("scim_get_user")}(${id}, uuid) to service_role;
grant execute on function ${fn("scim_save_user")}(${id}, uuid, jsonb, integer) to service_role;
grant execute on function ${fn("scim_delete_user")}(${id}, uuid) to service_role;
grant execute on function ${fn("scim_list_groups")}(${id}) to service_role;
grant execute on function ${fn("scim_get_group")}(${id}, uuid) to service_role;
grant execute on function ${fn("scim_save_group")}(${id}, uuid, jsonb, integer) to service_role;
grant execute on function ${fn("scim_delete_group")}(${id}, uuid) to service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "scim_group_role", args: ["text"], returns: "text" },
    { name: "scim_sync_member", args: ["uuid"], returns: "void" },
    {
      name: "add_organization_domain",
      args: ["{id}", "text"],
      returns: "jsonb",
    },
    { name: "list_organization_domains", args: ["{id}"], returns: "jsonb" },
    { name: "organization_domain", args: ["uuid"], returns: "jsonb" },
    {
      name: "update_organization_domain",
      args: ["uuid", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "remove_organization_domain", args: ["uuid"], returns: "boolean" },
    {
      name: "verify_organization_domain",
      args: ["uuid", "uuid"],
      returns: "jsonb",
    },
    {
      name: "check_sso_provider",
      args: ["{id}", "text[]", "uuid"],
      returns: "void",
    },
    {
      name: "register_sso_provider",
      args: ["{id}", "uuid", "text[]", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "sso_provider", args: ["uuid", "uuid"], returns: "jsonb" },
    {
      name: "unregister_sso_provider",
      args: ["uuid", "uuid"],
      returns: "jsonb",
    },
    { name: "list_sso_providers", args: ["{id}"], returns: "jsonb" },
    { name: "sso_domain_for", args: ["text"], returns: "jsonb" },
    { name: "sso_access_token_check", args: ["jsonb"], returns: "jsonb" },
    { name: "sso_on_auth_user", args: [], returns: "trigger" },
    { name: "scim_list_users", args: ["{id}"], returns: "jsonb" },
    { name: "scim_get_user", args: ["{id}", "uuid"], returns: "jsonb" },
    {
      name: "scim_save_user",
      args: ["{id}", "uuid", "jsonb", "integer"],
      returns: "jsonb",
    },
    { name: "scim_delete_user", args: ["{id}", "uuid"], returns: "boolean" },
    { name: "scim_list_groups", args: ["{id}"], returns: "jsonb" },
    { name: "scim_get_group", args: ["{id}", "uuid"], returns: "jsonb" },
    {
      name: "scim_save_group",
      args: ["{id}", "uuid", "jsonb", "integer"],
      returns: "jsonb",
    },
    { name: "scim_delete_group", args: ["{id}", "uuid"], returns: "boolean" },
  ];
}

export const SSO: ModuleDefinition = {
  name: "sso",
  title: "SSO and SCIM",
  description:
    "Verified email domains with auto-join and SSO enforcement, SAML providers per organization registered with Supabase Auth, and SCIM 2.0 users and groups that provision memberships and map groups to roles.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
