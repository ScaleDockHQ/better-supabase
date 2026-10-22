import type { DomainsEvents } from "../../blocks/domains/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  raise,
  SERVICE_CALLER,
  schemaPreamble,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";

const EVENTS: BlockSqlEvents<DomainsEvents> = {
  "hostname.added": {
    subject: "hostnames",
    payload: ["organizationId", "hostnameId", "hostname"],
  },
  "hostname.verified": {
    subject: "hostnames",
    payload: ["organizationId", "hostnameId", "hostname"],
  },
  "hostname.primary_set": {
    subject: "hostnames",
    payload: ["organizationId", "hostnameId", "hostname"],
  },
  "hostname.removed": {
    subject: "hostnames",
    payload: ["organizationId", "hostnameId", "hostname"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["platformDomain", "txtPrefix"],
  hooks: [],
  tables: {
    hostnames: {
      name: "organization_hostnames",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        hostname: "hostname",
        kind: "kind",
        token: "verification_token",
        verifiedAt: "verified_at",
        primary: "is_primary",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

const HOSTNAME = "^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$";
const PREFIX = /^_[a-z0-9-]{1,62}$/;

/** `blocks.domains.options.platformDomain`, lowercased, or `undefined`. */
function platformDomainOf(ctx: BlockSqlContext): string | undefined {
  const value = ctx.text("platformDomain", "").trim().toLowerCase();

  if (value === "") {
    return undefined;
  }

  if (!new RegExp(HOSTNAME).test(value)) {
    throw new TypeError(
      `blocks.domains.options.platformDomain: "${value}" is not a hostname`,
    );
  }

  return value;
}

function prefixOf(ctx: BlockSqlContext): string {
  const prefix = ctx.text("txtPrefix", "_better-supabase");

  if (!PREFIX.test(prefix)) {
    throw new TypeError(
      "blocks.domains.options.txtPrefix must start with an underscore and hold lowercase letters, digits or dashes",
    );
  }

  return prefix;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("hostnames");
  const c = (column: string): string => ctx.col("hostnames", column);
  const keys = moduleOperations("domains");
  const read = ctx.permission("read", keys.read);
  const manage = ctx.permission("manage", keys.manage);

  const can = (tenant: string, key: string): string =>
    ctx.scope.can(tenant, key);

  const platform = platformDomainOf(ctx);
  const prefix = prefixOf(ctx);

  const raw = (column: string): string =>
    sqlString(c(column).replaceAll('"', ""));

  const actorCan = (tenant: string, actor: string): string =>
    `(${actor} is null or ${ctx.scope.canUser(actor, tenant, manage)})`;

  // A verified hostname needs no record; a pending one carries the TXT record to publish.
  const publicRow = (row: string): string =>
    `(to_jsonb(${row}) - ${raw("token")}) || case when ${row}.${c("verifiedAt")} is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', ${sqlString(`${prefix}.`)} || ${row}.${c("hostname")}, 'value', 'better-supabase-hostname-verification=' || ${row}.${c("token")})) else '{}'::jsonb end`;

  const hostnameEvent = (
    type: string,
    row: string,
    actor = "auth.uid()",
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}::text, 'hostnameId', ${row}.${c("id")}::text, 'hostname', ${row}.${c("hostname")})`,
      subject: `'hostnames/' || ${row}.${c("id")}::text`,
      tenant: `${row}.${c("tenant")}`,
      audit: {
        category: "configuration",
        targetType: "hostname",
        recordId: `${row}.${c("id")}::text`,
        targetLabel: `${row}.${c("hostname")}`,
        actor,
      },
    });

  const reservedLabel = ctx.installed("reserved-slugs")
    ? `
      if better_supabase.slug_problem(v_label) is not null then
        ${raise("The subdomain % is reserved or not a slug", "23514", "HOSTNAME_RESERVED", "v_label")}
      end if;`
    : "";

  // Under options.platformDomain, one label below it is a subdomain the
  // platform already controls, so it is verified as soon as it is added.
  const platformCheck =
    platform === undefined
      ? ""
      : `
  if v_hostname = ${sqlString(platform)} then
    ${fail("HOSTNAME_RESERVED", "The platform's own domain can't be added", "23514")}
  end if;
  if right(v_hostname, ${String(platform.length + 1)}) = ${sqlString(`.${platform}`)} then
    v_label := left(v_hostname, length(v_hostname) - ${String(platform.length + 1)});
    if position('.' in v_label) > 0 then
      ${raise("Only one label below the platform domain: %", "22023", "HOSTNAME_INVALID", "v_hostname")}
    end if;${reservedLabel}
    v_kind := 'subdomain';
  end if;`;

  return `${schemaPreamble(ctx)}
-- Hostnames an organization serves its app on: its own domains, verified by a
-- DNS TXT record ${prefix}.<hostname>, and subdomains of
-- ${platform ?? "blocks.domains.options.platformDomain (unset)"}, verified when added. One organization holds
-- each verified hostname, and each organization has at most one primary.
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${id} not null,
  ${c("hostname")} text not null check (length(${c("hostname")}) <= 253 and ${c("hostname")} ~ ${sqlString(HOSTNAME)}),
  ${c("kind")} text not null default 'custom' check (${c("kind")} in ('custom', 'subdomain')),
  ${c("token")} text not null default replace(gen_random_uuid()::text, '-', ''),
  ${c("verifiedAt")} timestamptz,
  ${c("primary")} boolean not null default false,
  ${c("createdBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${c("createdAt")} timestamptz not null default now(),
  unique (${c("tenant")}, ${c("hostname")}),
  check (not ${c("primary")} or ${c("verifiedAt")} is not null)
);
create unique index if not exists ${ctx.naming.rename("organization_hostnames_verified_idx")} on ${t} (${c("hostname")}) where ${c("verifiedAt")} is not null;
create unique index if not exists ${ctx.naming.rename("organization_hostnames_primary_idx")} on ${t} (${c("tenant")}) where ${c("primary")};
create index if not exists ${ctx.naming.rename("organization_hostnames_created_by_idx")} on ${t} (${c("createdBy")}) where ${c("createdBy")} is not null;
${lockTable(t)}

-- Adds a hostname (needs the manage permission). A custom domain comes back
-- with the TXT record to publish; adding it again returns the same row.
create or replace function ${fn("add_hostname")}(tenant ${id}, hostname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (${SERVICE_CALLER} or ${can("add_hostname.tenant", manage)}) then
    ${fail("HOSTNAME_FORBIDDEN", "You may not manage this organization's hostnames")}
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ ${sqlString(HOSTNAME)} then
    ${raise("Not a hostname: %", "22023", "HOSTNAME_INVALID", "add_hostname.hostname")}
  end if;${platformCheck}
  select * into v_row from ${t} x where x.${c("tenant")} = add_hostname.tenant and x.${c("hostname")} = v_hostname;
  if v_row.${c("id")} is not null then
    return ${publicRow("v_row")};
  end if;
  if v_kind = 'subdomain' and exists (select 1 from ${t} x where x.${c("hostname")} = v_hostname and x.${c("verifiedAt")} is not null) then
    ${raise("Another organization holds %", "23505", "HOSTNAME_TAKEN", "v_hostname")}
  end if;
  insert into ${t} (${c("tenant")}, ${c("hostname")}, ${c("kind")}, ${c("verifiedAt")})
  values (add_hostname.tenant, v_hostname, v_kind, case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  ${hostnameEvent("hostname.added", "v_row")}
  if v_row.${c("verifiedAt")} is not null then
    ${hostnameEvent("hostname.verified", "v_row")}
  end if;
  return ${publicRow("v_row")};
exception when unique_violation then
  ${raise("Another organization holds %", "23505", "HOSTNAME_TAKEN", "v_hostname")}
end;
$$;

-- An organization's hostnames, primary first (read permission or the service role).
create or replace function ${fn("list_hostnames")}(tenant ${id})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER} or ${can("list_hostnames.tenant", read)}) then
    ${fail("HOSTNAME_FORBIDDEN", "You may not read this organization's hostnames")}
  end if;
  return (
    select coalesce(jsonb_agg(${publicRow("x")} order by x.${c("primary")} desc, x.${c("hostname")}), '[]'::jsonb)
    from ${t} x where x.${c("tenant")} = list_hostnames.tenant
  );
end;
$$;

-- One hostname with its record, for the service role or a manager; null otherwise.
create or replace function ${fn("hostname_by_id")}(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${c("id")} = hostname_by_id.id;
  if v_row.${c("id")} is null or not (${SERVICE_CALLER} or ${can(`v_row.${c("tenant")}`, manage)}) then
    return null;
  end if;
  return ${publicRow("v_row")};
end;
$$;

-- Marks a hostname verified once the app has found its TXT record (service
-- role only). \`actor\`, when set, must hold the manage permission.
create or replace function ${fn("verify_hostname")}(id uuid, actor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  if not (${SERVICE_CALLER}) then
    ${fail("HOSTNAME_FORBIDDEN", "Only the service role verifies hostnames")}
  end if;
  select * into v_row from ${t} x where x.${c("id")} = verify_hostname.id for update;
  if v_row.${c("id")} is null or not ${actorCan(`v_row.${c("tenant")}`, "verify_hostname.actor")} then
    ${fail("HOSTNAME_NOT_FOUND", "No hostname you manage has this id", "P0002")}
  end if;
  if v_row.${c("verifiedAt")} is not null then
    return ${publicRow("v_row")};
  end if;
  if exists (select 1 from ${t} x where x.${c("hostname")} = v_row.${c("hostname")} and x.${c("verifiedAt")} is not null) then
    ${raise("Another organization holds %", "23505", "HOSTNAME_TAKEN", `v_row.${c("hostname")}`)}
  end if;
  update ${t} x set ${c("verifiedAt")} = now() where x.${c("id")} = v_row.${c("id")} returning * into v_row;
  ${hostnameEvent("hostname.verified", "v_row", "verify_hostname.actor")}
  return ${publicRow("v_row")};
end;
$$;

-- Makes a verified hostname the organization's primary, the one other
-- hostnames redirect to.
create or replace function ${fn("set_primary_hostname")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${c("id")} = set_primary_hostname.id for update;
  if v_row.${c("id")} is null or not (${SERVICE_CALLER} or ${can(`v_row.${c("tenant")}`, manage)}) then
    ${fail("HOSTNAME_NOT_FOUND", "No hostname you manage has this id", "P0002")}
  end if;
  if v_row.${c("verifiedAt")} is null then
    ${fail("HOSTNAME_NOT_VERIFIED", "Verify the hostname first", "22023")}
  end if;
  if v_row.${c("primary")} then
    return ${publicRow("v_row")};
  end if;
  update ${t} x set ${c("primary")} = false where x.${c("tenant")} = v_row.${c("tenant")} and x.${c("primary")};
  update ${t} x set ${c("primary")} = true where x.${c("id")} = v_row.${c("id")} returning * into v_row;
  ${hostnameEvent("hostname.primary_set", "v_row")}
  return ${publicRow("v_row")};
end;
$$;

-- Removes a hostname; false when there is none the caller manages.
create or replace function ${fn("remove_hostname")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${c("id")} = remove_hostname.id;
  if v_row.${c("id")} is null or not (${SERVICE_CALLER} or ${can(`v_row.${c("tenant")}`, manage)}) then
    return false;
  end if;
  delete from ${t} x where x.${c("id")} = v_row.${c("id")};
  ${hostnameEvent("hostname.removed", "v_row")}
  return true;
end;
$$;

-- The organization a request's hostname belongs to, for the proxy: null
-- unless the hostname is verified. Open to anon, since the proxy runs before
-- sign-in; it returns nothing a DNS lookup doesn't already show.
create or replace function ${fn("resolve_hostname")}(hostname text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', x.${c("tenant")},
    'hostname', x.${c("hostname")},
    'primary', x.${c("primary")},
    'primaryHostname', (
      select p.${c("hostname")} from ${t} p
      where p.${c("tenant")} = x.${c("tenant")} and p.${c("primary")}
    )
  )
  from ${t} x
  where x.${c("hostname")} = lower(trim(trailing '.' from trim(resolve_hostname.hostname)))
    and x.${c("verifiedAt")} is not null
$$;

revoke execute on function ${fn("add_hostname")}(${id}, text) from public, anon;
revoke execute on function ${fn("list_hostnames")}(${id}) from public, anon;
revoke execute on function ${fn("hostname_by_id")}(uuid) from public, anon;
revoke execute on function ${fn("verify_hostname")}(uuid, uuid) from public, anon, authenticated;
revoke execute on function ${fn("set_primary_hostname")}(uuid) from public, anon;
revoke execute on function ${fn("remove_hostname")}(uuid) from public, anon;
revoke execute on function ${fn("resolve_hostname")}(text) from public;
grant execute on function ${fn("add_hostname")}(${id}, text) to authenticated, service_role;
grant execute on function ${fn("list_hostnames")}(${id}) to authenticated, service_role;
grant execute on function ${fn("hostname_by_id")}(uuid) to authenticated, service_role;
grant execute on function ${fn("verify_hostname")}(uuid, uuid) to service_role;
grant execute on function ${fn("set_primary_hostname")}(uuid) to authenticated, service_role;
grant execute on function ${fn("remove_hostname")}(uuid) to authenticated, service_role;
grant execute on function ${fn("resolve_hostname")}(text) to anon, authenticated, service_role;`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "add_hostname", args: ["{id}", "text"], returns: "jsonb" },
    { name: "list_hostnames", args: ["{id}"], returns: "jsonb" },
    { name: "hostname_by_id", args: ["uuid"], returns: "jsonb" },
    { name: "verify_hostname", args: ["uuid", "uuid"], returns: "jsonb" },
    { name: "set_primary_hostname", args: ["uuid"], returns: "jsonb" },
    { name: "remove_hostname", args: ["uuid"], returns: "boolean" },
    { name: "resolve_hostname", args: ["text"], returns: "jsonb" },
  ];
}

export const DOMAINS: BlockSqlDefinition = {
  name: "domains",
  scopes: ["tenant"],
  title: "Custom domains",
  description:
    "Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.",
  requires: ["tenant", "access"],
  integrates: ["reserved-slugs"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
