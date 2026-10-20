import type { OAuthServerEvents } from "../../blocks/oauth-server/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";

const EVENTS: ModuleEvents<OAuthServerEvents> = {
  "oauth_client.registered": {
    subject: "oauth-clients",
    payload: ["clientId"],
  },
  "oauth_client.deleted": {
    subject: "oauth-clients",
    payload: ["clientId"],
  },
  "oauth_grant.created": {
    subject: "oauth-grants",
    payload: ["grantId", "userId", "clientId"],
  },
  "oauth_grant.revoked": {
    subject: "oauth-grants",
    payload: ["grantId", "userId", "clientId"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  options: ["clientIdPattern"],
  tables: {
    clients: {
      name: "oauth_clients",
      columns: {
        id: "id",
        clientId: "client_id",
        secretHash: "secret_hash",
        registrationTokenHash: "registration_token_hash",
        name: "client_name",
        redirectUris: "redirect_uris",
        grantTypes: "grant_types",
        authMethod: "token_endpoint_auth_method",
        scope: "scope",
        metadata: "metadata",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    grants: {
      name: "oauth_grants",
      columns: {
        id: "id",
        userId: "user_id",
        clientId: "client_id",
        scopes: "scopes",
        resource: "resource",
        createdAt: "created_at",
        updatedAt: "updated_at",
        revokedAt: "revoked_at",
      },
    },
    codes: {
      name: "oauth_authorization_codes",
      columns: {
        codeHash: "code_hash",
        clientId: "client_id",
        userId: "user_id",
        grantId: "grant_id",
        redirectUri: "redirect_uri",
        scope: "scope",
        resource: "resource",
        codeChallenge: "code_challenge",
        nonce: "nonce",
        expiresAt: "expires_at",
        consumedAt: "consumed_at",
        createdAt: "created_at",
      },
    },
    devices: {
      name: "oauth_device_codes",
      columns: {
        deviceCodeHash: "device_code_hash",
        userCode: "user_code",
        clientId: "client_id",
        scope: "scope",
        resource: "resource",
        status: "status",
        userId: "user_id",
        grantId: "grant_id",
        pollInterval: "poll_interval",
        lastPolledAt: "last_polled_at",
        expiresAt: "expires_at",
        consumedAt: "consumed_at",
        createdAt: "created_at",
      },
    },
    revocations: {
      name: "oauth_revocations",
      columns: {
        jti: "jti",
        grantId: "grant_id",
        expiresAt: "expires_at",
        createdAt: "created_at",
      },
    },
  },
};

/** `clientIdPattern: "slug"` accepts lower-case slugs such as `acme-cli`. */
const CLIENT_ID_PATTERNS: Readonly<Record<string, string>> = {
  slug: "^[a-z0-9][a-z0-9-]{2,63}$",
};

const DEFAULT_CLIENT_ID_PATTERN = "^[A-Za-z0-9._~-]{8,128}$";

const guard = `
  if not (${SERVICE_CALLER}) then
    ${fail("OAUTH_SERVER_FORBIDDEN", "only the service role calls the oauth-server functions")}
  end if;`;

function clientEvent(
  ctx: ModuleContext,
  type: "oauth_client.registered" | "oauth_client.deleted",
  clientId: string,
): string {
  return ctx.record({
    type,
    payload: `jsonb_build_object('clientId', ${clientId})`,
    subject: `'oauth-clients/' || ${clientId}`,
    audit: {
      category: "security",
      targetType: "oauth_client",
      recordId: clientId,
    },
  });
}

function grantEvent(
  ctx: ModuleContext,
  type: "oauth_grant.created" | "oauth_grant.revoked",
  row: string,
): string {
  const g = (logical: string): string => `${row}.${ctx.col("grants", logical)}`;

  return ctx.record({
    type,
    payload: `jsonb_build_object('grantId', ${g("id")}::text, 'userId', ${g("userId")}::text, 'clientId', ${g("clientId")})`,
    subject: `'oauth-grants/' || ${g("id")}::text`,
    audit: {
      category: "access",
      targetType: "oauth_grant",
      recordId: `${g("id")}::text`,
      actor: g("userId"),
    },
  });
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const clients = ctx.table("clients");
  const grants = ctx.table("grants");
  const codes = ctx.table("codes");
  const devices = ctx.table("devices");
  const revocations = ctx.table("revocations");
  const cc = (logical: string): string => ctx.col("clients", logical);
  const gc = (logical: string): string => ctx.col("grants", logical);
  const ac = (logical: string): string => ctx.col("codes", logical);
  const dc = (logical: string): string => ctx.col("devices", logical);
  const rc = (logical: string): string => ctx.col("revocations", logical);
  const fn = (name: string): string => ctx.fn(name);
  const configured = ctx.text("clientIdPattern", DEFAULT_CLIENT_ID_PATTERN);
  const clientIdPattern = CLIENT_ID_PATTERNS[configured] ?? configured;

  try {
    new RegExp(clientIdPattern, "u").test("");
  } catch {
    throw new TypeError(
      "blocks.oauth-server.options.clientIdPattern must be a regular expression or the preset slug",
    );
  }

  const clientJson = (alias: string): string => `jsonb_build_object(
      'clientId', ${alias}.${cc("clientId")},
      'name', ${alias}.${cc("name")},
      'redirectUris', to_jsonb(${alias}.${cc("redirectUris")}),
      'grantTypes', to_jsonb(${alias}.${cc("grantTypes")}),
      'tokenEndpointAuthMethod', ${alias}.${cc("authMethod")},
      'scope', ${alias}.${cc("scope")},
      'metadata', ${alias}.${cc("metadata")},
      'createdBy', ${alias}.${cc("createdBy")},
      'createdAt', ${alias}.${cc("createdAt")},
      'updatedAt', ${alias}.${cc("updatedAt")})`;

  const grantJson = (alias: string): string => `jsonb_build_object(
      'id', ${alias}.${gc("id")},
      'userId', ${alias}.${gc("userId")},
      'clientId', ${alias}.${gc("clientId")},
      'scopes', to_jsonb(${alias}.${gc("scopes")}),
      'resource', to_jsonb(${alias}.${gc("resource")}),
      'createdAt', ${alias}.${gc("createdAt")},
      'updatedAt', ${alias}.${gc("updatedAt")},
      'revokedAt', ${alias}.${gc("revokedAt")})`;

  const scopes = (expression: string): string =>
    `array(select s from unnest(regexp_split_to_array(btrim(coalesce(${expression}, '')), '\\s+')) s where s <> '')`;

  return `${schemaPreamble(ctx)}
-- OAuth 2.1 authorization server storage: registered clients (RFC 7591)
-- with hashed secrets, a user's grant per client, single-use authorization
-- codes bound to a PKCE S256 challenge (RFC 7636), device codes (RFC 8628)
-- and a revocation list of access token jtis. Tokens are issued elsewhere.
create table if not exists ${clients} (
  ${cc("id")} uuid primary key default gen_random_uuid(),
  ${cc("clientId")} text not null unique check (${cc("clientId")} ~ ${sqlString(clientIdPattern)}),
  ${cc("secretHash")} text check (${cc("secretHash")} ~ '^[0-9a-f]{64}$'),
  ${cc("registrationTokenHash")} text check (${cc("registrationTokenHash")} ~ '^[0-9a-f]{64}$'),
  ${cc("name")} text check (length(${cc("name")}) <= 200),
  ${cc("redirectUris")} text[] not null default '{}',
  ${cc("grantTypes")} text[] not null default '{authorization_code}'
    check (${cc("grantTypes")} <@ array['authorization_code', 'refresh_token', 'client_credentials', 'urn:ietf:params:oauth:grant-type:device_code']::text[]),
  ${cc("authMethod")} text not null default 'client_secret_basic'
    check (${cc("authMethod")} in ('none', 'client_secret_basic', 'client_secret_post')),
  ${cc("scope")} text,
  ${cc("metadata")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${cc("metadata")}) = 'object'),
  ${cc("createdBy")} uuid references auth.users (id) on delete set null,
  ${cc("createdAt")} timestamptz not null default now(),
  ${cc("updatedAt")} timestamptz not null default now(),
  check ((${cc("authMethod")} = 'none') = (${cc("secretHash")} is null))
);
create index if not exists oauth_clients_created_by_idx on ${clients} (${cc("createdBy")});
${lockTable(clients)}

create table if not exists ${grants} (
  ${gc("id")} uuid primary key default gen_random_uuid(),
  ${gc("userId")} uuid not null references auth.users (id) on delete cascade,
  ${gc("clientId")} text not null references ${clients} (${cc("clientId")}) on delete cascade on update cascade,
  ${gc("scopes")} text[] not null default '{}',
  ${gc("resource")} text[] not null default '{}',
  ${gc("createdAt")} timestamptz not null default now(),
  ${gc("updatedAt")} timestamptz not null default now(),
  ${gc("revokedAt")} timestamptz
);
create unique index if not exists oauth_grants_active_idx on ${grants} (${gc("userId")}, ${gc("clientId")}) where ${gc("revokedAt")} is null;
create index if not exists oauth_grants_client_idx on ${grants} (${gc("clientId")});
alter table ${grants} add column if not exists ${gc("resource")} text[] not null default '{}';
create index if not exists oauth_grants_user_idx on ${grants} (${gc("userId")});
${lockTable(grants)}

create table if not exists ${codes} (
  ${ac("codeHash")} text primary key check (${ac("codeHash")} ~ '^[0-9a-f]{64}$'),
  ${ac("clientId")} text not null references ${clients} (${cc("clientId")}) on delete cascade on update cascade,
  ${ac("userId")} uuid not null references auth.users (id) on delete cascade,
  ${ac("grantId")} uuid not null references ${grants} (${gc("id")}) on delete cascade,
  ${ac("redirectUri")} text,
  ${ac("scope")} text not null default '',
  ${ac("resource")} text[] not null default '{}',
  ${ac("codeChallenge")} text not null check (${ac("codeChallenge")} ~ '^[A-Za-z0-9_-]{43}$'),
  ${ac("nonce")} text,
  ${ac("expiresAt")} timestamptz not null,
  ${ac("consumedAt")} timestamptz,
  ${ac("createdAt")} timestamptz not null default now()
);
create index if not exists oauth_authorization_codes_expires_idx on ${codes} (${ac("expiresAt")});
create index if not exists oauth_authorization_codes_grant_idx on ${codes} (${ac("grantId")});
create index if not exists oauth_authorization_codes_client_idx on ${codes} (${ac("clientId")});
alter table ${codes} add column if not exists ${ac("resource")} text[] not null default '{}';
create index if not exists oauth_authorization_codes_user_idx on ${codes} (${ac("userId")});
${lockTable(codes)}

create table if not exists ${devices} (
  ${dc("deviceCodeHash")} text primary key check (${dc("deviceCodeHash")} ~ '^[0-9a-f]{64}$'),
  ${dc("userCode")} text not null check (${dc("userCode")} ~ '^[A-Z0-9]{6,12}$'),
  ${dc("clientId")} text not null references ${clients} (${cc("clientId")}) on delete cascade on update cascade,
  ${dc("scope")} text not null default '',
  ${dc("resource")} text[] not null default '{}',
  ${dc("status")} text not null default 'pending' check (${dc("status")} in ('pending', 'approved', 'denied')),
  ${dc("userId")} uuid references auth.users (id) on delete cascade,
  ${dc("grantId")} uuid references ${grants} (${gc("id")}) on delete cascade,
  ${dc("pollInterval")} integer not null default 5 check (${dc("pollInterval")} between 1 and 300),
  ${dc("lastPolledAt")} timestamptz,
  ${dc("expiresAt")} timestamptz not null,
  ${dc("consumedAt")} timestamptz,
  ${dc("createdAt")} timestamptz not null default now(),
  check ((${dc("status")} = 'approved') = (${dc("grantId")} is not null))
);
create unique index if not exists oauth_device_codes_user_code_idx on ${devices} (${dc("userCode")}) where ${dc("status")} = 'pending';
create index if not exists oauth_device_codes_expires_idx on ${devices} (${dc("expiresAt")});
create index if not exists oauth_device_codes_grant_idx on ${devices} (${dc("grantId")});
create index if not exists oauth_device_codes_client_idx on ${devices} (${dc("clientId")});
alter table ${devices} add column if not exists ${dc("resource")} text[] not null default '{}';
create index if not exists oauth_device_codes_user_idx on ${devices} (${dc("userId")});
${lockTable(devices)}

create table if not exists ${revocations} (
  ${rc("jti")} text primary key check (length(${rc("jti")}) between 1 and 256),
  ${rc("grantId")} uuid,
  ${rc("expiresAt")} timestamptz not null,
  ${rc("createdAt")} timestamptz not null default now()
);
create index if not exists oauth_revocations_expires_idx on ${revocations} (${rc("expiresAt")});
${lockTable(revocations)}

-- The user's active grant for the client, widened to the scopes; a new one
-- when there is none. Only the definer functions below call it.
drop function if exists ${fn("oauth_grant_for")}(uuid, text, text[]);
create or replace function ${fn("oauth_grant_for")}(user_id uuid, client_id text, scopes text[], resource text[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${grants};
begin${guard}
  update ${grants} g
  set ${gc("scopes")} = array(select distinct s from unnest(g.${gc("scopes")} || oauth_grant_for.scopes) s order by s),
    ${gc("resource")} = array(select distinct r from unnest(g.${gc("resource")} || coalesce(oauth_grant_for.resource, '{}')) r order by r),
    ${gc("updatedAt")} = now()
  where g.${gc("userId")} = oauth_grant_for.user_id
    and g.${gc("clientId")} = oauth_grant_for.client_id
    and g.${gc("revokedAt")} is null
  returning g.* into v_row;
  if v_row.${gc("id")} is null then
    insert into ${grants} (${gc("userId")}, ${gc("clientId")}, ${gc("scopes")}, ${gc("resource")})
    values (oauth_grant_for.user_id, oauth_grant_for.client_id,
      array(select distinct s from unnest(oauth_grant_for.scopes) s order by s),
      array(select distinct r from unnest(coalesce(oauth_grant_for.resource, '{}')) r order by r))
    returning * into v_row;
    ${grantEvent(ctx, "oauth_grant.created", "v_row")}
  end if;
  return v_row.${gc("id")};
end;
$$;
revoke execute on function ${fn("oauth_grant_for")}(uuid, text, text[], text[]) from public, anon, authenticated, service_role;

-- Registers a client (RFC 7591). The secret and registration token arrive hashed.
create or replace function ${fn("register_oauth_client")}(
  client_id text, secret_hash text, registration_token_hash text, client_name text,
  redirect_uris text[], grant_types text[], token_endpoint_auth_method text, scope text,
  metadata jsonb, created_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${clients};
begin${guard}
  insert into ${clients} (${cc("clientId")}, ${cc("secretHash")}, ${cc("registrationTokenHash")}, ${cc("name")},
    ${cc("redirectUris")}, ${cc("grantTypes")}, ${cc("authMethod")}, ${cc("scope")}, ${cc("metadata")}, ${cc("createdBy")})
  values (register_oauth_client.client_id, register_oauth_client.secret_hash,
    register_oauth_client.registration_token_hash, register_oauth_client.client_name,
    coalesce(register_oauth_client.redirect_uris, '{}'),
    coalesce(register_oauth_client.grant_types, '{authorization_code}'),
    coalesce(register_oauth_client.token_endpoint_auth_method, 'client_secret_basic'),
    register_oauth_client.scope, coalesce(register_oauth_client.metadata, '{}'::jsonb),
    register_oauth_client.created_by)
  returning * into v_row;
  ${clientEvent(ctx, "oauth_client.registered", `v_row.${cc("clientId")}`)}
  return ${clientJson("v_row")};
end;
$$;
${serviceGrant(`${fn("register_oauth_client")}(text, text, text, text, text[], text[], text, text, jsonb, uuid)`)}

-- A client without its hashes, or null.
create or replace function ${fn("oauth_client")}(client_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (select ${clientJson("c")} from ${clients} c where c.${cc("clientId")} = oauth_client.client_id);
end;
$$;
${serviceGrant(`${fn("oauth_client")}(text)`)}

-- The client when the secret hash matches (null secret for a public client), or null.
create or replace function ${fn("verify_oauth_client")}(client_id text, secret_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (
    select ${clientJson("c")}
    from ${clients} c
    where c.${cc("clientId")} = verify_oauth_client.client_id
      and c.${cc("secretHash")} is not distinct from verify_oauth_client.secret_hash
  );
end;
$$;
${serviceGrant(`${fn("verify_oauth_client")}(text, text)`)}

-- Whether the registration access token (RFC 7592) belongs to the client.
create or replace function ${fn("verify_oauth_registration_token")}(client_id text, token_hash text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return exists (
    select 1 from ${clients} c
    where c.${cc("clientId")} = verify_oauth_registration_token.client_id
      and c.${cc("registrationTokenHash")} = verify_oauth_registration_token.token_hash
  );
end;
$$;
${serviceGrant(`${fn("verify_oauth_registration_token")}(text, text)`)}

-- Replaces a client's metadata (RFC 7592); null keeps a value. Null when unknown.
create or replace function ${fn("update_oauth_client")}(
  client_id text, client_name text, redirect_uris text[], grant_types text[], scope text, metadata jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${clients};
begin${guard}
  update ${clients} c set
    ${cc("name")} = coalesce(update_oauth_client.client_name, c.${cc("name")}),
    ${cc("redirectUris")} = coalesce(update_oauth_client.redirect_uris, c.${cc("redirectUris")}),
    ${cc("grantTypes")} = coalesce(update_oauth_client.grant_types, c.${cc("grantTypes")}),
    ${cc("scope")} = coalesce(update_oauth_client.scope, c.${cc("scope")}),
    ${cc("metadata")} = coalesce(update_oauth_client.metadata, c.${cc("metadata")}),
    ${cc("updatedAt")} = now()
  where c.${cc("clientId")} = update_oauth_client.client_id
  returning c.* into v_row;
  return case when v_row.${cc("id")} is null then null else ${clientJson("v_row")} end;
end;
$$;
${serviceGrant(`${fn("update_oauth_client")}(text, text, text[], text[], text, jsonb)`)}

-- Sets a new secret hash for a confidential client; false when unknown or public.
create or replace function ${fn("rotate_oauth_client_secret")}(client_id text, secret_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin${guard}
  update ${clients} c set ${cc("secretHash")} = rotate_oauth_client_secret.secret_hash, ${cc("updatedAt")} = now()
  where c.${cc("clientId")} = rotate_oauth_client_secret.client_id and c.${cc("authMethod")} <> 'none';
  return found;
end;
$$;
${serviceGrant(`${fn("rotate_oauth_client_secret")}(text, text)`)}

-- Deletes a client with its grants and codes; its tokens fail the grant check.
create or replace function ${fn("delete_oauth_client")}(client_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin${guard}
  delete from ${clients} c where c.${cc("clientId")} = delete_oauth_client.client_id;
  if not found then
    return false;
  end if;
  ${clientEvent(ctx, "oauth_client.deleted", "delete_oauth_client.client_id")}
  return true;
end;
$$;
${serviceGrant(`${fn("delete_oauth_client")}(text)`)}

-- Stores an authorization code after consent, under the user's grant.
drop function if exists ${fn("create_oauth_authorization_code")}(text, text, uuid, text, text, text, interval, text);
create or replace function ${fn("create_oauth_authorization_code")}(
  code_hash text, client_id text, user_id uuid, redirect_uri text, scope text,
  code_challenge text, ttl interval, nonce text default null, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant uuid;
begin${guard}
  if not exists (
    select 1 from ${clients} c
    where c.${cc("clientId")} = create_oauth_authorization_code.client_id
      and 'authorization_code' = any (c.${cc("grantTypes")})
      and (create_oauth_authorization_code.redirect_uri is null
        or create_oauth_authorization_code.redirect_uri = any (c.${cc("redirectUris")}))
  ) then
    ${fail("OAUTH_CLIENT_INVALID", "the client is unknown, can't use codes, or didn't register the redirect URI", "22023")}
  end if;
  v_grant := ${fn("oauth_grant_for")}(create_oauth_authorization_code.user_id,
    create_oauth_authorization_code.client_id, ${scopes("create_oauth_authorization_code.scope")},
    coalesce(create_oauth_authorization_code.resource, '{}'));
  insert into ${codes} (${ac("codeHash")}, ${ac("clientId")}, ${ac("userId")}, ${ac("grantId")}, ${ac("redirectUri")},
    ${ac("scope")}, ${ac("resource")}, ${ac("codeChallenge")}, ${ac("nonce")}, ${ac("expiresAt")})
  values (create_oauth_authorization_code.code_hash, create_oauth_authorization_code.client_id,
    create_oauth_authorization_code.user_id, v_grant, create_oauth_authorization_code.redirect_uri,
    coalesce(create_oauth_authorization_code.scope, ''), coalesce(create_oauth_authorization_code.resource, '{}'),
    create_oauth_authorization_code.code_challenge,
    create_oauth_authorization_code.nonce, now() + create_oauth_authorization_code.ttl);
  return jsonb_build_object('grantId', v_grant);
end;
$$;
${serviceGrant(`${fn("create_oauth_authorization_code")}(text, text, uuid, text, text, text, interval, text, text[])`)}

-- Consumes a code once. code_challenge is S256 of the presented verifier.
-- A code presented twice revokes its grant (RFC 9700 section 4.5).
drop function if exists ${fn("redeem_oauth_authorization_code")}(text, text, text, text);
create or replace function ${fn("redeem_oauth_authorization_code")}(
  code_hash text, client_id text, redirect_uri text, code_challenge text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code ${codes};
  v_grant ${grants};
begin${guard}
  select * into v_code from ${codes} a
  where a.${ac("codeHash")} = redeem_oauth_authorization_code.code_hash
  for update;
  if v_code.${ac("codeHash")} is null then
    return jsonb_build_object('status', 'invalid');
  end if;
  if v_code.${ac("consumedAt")} is not null then
    update ${grants} g set ${gc("revokedAt")} = now(), ${gc("updatedAt")} = now()
    where g.${gc("id")} = v_code.${ac("grantId")} and g.${gc("revokedAt")} is null
    returning g.* into v_grant;
    if v_grant.${gc("id")} is not null then
      ${grantEvent(ctx, "oauth_grant.revoked", "v_grant")}
    end if;
    return jsonb_build_object('status', 'invalid', 'replayed', true);
  end if;
  update ${codes} a set ${ac("consumedAt")} = now()
  where a.${ac("codeHash")} = v_code.${ac("codeHash")};
  if v_code.${ac("expiresAt")} <= now()
    or v_code.${ac("clientId")} <> redeem_oauth_authorization_code.client_id
    or v_code.${ac("redirectUri")} is distinct from redeem_oauth_authorization_code.redirect_uri
    or v_code.${ac("codeChallenge")} <> redeem_oauth_authorization_code.code_challenge
    or not exists (
      select 1 from ${grants} g
      where g.${gc("id")} = v_code.${ac("grantId")} and g.${gc("revokedAt")} is null
    ) then
    return jsonb_build_object('status', 'invalid');
  end if;
  -- RFC 8707 section 2.2: a token request may narrow the resources of the
  -- code but never widen them.
  if redeem_oauth_authorization_code.resource is not null
    and not redeem_oauth_authorization_code.resource <@ v_code.${ac("resource")} then
    return jsonb_build_object('status', 'invalid', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_code.${ac("userId")}, 'clientId', v_code.${ac("clientId")},
    'grantId', v_code.${ac("grantId")}, 'scope', v_code.${ac("scope")}, 'nonce', v_code.${ac("nonce")},
    'resource', to_jsonb(coalesce(redeem_oauth_authorization_code.resource, v_code.${ac("resource")})));
end;
$$;
${serviceGrant(`${fn("redeem_oauth_authorization_code")}(text, text, text, text, text[])`)}

-- Starts a device authorization (RFC 8628 section 3.2).
drop function if exists ${fn("create_oauth_device_code")}(text, text, text, text, interval, integer);
create or replace function ${fn("create_oauth_device_code")}(
  device_code_hash text, user_code text, client_id text, scope text, ttl interval, poll_interval integer default 5,
  resource text[] default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin${guard}
  if not exists (
    select 1 from ${clients} c
    where c.${cc("clientId")} = create_oauth_device_code.client_id
      and 'urn:ietf:params:oauth:grant-type:device_code' = any (c.${cc("grantTypes")})
  ) then
    ${fail("OAUTH_CLIENT_INVALID", "the client is unknown or can't use the device flow", "22023")}
  end if;
  insert into ${devices} (${dc("deviceCodeHash")}, ${dc("userCode")}, ${dc("clientId")}, ${dc("scope")},
    ${dc("resource")}, ${dc("pollInterval")}, ${dc("expiresAt")})
  values (create_oauth_device_code.device_code_hash, create_oauth_device_code.user_code,
    create_oauth_device_code.client_id, coalesce(create_oauth_device_code.scope, ''),
    coalesce(create_oauth_device_code.resource, '{}'),
    coalesce(create_oauth_device_code.poll_interval, 5), now() + create_oauth_device_code.ttl);
  return true;
end;
$$;
${serviceGrant(`${fn("create_oauth_device_code")}(text, text, text, text, interval, integer, text[])`)}

-- The pending request behind a user code, for the verification page, or null.
create or replace function ${fn("oauth_device_request")}(user_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (
    select jsonb_build_object('clientId', d.${dc("clientId")}, 'scope', d.${dc("scope")}, 'resource', to_jsonb(d.${dc("resource")}), 'expiresAt', d.${dc("expiresAt")})
    from ${devices} d
    where d.${dc("userCode")} = oauth_device_request.user_code
      and d.${dc("status")} = 'pending'
      and d.${dc("expiresAt")} > now()
  );
end;
$$;
${serviceGrant(`${fn("oauth_device_request")}(text)`)}

-- Approves or denies a pending user code for the signed-in user; false when
-- there is no such pending, unexpired code.
create or replace function ${fn("decide_oauth_device_code")}(user_code text, user_id uuid, approve boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device ${devices};
  v_grant uuid;
begin${guard}
  select * into v_device from ${devices} d
  where d.${dc("userCode")} = decide_oauth_device_code.user_code
    and d.${dc("status")} = 'pending'
    and d.${dc("expiresAt")} > now()
  for update;
  if v_device.${dc("deviceCodeHash")} is null then
    return false;
  end if;
  if decide_oauth_device_code.approve then
    v_grant := ${fn("oauth_grant_for")}(decide_oauth_device_code.user_id, v_device.${dc("clientId")},
      ${scopes(`v_device.${dc("scope")}`)}, v_device.${dc("resource")});
  end if;
  update ${devices} d set
    ${dc("status")} = case when decide_oauth_device_code.approve then 'approved' else 'denied' end,
    ${dc("userId")} = decide_oauth_device_code.user_id,
    ${dc("grantId")} = v_grant
  where d.${dc("deviceCodeHash")} = v_device.${dc("deviceCodeHash")};
  return true;
end;
$$;
${serviceGrant(`${fn("decide_oauth_device_code")}(text, uuid, boolean)`)}

-- A token request's poll (RFC 8628 section 3.5): pending, slow_down,
-- access_denied, expired_token, invalid_grant, or ok once.
drop function if exists ${fn("poll_oauth_device_code")}(text, text);
create or replace function ${fn("poll_oauth_device_code")}(device_code_hash text, client_id text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device ${devices};
begin${guard}
  select * into v_device from ${devices} d
  where d.${dc("deviceCodeHash")} = poll_oauth_device_code.device_code_hash
  for update;
  if v_device.${dc("deviceCodeHash")} is null
    or v_device.${dc("clientId")} <> poll_oauth_device_code.client_id
    or v_device.${dc("consumedAt")} is not null then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if v_device.${dc("expiresAt")} <= now() then
    return jsonb_build_object('status', 'expired_token');
  end if;
  if v_device.${dc("status")} = 'denied' then
    update ${devices} d set ${dc("consumedAt")} = now()
    where d.${dc("deviceCodeHash")} = v_device.${dc("deviceCodeHash")};
    return jsonb_build_object('status', 'access_denied');
  end if;
  if v_device.${dc("status")} = 'pending' then
    if v_device.${dc("lastPolledAt")} is not null
      and v_device.${dc("lastPolledAt")} + make_interval(secs => v_device.${dc("pollInterval")}) > now() then
      update ${devices} d set ${dc("pollInterval")} = least(d.${dc("pollInterval")} + 5, 300), ${dc("lastPolledAt")} = now()
      where d.${dc("deviceCodeHash")} = v_device.${dc("deviceCodeHash")};
      return jsonb_build_object('status', 'slow_down', 'interval', least(v_device.${dc("pollInterval")} + 5, 300));
    end if;
    update ${devices} d set ${dc("lastPolledAt")} = now()
    where d.${dc("deviceCodeHash")} = v_device.${dc("deviceCodeHash")};
    return jsonb_build_object('status', 'authorization_pending', 'interval', v_device.${dc("pollInterval")});
  end if;
  update ${devices} d set ${dc("consumedAt")} = now()
  where d.${dc("deviceCodeHash")} = v_device.${dc("deviceCodeHash")};
  if not exists (
    select 1 from ${grants} g
    where g.${gc("id")} = v_device.${dc("grantId")} and g.${gc("revokedAt")} is null
  ) then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if poll_oauth_device_code.resource is not null
    and not poll_oauth_device_code.resource <@ v_device.${dc("resource")} then
    return jsonb_build_object('status', 'invalid_grant', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_device.${dc("userId")}, 'clientId', v_device.${dc("clientId")},
    'grantId', v_device.${dc("grantId")}, 'scope', v_device.${dc("scope")},
    'resource', to_jsonb(coalesce(poll_oauth_device_code.resource, v_device.${dc("resource")})));
end;
$$;
${serviceGrant(`${fn("poll_oauth_device_code")}(text, text, text[])`)}

-- A user's grants, newest first; revoked ones only with include_revoked.
create or replace function ${fn("list_oauth_grants")}(user_id uuid, include_revoked boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return coalesce((
    select jsonb_agg(${grantJson("g")} || jsonb_build_object('clientName', c.${cc("name")}) order by g.${gc("createdAt")} desc)
    from ${grants} g
    join ${clients} c on c.${cc("clientId")} = g.${gc("clientId")}
    where g.${gc("userId")} = list_oauth_grants.user_id
      and (list_oauth_grants.include_revoked or g.${gc("revokedAt")} is null)
  ), '[]'::jsonb);
end;
$$;
${serviceGrant(`${fn("list_oauth_grants")}(uuid, boolean)`)}

-- Revokes a grant, which ends every token and code issued under it.
create or replace function ${fn("revoke_oauth_grant")}(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${grants};
begin${guard}
  update ${grants} g set ${gc("revokedAt")} = now(), ${gc("updatedAt")} = now()
  where g.${gc("id")} = revoke_oauth_grant.grant_id and g.${gc("revokedAt")} is null
  returning g.* into v_row;
  if v_row.${gc("id")} is null then
    return false;
  end if;
  ${grantEvent(ctx, "oauth_grant.revoked", "v_row")}
  return true;
end;
$$;
${serviceGrant(`${fn("revoke_oauth_grant")}(uuid)`)}

-- The signed-in user's active grants, for a "connected apps" page.
create or replace function ${fn("my_oauth_grants")}()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select jsonb_agg(${grantJson("g")} || jsonb_build_object('clientName', c.${cc("name")}) order by g.${gc("createdAt")} desc)
    from ${grants} g
    join ${clients} c on c.${cc("clientId")} = g.${gc("clientId")}
    where g.${gc("userId")} = (select auth.uid())
      and g.${gc("revokedAt")} is null
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("my_oauth_grants")}()`)}

-- Revokes one of the signed-in user's grants; false when it isn't theirs or active.
create or replace function ${fn("revoke_my_oauth_grant")}(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${grants};
begin
  update ${grants} g set ${gc("revokedAt")} = now(), ${gc("updatedAt")} = now()
  where g.${gc("id")} = revoke_my_oauth_grant.grant_id
    and g.${gc("userId")} = (select auth.uid())
    and g.${gc("revokedAt")} is null
  returning g.* into v_row;
  if v_row.${gc("id")} is null then
    return false;
  end if;
  ${grantEvent(ctx, "oauth_grant.revoked", "v_row")}
  return true;
end;
$$;
${userGrant(`${fn("revoke_my_oauth_grant")}(uuid)`)}

-- Adds an access token's jti to the revocation list until it expires.
create or replace function ${fn("revoke_oauth_token")}(jti text, expires_at timestamptz, grant_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin${guard}
  insert into ${revocations} (${rc("jti")}, ${rc("grantId")}, ${rc("expiresAt")})
  values (revoke_oauth_token.jti, revoke_oauth_token.grant_id, revoke_oauth_token.expires_at)
  on conflict (${rc("jti")}) do update
    set ${rc("expiresAt")} = greatest(${revocations}.${rc("expiresAt")}, excluded.${rc("expiresAt")});
  return true;
end;
$$;
${serviceGrant(`${fn("revoke_oauth_token")}(text, timestamptz, uuid)`)}

-- True when the jti is on the revocation list, or the grant is revoked or
-- gone. A grant id that isn't a uuid counts as gone.
create or replace function ${fn("is_oauth_token_revoked")}(jti text, grant_id text default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  if exists (select 1 from ${revocations} r where r.${rc("jti")} = is_oauth_token_revoked.jti) then
    return true;
  end if;
  if is_oauth_token_revoked.grant_id is null then
    return false;
  end if;
  return not exists (
    select 1 from ${grants} g
    where g.${gc("id")}::text = is_oauth_token_revoked.grant_id
      and g.${gc("revokedAt")} is null
  );
end;
$$;
${serviceGrant(`${fn("is_oauth_token_revoked")}(text, text)`)}

-- Deletes expired codes, device codes and revocation entries.
create or replace function ${fn("purge_oauth_server")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_rows integer;
begin${guard}
  delete from ${codes} a where a.${ac("expiresAt")} < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from ${devices} d where d.${dc("expiresAt")} < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from ${revocations} r where r.${rc("expiresAt")} < now();
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
$$;
${serviceGrant(`${fn("purge_oauth_server")}()`)}`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "register_oauth_client",
      args: [
        "text",
        "text",
        "text",
        "text",
        "text[]",
        "text[]",
        "text",
        "text",
        "jsonb",
        "uuid",
      ],
      returns: "jsonb",
    },
    { name: "oauth_client", args: ["text"], returns: "jsonb" },
    { name: "verify_oauth_client", args: ["text", "text"], returns: "jsonb" },
    {
      name: "verify_oauth_registration_token",
      args: ["text", "text"],
      returns: "boolean",
    },
    {
      name: "update_oauth_client",
      args: ["text", "text", "text[]", "text[]", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "rotate_oauth_client_secret",
      args: ["text", "text"],
      returns: "boolean",
    },
    { name: "delete_oauth_client", args: ["text"], returns: "boolean" },
    {
      name: "create_oauth_authorization_code",
      args: [
        "text",
        "text",
        "uuid",
        "text",
        "text",
        "text",
        "interval",
        "text",
        "text[]",
      ],
      returns: "jsonb",
    },
    {
      name: "redeem_oauth_authorization_code",
      args: ["text", "text", "text", "text", "text[]"],
      returns: "jsonb",
    },
    {
      name: "create_oauth_device_code",
      args: ["text", "text", "text", "text", "interval", "integer", "text[]"],
      returns: "boolean",
    },
    { name: "oauth_device_request", args: ["text"], returns: "jsonb" },
    {
      name: "decide_oauth_device_code",
      args: ["text", "uuid", "boolean"],
      returns: "boolean",
    },
    {
      name: "poll_oauth_device_code",
      args: ["text", "text", "text[]"],
      returns: "jsonb",
    },
    { name: "list_oauth_grants", args: ["uuid", "boolean"], returns: "jsonb" },
    { name: "revoke_oauth_grant", args: ["uuid"], returns: "boolean" },
    { name: "my_oauth_grants", args: [], returns: "jsonb" },
    { name: "revoke_my_oauth_grant", args: ["uuid"], returns: "boolean" },
    {
      name: "revoke_oauth_token",
      args: ["text", "timestamptz", "uuid"],
      returns: "boolean",
    },
    {
      name: "is_oauth_token_revoked",
      args: ["text", "text"],
      returns: "boolean",
    },
    { name: "purge_oauth_server", args: [], returns: "integer" },
  ];
}

export const OAUTH_SERVER: ModuleDefinition = {
  name: "oauth-server",
  title: "OAuth server",
  description:
    "Storage for an OAuth 2.1 authorization server: registered clients (RFC 7591) with hashed secrets, a grant per user and client, single-use authorization codes bound to a PKCE S256 challenge, device codes (RFC 8628) and a revocation list of access token jtis. It issues no tokens. createOAuthServer() in better-supabase/blocks/oauth-server hashes secrets and checks PKCE, and its isRevoked plugs into accessTokenResolver.",
  requires: [],
  integrates: ["outbox", "audit"],
  target: "schema",
  version: 1,
  names: NAMES,
  contract,
  build,
};
