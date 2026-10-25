import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { ScimSqlNames } from "./sso-scim-sql.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  memberAddedRecord,
  SERVICE_CALLER,
  schemaPreamble,
  lockTable,
  fail,
  raise,
} from "../shared.ts";
import { roleNameOf } from "./memberships.ts";
import { roleValue } from "./organizations-roles.ts";
import {
  accessModel,
  moduleOperations,
  roleNames,
} from "./permissions-model.ts";
import { NAMES } from "./sso-names.ts";
import {
  appRowJson,
  SCIM_SYNC_LOG_CONTRACT,
  scimSql,
  scimSyncLogSql,
} from "./sso-scim-sql.ts";

const PREFIX = /^_[a-z0-9][a-z0-9-]{0,61}$/;
const DOMAIN = "^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$";

interface Roles {
  readonly owner: string;
  /** Roles SCIM and auto-join may assign, highest first. */
  readonly order: readonly string[];
  readonly fallback: string;
  readonly groups: readonly (readonly [string, string])[];
}

function rolesFor(ctx: BlockSqlContext): Roles {
  const model = accessModel(ctx);
  const listed = model === "roles" || model === "catalog";

  if (!listed && ctx.option("roleOrder") === undefined) {
    throw new TypeError(
      `blocks.sso assigns membership roles. Under blocks.permissions.model "${model}" the roles are not in the config, so list the roles SCIM and auto-join may assign in blocks.sso.options.roleOrder, highest first`,
    );
  }

  const owner = ctx.installed("organizations")
    ? ctx.of("organizations").text("ownerRole", "owner")
    : "owner";

  const order = ctx.list(
    "roleOrder",
    listed ? roleNames(ctx).filter((role) => role !== owner) : [],
  );

  if (order.includes(owner)) {
    throw new TypeError(
      `blocks.sso.options.roleOrder must not include the owner role "${owner}"`,
    );
  }

  const fallback = ctx.text("defaultRole", "member");
  const where = "blocks.sso.options";

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

function prefixOf(ctx: BlockSqlContext): string {
  const prefix = ctx.text("txtPrefix", "_better-supabase");

  if (!PREFIX.test(prefix)) {
    throw new TypeError(
      "blocks.sso.options.txtPrefix must start with an underscore and hold lowercase letters, digits or dashes",
    );
  }

  return prefix;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

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
  const permissions = moduleOperations("sso");
  const key = ctx.permission("manage", permissions.manage);
  const can = (tenant: string): string => ctx.can("tenant", tenant, key);

  const actorCan = (tenant: string, actor: string): string =>
    `(${actor} is null or ${ctx.scope.canUser(actor, tenant, key)})`;

  const tenant = ctx.of("memberships");
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

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const line = (table: string, column: string, type: string): string =>
    has(table, column) ? `  ${ctx.col(table, column)} ${type},\n` : "";

  const ownKey = (table: string, name: string, columns: string): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(ctx.naming.rename(name))} on ${ctx.table(table)} (${columns});`;

  const domainJson = (row: string): string =>
    ctx.owns("domains")
      ? `to_jsonb(${row}) - ${sqlString(ctx.col("domains", "token").replaceAll('"', ""))}`
      : appRowJson(ctx, "domains", row, {}, ["token"]);

  const providerJson = (row: string, whole = row): string =>
    ctx.owns("providers")
      ? `to_jsonb(${whole})`
      : appRowJson(ctx, "providers", row, {}, []);

  const provided: [string, string][] = [
    ["id", "register_sso_provider.provider"],
    ["tenant", "register_sso_provider.tenant"],
  ];

  if (!ctx.owns("providers")) {
    provided.push(["type", ctx.cast("providers", "type", "'saml'")]);
  }

  if (has("providers", "metadataUrl")) {
    provided.push(["metadataUrl", "register_sso_provider.metadata_url"]);
  }

  const providerColumns = [...provided.map(([column]) => column), "domains"]
    .map(cp)
    .join(", ");

  const providerValues = provided.map(([, value]) => value).join(", ");

  const providerSet = ["metadataUrl", "domains"]
    .filter((column) => has("providers", column))
    .map((column) => `${cp(column)} = excluded.${cp(column)}`)
    .join(", ");

  const scimMissing = (
    table: "scimUsers" | "scimGroups",
    alias: string,
  ): Record<string, string> => ({
    updatedAt: `${alias}.${ctx.col(table, "createdAt")}`,
  });

  const asText = (table: string, value: string): string =>
    ctx.owns(table) ? value : `${value}::text`;

  const withRecord = (row: string): string =>
    `${domainJson(row)} || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', ${recordName(`${row}.${cd("domain")}`)}, 'value', 'better-supabase-domain-verification=' || ${row}.${cd("token")}))`;

  const memberEvent = (type: string, extra = ""): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user${extra})`,
      subject: "'organizations/' || v_tenant::text",
      tenant: "v_tenant",
      audit: {
        category: "membership",
        targetType: "user",
        recordId: "v_user::text",
      },
    });

  const domainEvent = (type: string, actor: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${cd("tenant")}::text, 'domainId', v_row.${cd("id")}, 'domain', v_row.${cd("domain")}, 'userId', ${actor})`,
      subject: `'organizations/' || v_row.${cd("tenant")}::text`,
      tenant: `v_row.${cd("tenant")}`,
      audit: {
        category: "security",
        targetType: "domain",
        recordId: `v_row.${cd("id")}::text`,
        targetLabel: `v_row.${cd("domain")}`,
        actor,
      },
    });

  const providerEvent = (type: string, actor: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${cp("tenant")}::text, 'providerId', v_row.${cp("id")}, 'domains', to_jsonb(v_row.${cp("domains")}), 'userId', ${actor})`,
      subject: `'organizations/' || v_row.${cp("tenant")}::text`,
      tenant: `v_row.${cp("tenant")}`,
      audit: {
        category: "security",
        targetType: "sso_provider",
        recordId: `v_row.${cp("id")}::text`,
        actor,
      },
    });

  const emailDomain = (email: string): string =>
    `lower(split_part(${email}, '@', 2))`;

  const verifiedFor = (tenantExpr: string, email: string): string =>
    `exists (select 1 from ${d} vd where vd.${cd("tenant")} = ${tenantExpr} and vd.${cd("verifiedAt")} is not null and vd.${cd("domain")} = ${emailDomain(email)})`;

  const serviceOnly = (what: string): string => `if not (${SERVICE_CALLER}) then
    ${fail("SSO_FORBIDDEN", `Only the service role ${what}`)}
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
    has,
    role: (value) => ctx.cast("scimGroups", "role", value),
    row: (table, alias) =>
      ctx.owns(table)
        ? `to_jsonb(${alias}.*)`
        : appRowJson(ctx, table, alias, scimMissing(table, alias), []),
    record: (type, tenantId, row) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${tenantId}::text, ${sqlString(type.startsWith("scim_user.") ? "scimUserId" : "scimGroupId")}, ${row})`,
        subject: `'organizations/' || ${tenantId}::text`,
        tenant: tenantId,
        audit: {
          category: "security",
          targetType: type.slice(0, type.indexOf(".")),
          recordId: `${row}::text`,
        },
      }),
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
${line("domains", "createdBy", "uuid references auth.users (id) on delete set null default auth.uid()")}${line("domains", "createdAt", "timestamptz not null default now()")}  unique (${cd("tenant")}, ${cd("domain")}),
  check (not ${cd("enforceSso")} or ${cd("verifiedAt")} is not null)
);
create unique index if not exists ${ctx.naming.rename("organization_domains_verified_idx")} on ${d} (${cd("domain")}) where ${cd("verifiedAt")} is not null;
${has("domains", "createdBy") ? `create index if not exists ${ctx.naming.rename("organization_domains_created_by_idx")} on ${d} (${cd("createdBy")}) where ${cd("createdBy")} is not null;\n` : ""}${lockTable(d)}${ownKey("domains", "bsb_organization_domains_tenant_domain_key", `${cd("tenant")}, ${cd("domain")}`)}

-- SAML identity providers registered with Supabase Auth for an organization.
create table if not exists ${p} (
  ${cp("id")} uuid primary key,
  ${cp("tenant")} ${id} not null,
  ${cp("type")} text not null default 'saml' check (${cp("type")} = 'saml'),
${line("providers", "metadataUrl", "text")}  ${cp("domains")} text[] not null default '{}',
  ${cp("createdAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("organization_sso_providers_tenant_idx")} on ${p} (${cp("tenant")});
${lockTable(p)}${ownKey("providers", "bsb_organization_sso_providers_id_key", cp("id"))}

-- SCIM 2.0 users and groups per organization, written by the SCIM handler.
-- A user links to an account whose confirmed email is at a verified domain
-- of the organization; groups map to roles.
create table if not exists ${u} (
  ${cu("id")} uuid primary key default gen_random_uuid(),
  ${cu("tenant")} ${id} not null,
  ${cu("user")} uuid references auth.users (id) on delete set null,
  ${cu("externalId")} text,
  ${cu("userName")} text not null check (length(${cu("userName")}) between 1 and 320),
${line("scimUsers", "displayName", "text")}${line("scimUsers", "givenName", "text")}${line("scimUsers", "familyName", "text")}  ${cu("email")} text,
  ${cu("emails")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${cu("emails")}) = 'array'),
  ${cu("active")} boolean not null default true,
  ${cu("version")} integer not null default 1,
  ${cu("createdAt")} timestamptz not null default now()${has("scimUsers", "updatedAt") ? `,\n  ${cu("updatedAt")} timestamptz not null default now()` : ""}
);
create unique index if not exists scim_users_user_name_idx on ${u} (${cu("tenant")}, lower(${cu("userName")}));
create unique index if not exists scim_users_external_id_idx on ${u} (${cu("tenant")}, ${cu("externalId")}) where ${cu("externalId")} is not null;
create unique index if not exists scim_users_user_idx on ${u} (${cu("tenant")}, ${cu("user")}) where ${cu("user")} is not null;
create index if not exists scim_users_email_idx on ${u} (${cu("email")}) where ${cu("user")} is null;
create index if not exists scim_users_account_idx on ${u} (${cu("user")}) where ${cu("user")} is not null;
${lockTable(u)}

create table if not exists ${g} (
  ${cg("id")} uuid primary key default gen_random_uuid(),
  ${cg("tenant")} ${id} not null,
  ${cg("displayName")} text not null check (length(${cg("displayName")}) between 1 and 256),
  ${cg("externalId")} text,
  ${cg("role")} text,
  ${cg("version")} integer not null default 1,
  ${cg("createdAt")} timestamptz not null default now()${has("scimGroups", "updatedAt") ? `,\n  ${cg("updatedAt")} timestamptz not null default now()` : ""}
);
create unique index if not exists scim_groups_display_name_idx on ${g} (${cg("tenant")}, lower(${cg("displayName")}));
create unique index if not exists scim_groups_external_id_idx on ${g} (${cg("tenant")}, ${cg("externalId")}) where ${cg("externalId")} is not null;
${lockTable(g)}

create table if not exists ${gm} (
  ${cm("group")} uuid not null references ${g} (${cg("id")}) on delete cascade,
  ${cm("member")} uuid not null references ${u} (${cu("id")}) on delete cascade,
  primary key (${cm("group")}, ${cm("member")})
);
create index if not exists scim_group_members_member_idx on ${gm} (${cm("member")});
${lockTable(gm)}${ownKey("scimMembers", "bsb_scim_group_members_key", `${cm("group")}, ${cm("member")}`)}

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
    select ${asText("scimGroups", `sg.${cg("role")}`)} from ${gm} sm join ${g} sg on sg.${cg("id")} = sm.${cm("group")}
    where sm.${cm("member")} = v_row.${cu("id")} and sg.${cg("role")} is not null
    order by array_position(${assignable}, ${asText("scimGroups", `sg.${cg("role")}`)})
    limit 1
  ), ${sqlString(roles.fallback)}) into v_role;
  if v_current is null then
    insert into ${m} (${mt}, ${mu}, ${mr}) values (v_tenant, v_user, ${roleValue(ctx, "v_role", "v_tenant")});
    ${memberAddedRecord(ctx, { tenant: "v_tenant", user: "v_user", role: "v_role" })}
  elsif v_current is distinct from v_role then
    update ${m} mm set ${mr} = ${roleValue(ctx, "v_role", "v_tenant")} where mm.${mt} = v_tenant and mm.${mu} = v_user;
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
    ${fail("SSO_FORBIDDEN", "You may not manage this organization's domains")}
  end if;
  if v_domain !~ ${sqlString(DOMAIN)} then
    ${raise("Not a domain name: %", "22023", "SSO_DOMAIN_INVALID", "add_organization_domain.domain")}
  end if;
  insert into ${d} as x (${cd("tenant")}, ${cd("domain")}) values (add_organization_domain.tenant, v_domain)
  on conflict (${cd("tenant")}, ${cd("domain")}) do update set ${cd("domain")} = x.${cd("domain")}
  returning * into v_row;
  ${domainEvent("organization.domain_added", "auth.uid()")}
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
    ${fail("SSO_FORBIDDEN", "You may not manage this organization's domains")}
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
    ${fail("SSO_DOMAIN_NOT_FOUND", "No domain you manage has this id", "P0002")}
  end if;
  if update_organization_domain.auto_join_role is not null and not (update_organization_domain.auto_join_role = any (${assignable})) then
    ${raise("Auto-join cannot assign role %", "22023", "SSO_ROLE_INVALID", "update_organization_domain.auto_join_role")}
  end if;
  if update_organization_domain.auto_join_role is not null
    and not (${SERVICE_CALLER})
    and not coalesce(better_supabase.can_assign(v_row.${cd("tenant")}, update_organization_domain.auto_join_role), false) then
    ${raise("You may not assign role %", "42501", "SSO_ROLE_FORBIDDEN", "update_organization_domain.auto_join_role")}
  end if;
  if (update_organization_domain.enforce_sso or update_organization_domain.auto_join_role is not null) and v_row.${cd("verifiedAt")} is null then
    ${fail("SSO_DOMAIN_NOT_VERIFIED", "Verify the domain first", "22023")}
  end if;
  update ${d} x set ${cd("autoJoinRole")} = ${ctx.cast("domains", "autoJoinRole", "update_organization_domain.auto_join_role")}, ${cd("enforceSso")} = update_organization_domain.enforce_sso
  where x.${cd("id")} = v_row.${cd("id")}
  returning * into v_row;
  ${domainEvent("organization.domain_updated", "auth.uid()")}
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
    ${fail("SSO_DOMAIN_IN_USE", "An SSO provider uses this domain; remove it first", "23503")}
  end if;
  delete from ${d} x where x.${cd("id")} = v_row.${cd("id")};
  ${domainEvent("organization.domain_removed", "auth.uid()")}
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
    ${fail("SSO_DOMAIN_NOT_FOUND", "No domain you manage has this id", "P0002")}
  end if;
  if v_row.${cd("verifiedAt")} is not null then
    return ${withRecord("v_row")};
  end if;
  if exists (select 1 from ${d} x where x.${cd("domain")} = v_row.${cd("domain")} and x.${cd("verifiedAt")} is not null) then
    ${raise("Another organization has verified %", "23505", "SSO_DOMAIN_TAKEN", `v_row.${cd("domain")}`)}
  end if;
  update ${d} x set ${cd("verifiedAt")} = now() where x.${cd("id")} = v_row.${cd("id")} returning * into v_row;
  ${domainEvent("organization.domain_verified", "verify_organization_domain.actor")}
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
    ${fail("SSO_FORBIDDEN", "You may not manage this organization's SSO")}
  end if;
  if cardinality(check_sso_provider.domains) = 0 or exists (
    select 1 from unnest(check_sso_provider.domains) as w(domain)
    where not exists (
      select 1 from ${d} x where x.${cd("tenant")} = check_sso_provider.tenant and x.${cd("domain")} = lower(w.domain) and x.${cd("verifiedAt")} is not null
    )
  ) then
    ${fail("SSO_DOMAIN_NOT_VERIFIED", "Every SSO domain must be a verified domain of the organization", "22023")}
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
#variable_conflict use_column
declare
  v_row ${p};
begin
  perform ${fn("check_sso_provider")}(register_sso_provider.tenant, register_sso_provider.domains, register_sso_provider.actor);
  insert into ${p} as x (${providerColumns})
  values (${providerValues},
    (select array_agg(distinct lower(w.domain) order by lower(w.domain)) from unnest(register_sso_provider.domains) as w(domain)))
  on conflict (${cp("id")}) do update set ${providerSet}
  where x.${cp("tenant")} = excluded.${cp("tenant")}
  returning * into v_row;
  if v_row.${cp("id")} is null then
    ${fail("SSO_FORBIDDEN", "The provider belongs to another organization")}
  end if;
  ${providerEvent("sso_provider.registered", "register_sso_provider.actor")}
  return ${providerJson("v_row")};
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
    ${fail("SSO_FORBIDDEN", "You may not manage this organization's SSO")}
  end if;
  return ${providerJson("v_row")};
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
    ${fail("SSO_FORBIDDEN", "You may not manage this organization's SSO")}
  end if;
  delete from ${p} x where x.${cp("id")} = v_row.${cp("id")};
  ${providerEvent("sso_provider.unregistered", "unregister_sso_provider.actor")}
  return ${providerJson("v_row")};
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
    ${fail("SSO_FORBIDDEN", "You may not manage this organization's SSO")}
  end if;
  return (
    select coalesce(jsonb_agg(${providerJson("x", "x.*")} order by x.${cp("createdAt")}), '[]'::jsonb)
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
      select x.${cd("tenant")} as tenant, ${asText("domains", `x.${cd("autoJoinRole")}`)} as role from ${d} x
      where x.${cd("verifiedAt")} is not null and x.${cd("autoJoinRole")} is not null
        and x.${cd("domain")} = ${emailDomain("new.email")}
        and not exists (select 1 from ${u} y where y.${cu("tenant")} = x.${cd("tenant")} and y.${cu("user")} = new.id)
        and not exists (select 1 from ${m} mm where mm.${mt} = x.${cd("tenant")} and mm.${mu} = new.id)
    loop
      v_tenant := v_join.tenant;
      insert into ${m} (${mt}, ${mu}, ${mr}) values (v_tenant, v_user, ${roleValue(ctx, "v_join.role", "v_tenant")});
      ${memberAddedRecord(ctx, { tenant: "v_tenant", user: "v_user", role: "v_join.role" })}
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
grant execute on function ${fn("scim_delete_group")}(${id}, uuid) to service_role;${ctx.flag("syncLog", false) ? `\n\n${scimSyncLogSql(ctx, serviceOnly)}` : ""}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    ...(ctx.flag("syncLog", false) ? SCIM_SYNC_LOG_CONTRACT : []),
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

export const SSO: BlockSqlDefinition = {
  name: "sso",
  scopes: ["tenant"],
  title: "SSO and SCIM",
  description:
    "Verified email domains with auto-join and SSO enforcement, SAML providers per organization registered with Supabase Auth, and SCIM 2.0 users and groups that provision memberships and map groups to roles.",
  requires: ["memberships", "permissions"],
  integrates: ["organizations", "data-lifecycle"],
  providerFunctions: ["idsWithFor"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
