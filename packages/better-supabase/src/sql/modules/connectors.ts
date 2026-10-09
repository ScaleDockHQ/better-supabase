import type { ModuleContext, ModuleNames } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { schemaPreamble, SERVICE_CALLER, tenantIn } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { canIn, raise, serviceGrant, userGrant } from "./ai-chat-sql.ts";
import { tenantRefGuard } from "./credentials.ts";
import { columnsOf, rowJson } from "./module-columns.ts";

const SERVERS = {
  id: "id",
  tenant: "organization_id",
  name: "name",
  url: "url",
  transport: "transport",
  authType: "auth_type",
  credentialRef: "credential_ref",
  scopes: "scopes",
  clientMetadata: "client_metadata",
  enabled: "enabled",
  createdBy: "created_by",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const GRANTS = {
  id: "id",
  user: "user_id",
  server: "server_id",
  tenant: "organization_id",
  credentialRef: "credential_ref",
  scopes: "scopes",
  expiresAt: "expires_at",
  grantedAt: "granted_at",
  revokedAt: "revoked_at",
} as const;

const SESSIONS = {
  server: "server_id",
  user: "user_id",
  chat: "chat_key",
  session: "session_id",
  initializeResult: "initialize_result",
  lastUsedAt: "last_used_at",
  expiresAt: "expires_at",
} as const;

const FINGERPRINTS = {
  server: "server_id",
  fingerprint: "fingerprint",
  tools: "tools",
  status: "status",
  approvedBy: "approved_by",
  approvedAt: "approved_at",
  createdAt: "created_at",
} as const;

const NAMES: ModuleNames = {
  options: ["allowHttp", "trustFirstUse", "sessionTtl"],
  tables: {
    servers: {
      name: "connector_servers",
      columns: SERVERS,
      lifecycle: { tenant: "tenant" },
    },
    grants: {
      name: "connector_grants",
      columns: GRANTS,
      lifecycle: { user: "user", tenant: "tenant" },
    },
    sessions: {
      name: "connector_sessions",
      columns: SESSIONS,
      lifecycle: { user: "user" },
    },
    fingerprints: {
      name: "connector_tool_fingerprints",
      columns: FINGERPRINTS,
    },
  },
};

const INTERVAL = /^\d+ (second|minute|hour|day)s?$/;

function build(ctx: ModuleContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const v = columnsOf(ctx, "servers", SERVERS);
  const g = columnsOf(ctx, "grants", GRANTS);
  const n = columnsOf(ctx, "sessions", SESSIONS);
  const f = columnsOf(ctx, "fingerprints", FINGERPRINTS);
  const servers = ctx.table("servers");
  const grants = ctx.table("grants");
  const sessions = ctx.table("sessions");
  const fingerprints = ctx.table("fingerprints");
  const permissions = MODULE_PERMISSIONS.connectors;
  const read = ctx.permission("read", permissions.read);
  const use = ctx.permission("use", permissions.use);
  const manage = ctx.permission("manage", permissions.manage);
  const allowHttp = ctx.flag("allowHttp", false);
  const trustFirstUse = ctx.flag("trustFirstUse", true);
  const sessionTtl = ctx.text("sessionTtl", "1 hour");
  if (!INTERVAL.test(sessionTtl)) {
    throw new TypeError(
      'sql.modules.connectors.options.sessionTtl must be an interval such as "1 hour"',
    );
  }
  const urlPattern = allowHttp
    ? "^https?://"
    : "^(https://|http://(localhost|127[.]0[.]0[.]1)(:[0-9]+)?(/|$))";
  const serverJson = (row: string): string => rowJson(SERVERS, v, row);
  const grantJson = (row: string): string => rowJson(GRANTS, g, row);
  const isAdmin = (tenant: string): string =>
    `(${SERVICE_CALLER} or ${canIn(tenant, manage)})`;
  const notFound = (server: string): string =>
    raise("connector % not found", "P0002", "CONNECTOR_NOT_FOUND", server);

  return `${schemaPreamble(ctx)}
-- MCP servers a tenant connects its assistants to. A server names how to
-- authenticate (none, OAuth per user, or a header from credential_ref) and
-- never holds a token itself.
create table if not exists ${servers} (
  ${v.id} uuid primary key default gen_random_uuid(),
  ${v.tenant} ${id} not null,
  ${v.name} text not null check (length(${v.name}) between 1 and 200),
  ${v.url} text not null check (${v.url} ~ '${urlPattern}' and length(${v.url}) <= 2000),
  ${v.transport} text not null default 'http' check (${v.transport} in ('http', 'sse')),
  ${v.authType} text not null default 'oauth' check (${v.authType} in ('none', 'oauth', 'header')),
  ${v.credentialRef} jsonb check (${v.credentialRef} is null or (jsonb_typeof(${v.credentialRef}) = 'object' and ${v.credentialRef} ? 'provider')),
  ${v.scopes} text[] not null default '{}',
  ${v.clientMetadata} jsonb not null default '{}' check (jsonb_typeof(${v.clientMetadata}) = 'object'),
  ${v.enabled} boolean not null default true,
  ${v.createdBy} uuid references auth.users (id) on delete set null,
  ${v.createdAt} timestamptz not null default now(),
  ${v.updatedAt} timestamptz not null default now(),
  check ((${v.authType} = 'header') = (${v.credentialRef} is not null))
);
create index if not exists connector_servers_tenant_idx on ${servers} (${v.tenant});
create index if not exists connector_servers_created_by_idx on ${servers} (${v.createdBy});
alter table ${servers} enable row level security;
revoke all on ${servers} from anon, authenticated;
grant select on ${servers} to authenticated;
grant all on ${servers} to service_role;
drop policy if exists connector_servers_read on ${servers};
create policy connector_servers_read on ${servers} for select to authenticated
  using (${tenantIn(v.tenant, read)});

-- A user's connection to a server. credential_ref names where the provider
-- keeps the token (Vault, Vercel Connect); the row holds none.
create table if not exists ${grants} (
  ${g.id} uuid primary key default gen_random_uuid(),
  ${g.user} uuid not null references auth.users (id) on delete cascade,
  ${g.server} uuid not null references ${servers} (${v.id}) on delete cascade,
  ${g.tenant} ${id} not null,
  ${g.credentialRef} jsonb not null check (jsonb_typeof(${g.credentialRef}) = 'object' and ${g.credentialRef} ? 'provider'),
  ${g.scopes} text[] not null default '{}',
  ${g.expiresAt} timestamptz,
  ${g.grantedAt} timestamptz not null default now(),
  ${g.revokedAt} timestamptz
);
create unique index if not exists connector_grants_active_idx on ${grants} (${g.user}, ${g.server}) where ${g.revokedAt} is null;
create index if not exists connector_grants_server_idx on ${grants} (${g.server});
create index if not exists connector_grants_user_idx on ${grants} (${g.user});
alter table ${grants} enable row level security;
revoke all on ${grants} from anon, authenticated;
grant select on ${grants} to authenticated;
grant all on ${grants} to service_role;
drop policy if exists connector_grants_read on ${grants};
create policy connector_grants_read on ${grants} for select to authenticated
  using (${g.user} = (select auth.uid()));

-- The MCP session a user holds with a server per chat, so a later request
-- reuses it instead of initializing again.
create table if not exists ${sessions} (
  ${n.server} uuid not null references ${servers} (${v.id}) on delete cascade,
  ${n.user} uuid not null references auth.users (id) on delete cascade,
  ${n.chat} text not null default '',
  ${n.session} text,
  ${n.initializeResult} jsonb,
  ${n.lastUsedAt} timestamptz not null default now(),
  ${n.expiresAt} timestamptz not null,
  primary key (${n.server}, ${n.user}, ${n.chat})
);
create index if not exists connector_sessions_expires_idx on ${sessions} (${n.expiresAt});
create index if not exists connector_sessions_user_idx on ${sessions} (${n.user});
alter table ${sessions} enable row level security;
revoke all on ${sessions} from anon, authenticated;
grant select on ${sessions} to authenticated;
grant all on ${sessions} to service_role;
drop policy if exists connector_sessions_read on ${sessions};
create policy connector_sessions_read on ${sessions} for select to authenticated
  using (${n.user} = (select auth.uid()));

-- Fingerprints of a server's tool list. A list that changed waits for an
-- admin before an assistant may call it.
create table if not exists ${fingerprints} (
  ${f.server} uuid not null references ${servers} (${v.id}) on delete cascade,
  ${f.fingerprint} text not null check (length(${f.fingerprint}) between 1 and 200),
  ${f.tools} jsonb not null default '{}' check (jsonb_typeof(${f.tools}) = 'object'),
  ${f.status} text not null default 'pending' check (${f.status} in ('pending', 'approved', 'rejected')),
  ${f.approvedBy} uuid references auth.users (id) on delete set null,
  ${f.approvedAt} timestamptz,
  ${f.createdAt} timestamptz not null default now(),
  primary key (${f.server}, ${f.fingerprint})
);
create index if not exists connector_tool_fingerprints_approved_by_idx on ${fingerprints} (${f.approvedBy});
alter table ${fingerprints} enable row level security;
revoke all on ${fingerprints} from anon, authenticated;
grant select on ${fingerprints} to authenticated;
grant all on ${fingerprints} to service_role;
drop policy if exists connector_tool_fingerprints_read on ${fingerprints};
create policy connector_tool_fingerprints_read on ${fingerprints} for select to authenticated
  using (exists (select 1 from ${servers} x where x.${v.id} = ${f.server}));

-- Adds a server (id null) or changes one (${manage}).
create or replace function ${fn("save_connector_server")}(tenant ${id}, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${servers}%rowtype;
begin
  if not ${isAdmin("save_connector_server.tenant")} then
    ${raise("you may not manage connectors here", "42501", "CONNECTOR_FORBIDDEN")}
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    ${raise("fields must be an object", "22023", "CONNECTOR_INVALID")}
  end if;
  ${tenantRefGuard("save_connector_server.fields -> 'credential_ref'", "save_connector_server.tenant")}
  if save_connector_server.id is null then
    insert into ${servers} (${v.tenant}, ${v.name}, ${v.url}, ${v.authType}, ${v.credentialRef}, ${v.createdBy})
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from ${servers} x where x.${v.id} = save_connector_server.id and x.${v.tenant} = save_connector_server.tenant for update;
    if not found then
      ${notFound("save_connector_server.id")}
    end if;
  end if;
  update ${servers} x set
    ${v.name} = coalesce(save_connector_server.fields ->> 'name', x.${v.name}),
    ${v.url} = coalesce(save_connector_server.fields ->> 'url', x.${v.url}),
    ${v.transport} = coalesce(save_connector_server.fields ->> 'transport', x.${v.transport}),
    ${v.authType} = coalesce(save_connector_server.fields ->> 'auth_type', x.${v.authType}),
    ${v.credentialRef} = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x.${v.credentialRef} end,
    ${v.scopes} = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x.${v.scopes} end,
    ${v.clientMetadata} = coalesce(save_connector_server.fields -> 'client_metadata', x.${v.clientMetadata}),
    ${v.enabled} = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x.${v.enabled}),
    ${v.updatedAt} = now()
  where x.${v.id} = v_row.${v.id}
  returning * into v_row;
  return ${serverJson("v_row")};
end;
$$;
${userGrant(`${fn("save_connector_server")}(${id}, uuid, jsonb)`)}

-- Deletes a server and returns the grants it had, so the caller revokes
-- each credential through its provider.
create or replace function ${fn("delete_connector_server")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${servers}%rowtype;
  v_grants jsonb;
begin
  select * into v_row from ${servers} x where x.${v.id} = delete_connector_server.id for update;
  if not found or not ${isAdmin(`v_row.${v.tenant}`)} then
    ${notFound("delete_connector_server.id")}
  end if;
  select coalesce(jsonb_agg(${grantJson("y")}), '[]') into v_grants
  from ${grants} y where y.${g.server} = v_row.${v.id} and y.${g.revokedAt} is null;
  delete from ${servers} x where x.${v.id} = v_row.${v.id};
  return v_grants;
end;
$$;
${userGrant(`${fn("delete_connector_server")}(uuid)`)}

-- The tenant's servers with the caller's active grant on each.
create or replace function ${fn("list_connector_servers")}(tenant ${id})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${serverJson("x")} || jsonb_build_object('grant', (
    select ${grantJson("y")} from ${grants} y
    where y.${g.server} = x.${v.id} and y.${g.user} = auth.uid() and y.${g.revokedAt} is null
  )) order by x.${v.name}), '[]')
  from ${servers} x where x.${v.tenant} = list_connector_servers.tenant
$$;
${userGrant(`${fn("list_connector_servers")}(${id})`)}

-- A server and the active grant of a user on it: the caller's, or for the
-- service role the one of owner.
create or replace function ${fn("get_connector")}(id uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := case when ${SERVICE_CALLER} then get_connector.owner else auth.uid() end;
  v_row ${servers}%rowtype;
begin
  select * into v_row from ${servers} x where x.${v.id} = get_connector.id;
  if not found or not (${SERVICE_CALLER} or ${canIn(`v_row.${v.tenant}`, read)}) then
    return null;
  end if;
  return ${serverJson("v_row")} || jsonb_build_object('grant', (
    select ${grantJson("y")} from ${grants} y
    where y.${g.server} = v_row.${v.id} and y.${g.user} = v_user and y.${g.revokedAt} is null
  ));
end;
$$;
${userGrant(`${fn("get_connector")}(uuid, uuid)`)}

-- Records a user's grant after the provider stored the credential, revoking
-- the previous one (service role). Returns the new grant and the old one.
create or replace function ${fn("record_connector_grant")}(server_id uuid, owner uuid, credential_ref jsonb, scopes text[] default '{}', expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server ${servers}%rowtype;
  v_old ${grants}%rowtype;
  v_row ${grants}%rowtype;
begin
  select * into v_server from ${servers} x where x.${v.id} = record_connector_grant.server_id;
  if not found then
    ${notFound("record_connector_grant.server_id")}
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server.${v.tenant}, ${use}), false) then
    ${raise("the user may not use connectors here", "42501", "CONNECTOR_FORBIDDEN")}
  end if;
  update ${grants} y set ${g.revokedAt} = now()
  where y.${g.server} = v_server.${v.id} and y.${g.user} = record_connector_grant.owner and y.${g.revokedAt} is null
  returning * into v_old;
  insert into ${grants} (${g.user}, ${g.server}, ${g.tenant}, ${g.credentialRef}, ${g.scopes}, ${g.expiresAt})
  values (record_connector_grant.owner, v_server.${v.id}, v_server.${v.tenant}, record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  return jsonb_build_object('grant', ${grantJson("v_row")}, 'replaced', case when v_old.${g.id} is null then null else ${grantJson("v_old")} end);
end;
$$;
${serviceGrant(`${fn("record_connector_grant")}(uuid, uuid, jsonb, text[], timestamptz)`)}

-- Revokes a grant (its owner or the service role) and returns it, so the
-- caller revokes the credential through its provider.
create or replace function ${fn("revoke_connector_grant")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${grants}%rowtype;
begin
  update ${grants} y set ${g.revokedAt} = now()
  where y.${g.id} = revoke_connector_grant.id and y.${g.revokedAt} is null
    and (${SERVICE_CALLER} or y.${g.user} = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from ${sessions} z where z.${n.server} = v_row.${g.server} and z.${n.user} = v_row.${g.user};
  return ${grantJson("v_row")};
end;
$$;
${userGrant(`${fn("revoke_connector_grant")}(uuid)`)}

-- Grants that expire before a time, for the renewal job (service role).
create or replace function ${fn("expiring_connector_grants")}(before timestamptz, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${grantJson("y")} order by y.${g.expiresAt}), '[]')
  from (
    select * from ${grants} y0
    where y0.${g.revokedAt} is null and y0.${g.expiresAt} is not null and y0.${g.expiresAt} < expiring_connector_grants.before
    order by y0.${g.expiresAt}
    limit least(greatest(expiring_connector_grants.max_rows, 1), 1000)
  ) y
$$;
${serviceGrant(`${fn("expiring_connector_grants")}(timestamptz, integer)`)}

-- Moves a grant's expiry after the provider refreshed the token (service role).
create or replace function ${fn("renew_connector_grant")}(id uuid, expires_at timestamptz)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update ${grants} y set ${g.expiresAt} = renew_connector_grant.expires_at
    where y.${g.id} = renew_connector_grant.id and y.${g.revokedAt} is null
    returning 1
  )
  select exists (select 1 from updated)
$$;
${serviceGrant(`${fn("renew_connector_grant")}(uuid, timestamptz)`)}

-- The caller's MCP session with a server for a chat key, when it is still fresh.
create or replace function ${fn("get_connector_session")}(server_id uuid, chat_key text default '')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('session_id', z.${n.session}, 'initialize_result', z.${n.initializeResult}, 'expires_at', z.${n.expiresAt})
  from ${sessions} z
  where z.${n.server} = get_connector_session.server_id and z.${n.user} = auth.uid()
    and z.${n.chat} = coalesce(get_connector_session.chat_key, '') and z.${n.expiresAt} > now()
$$;
${userGrant(`${fn("get_connector_session")}(uuid, text)`)}

-- Saves the caller's MCP session; a null session_id forgets it.
create or replace function ${fn("save_connector_session")}(server_id uuid, chat_key text default '', session_id text default null, initialize_result jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from ${sessions} z where z.${n.server} = save_connector_session.server_id and z.${n.user} = auth.uid()
      and z.${n.chat} = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from ${grants} y where y.${g.server} = save_connector_session.server_id and y.${g.user} = auth.uid() and y.${g.revokedAt} is null)
    and not exists (select 1 from ${servers} x where x.${v.id} = save_connector_session.server_id and x.${v.authType} <> 'oauth' and ${canIn(`x.${v.tenant}`, use)}) then
    return false;
  end if;
  insert into ${sessions} (${n.server}, ${n.user}, ${n.chat}, ${n.session}, ${n.initializeResult}, ${n.expiresAt})
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '${sessionTtl}')
  on conflict (${n.server}, ${n.user}, ${n.chat}) do update set
    ${n.session} = excluded.${n.session}, ${n.initializeResult} = excluded.${n.initializeResult},
    ${n.lastUsedAt} = now(), ${n.expiresAt} = excluded.${n.expiresAt};
  return true;
end;
$$;
${userGrant(`${fn("save_connector_session")}(uuid, text, text, jsonb)`)}

-- Checks a server's tool list fingerprint: 'approved', 'pending' or
-- 'rejected'. A new fingerprint is recorded as pending${trustFirstUse ? ", except the first one of a server, which is approved" : ""}.
create or replace function ${fn("check_connector_fingerprint")}(server_id uuid, fingerprint text, tools jsonb default '{}')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server ${servers}%rowtype;
  v_status text;
begin
  select * into v_server from ${servers} x where x.${v.id} = check_connector_fingerprint.server_id;
  if not found or not (${SERVICE_CALLER} or ${canIn(`v_server.${v.tenant}`, use)}) then
    ${notFound("check_connector_fingerprint.server_id")}
  end if;
  select p.${f.status} into v_status from ${fingerprints} p
  where p.${f.server} = v_server.${v.id} and p.${f.fingerprint} = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := ${trustFirstUse ? `case when exists (select 1 from ${fingerprints} p where p.${f.server} = v_server.${v.id}) then 'pending' else 'approved' end` : "'pending'"};
  insert into ${fingerprints} (${f.server}, ${f.fingerprint}, ${f.tools}, ${f.status}, ${f.approvedAt})
  values (v_server.${v.id}, check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), v_status,
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$$;
${userGrant(`${fn("check_connector_fingerprint")}(uuid, text, jsonb)`)}

-- Approves or rejects a fingerprint (${manage}).
create or replace function ${fn("decide_connector_fingerprint")}(server_id uuid, fingerprint text, approved boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server ${servers}%rowtype;
begin
  select * into v_server from ${servers} x where x.${v.id} = decide_connector_fingerprint.server_id;
  if not found or not ${isAdmin(`v_server.${v.tenant}`)} then
    ${notFound("decide_connector_fingerprint.server_id")}
  end if;
  update ${fingerprints} p set
    ${f.status} = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    ${f.approvedBy} = auth.uid(), ${f.approvedAt} = now()
  where p.${f.server} = v_server.${v.id} and p.${f.fingerprint} = decide_connector_fingerprint.fingerprint;
  return found;
end;
$$;
${userGrant(`${fn("decide_connector_fingerprint")}(uuid, text, boolean)`)}

-- Deletes expired sessions (service role).
create or replace function ${fn("purge_connector_sessions")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from ${sessions} z where z.${n.expiresAt} < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("purge_connector_sessions")}()`)}`;
}

export const CONNECTORS: ModuleDefinition = {
  name: "connectors",
  title: "Connectors",
  description:
    "MCP servers per tenant with no, per-user OAuth or header auth; per-user grants that hold only a credential_ref; MCP sessions per chat; and tool list fingerprints that hold a changed list until an admin approves it.",
  requires: ["tenant", "access"],
  providerFunctions: ["idsWithFor"],
  target: "schema",
  version: 1,
  names: NAMES,
  build,
};
