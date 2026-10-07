import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER } from "../shared.ts";
import { accessModel, MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["scopes", "touchInterval", "prefix"],
  tables: {
    keys: {
      name: "api_keys",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        user: "user_id",
        name: "name",
        prefix: "prefix",
        publicId: "public_id",
        secretHash: "secret_hash",
        scopes: "scopes",
        rateLimit: "rate_limit",
        windowStart: "window_start",
        windowHits: "window_hits",
        expiresAt: "expires_at",
        lastUsedAt: "last_used_at",
        revokedAt: "revoked_at",
        rotatedFrom: "rotated_from",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

const fail = (code: string, message: string, errcode = "42501"): string =>
  `raise exception '${message}' using errcode = '${errcode}', hint = '${code}';`;

const SCOPE = /^(\*|[A-Za-z][A-Za-z0-9_.:-]*)$/;
const PREFIX = /^[a-z][a-z0-9]*$/;

/**
 * `sql.modules.api-keys.options.scopes`: the scopes a key may carry, every
 * scope when unset, or `"catalog"` for the keys of PermDock's
 * `permissions.catalog.json`.
 */
function allowedScopes(
  ctx: ModuleContext,
  layout: ModuleLayout,
): readonly string[] | undefined {
  const option = ctx.option("scopes");
  if (option === undefined) return undefined;
  if (option === "catalog") {
    if (!layout.permissionCatalog) {
      throw new TypeError(
        'sql.modules.api-keys.options.scopes is "catalog", but there is no PermDock permission catalog to read. Run `permdock catalog`, or list the scopes.',
      );
    }
    return layout.permissionCatalog;
  }
  const scopes = ctx.list("scopes", []);
  for (const scope of scopes) {
    if (!SCOPE.test(scope)) {
      throw new TypeError(
        `sql.modules.api-keys.options.scopes: "${scope}" is not a scope. Use names such as "deals:read" or "invoice.read"`,
      );
    }
  }
  return scopes;
}

function prefixOf(ctx: ModuleContext): string {
  const prefix = ctx.text("prefix", "bs");
  if (!PREFIX.test(prefix)) {
    throw new TypeError(
      `sql.modules.api-keys.options.prefix must be lowercase letters and digits, not "${prefix}"`,
    );
  }
  return prefix;
}

function build(ctx: ModuleContext, layout: ModuleLayout): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const t = ctx.table("keys");
  const c = (logical: string): string => ctx.col("keys", logical);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = MODULE_PERMISSIONS["api-keys"];
  const can = (tenant: string, action: "manage" | "own"): string =>
    `coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission(action, permissions[action])}), false)`;
  const allowed = allowedScopes(ctx, layout);
  const prefix = sqlString(prefixOf(ctx));
  const touch = Math.max(0, Math.trunc(ctx.number("touchInterval", 60)));
  const wildcard =
    allowed === undefined && accessModel(ctx) === "permdock"
      ? `
  if '*' = any (coalesce(scopes, '{}')) then
    ${fail("API_KEY_SCOPE_WILDCARD", "PermDock checks scopes as exact permission keys, so a key cannot carry *", "22023")}
  end if;`
      : "";
  const scopeCheck = allowed
    ? `
  if exists (select 1 from unnest(coalesce(scopes, '{}')) s where s <> all (${sqlString(`{${allowed.join(",")}}`)}::text[])) then
    ${fail("API_KEY_SCOPE_UNKNOWN", "A scope is not one of sql.modules.api-keys.options.scopes", "22023")}
  end if;`
    : "";
  const json = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${c("id")},
    'organization_id', ${alias}.${c("tenant")},
    'user_id', ${alias}.${c("user")},
    'name', ${alias}.${c("name")},
    'prefix', ${alias}.${c("prefix")},
    'public_id', ${alias}.${c("publicId")},
    'scopes', to_jsonb(${alias}.${c("scopes")}),
    'rate_limit', ${alias}.${c("rateLimit")},
    'expires_at', ${alias}.${c("expiresAt")},
    'last_used_at', ${alias}.${c("lastUsedAt")},
    'revoked_at', ${alias}.${c("revokedAt")},
    'rotated_from', ${alias}.${c("rotatedFrom")},
    'created_by', ${alias}.${c("createdBy")},
    'created_at', ${alias}.${c("createdAt")}
  )`;
  // Who may change a key: a manager of its tenant, or the user it acts as.
  const mayChange = (alias: string): string =>
    `((${alias}.${c("tenant")} is not null and ${can(`${alias}.${c("tenant")}`, "manage")}) or coalesce(${alias}.${c("user")} = auth.uid(), false) or ${SERVICE_CALLER})`;

  return `${schemaPreamble(ctx)}
-- API keys: \`<prefix>_<public id>_<secret>\`. Only the SHA-256 of the secret
-- is stored. A key acts as its user (user_id), as its tenant (organization_id
-- without user_id), or as a user inside one tenant (both).
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${id},
  ${c("user")} uuid references auth.users (id) on delete cascade,
  ${c("name")} text not null check (length(trim(${c("name")})) > 0),
  ${c("prefix")} text not null check (${c("prefix")} ~ '^[a-z][a-z0-9]*$'),
  ${c("publicId")} text not null unique check (${c("publicId")} ~ '^[0-9a-f]{16}$'),
  ${c("secretHash")} text not null check (${c("secretHash")} ~ '^[0-9a-f]{64}$'),
  ${c("scopes")} text[] not null default '{}',
  ${c("rateLimit")} integer check (${c("rateLimit")} > 0),
  ${c("windowStart")} timestamptz,
  ${c("windowHits")} integer not null default 0,
  ${c("expiresAt")} timestamptz,
  ${c("lastUsedAt")} timestamptz,
  ${c("revokedAt")} timestamptz,
  ${c("rotatedFrom")} uuid references ${t} (${c("id")}) on delete set null,
  ${c("createdBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${c("createdAt")} timestamptz not null default now(),
  check (${c("tenant")} is not null or ${c("user")} is not null)
);
create index if not exists api_keys_tenant_idx on ${t} (${c("tenant")});
create index if not exists api_keys_user_idx on ${t} (${c("user")});
create index if not exists api_keys_rotated_from_idx on ${t} (${c("rotatedFrom")});
create index if not exists api_keys_created_by_idx on ${t} (${c("createdBy")});
alter table ${t} enable row level security;
revoke all on ${t} from anon, authenticated;
grant all on ${t} to service_role;

-- Creates a key. TypeScript generates the public id and the secret and sends
-- only the secret's SHA-256. A tenant key needs api_keys.manage; a personal
-- key in a tenant needs api_keys.own there.
create or replace function ${fn("create_api_key")}(
  name text,
  public_id text,
  secret_hash text,
  tenant ${id} default null,
  personal boolean default false,
  scopes text[] default '{}',
  expires_at timestamptz default null,
  rate_limit integer default null,
  prefix text default ${prefix}
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := case when personal then auth.uid() end;
  created ${t};
begin
  if personal and owner is null then
    ${fail("API_KEY_SIGN_IN", "Sign in to create a personal API key")}
  end if;
  if not personal and tenant is null then
    ${fail("API_KEY_TENANT_REQUIRED", "A tenant API key needs a tenant", "22023")}
  end if;
  if not (${SERVICE_CALLER}) then
    if not personal and not ${can("tenant", "manage")} then
      ${fail("API_KEY_FORBIDDEN", "Not allowed to manage API keys in this tenant")}
    end if;
    if personal and tenant is not null and not ${can("tenant", "own")} then
      ${fail("API_KEY_FORBIDDEN", "Not allowed to create API keys in this tenant")}
    end if;
  end if;${scopeCheck}${wildcard}
  if expires_at is not null and expires_at <= now() then
    ${fail("API_KEY_EXPIRED", "expires_at is in the past", "22023")}
  end if;
  insert into ${t} (${c("tenant")}, ${c("user")}, ${c("name")}, ${c("prefix")}, ${c("publicId")}, ${c("secretHash")}, ${c("scopes")}, ${c("rateLimit")}, ${c("expiresAt")})
  values (tenant, owner, create_api_key.name, create_api_key.prefix, create_api_key.public_id, create_api_key.secret_hash, coalesce(create_api_key.scopes, '{}'), create_api_key.rate_limit, create_api_key.expires_at)
  returning * into created;
  return ${json("created")};
end;
$$;

-- A tenant's keys for its managers, or the caller's own keys.
create or replace function ${fn("list_api_keys")}(tenant ${id} default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json("k")} order by k.${c("createdAt")} desc), '[]'::jsonb)
  from ${t} k
  where case
    when list_api_keys.tenant is null then k.${c("user")} = auth.uid()
    when ${SERVICE_CALLER} or ${can("list_api_keys.tenant", "manage")} then k.${c("tenant")} = list_api_keys.tenant
    else k.${c("tenant")} = list_api_keys.tenant and k.${c("user")} = auth.uid()
  end
$$;

create or replace function ${fn("revoke_api_key")}(key uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  found ${t};
begin
  select * into found from ${t} k where k.${c("id")} = revoke_api_key.key;
  if found.${c("id")} is null or not ${mayChange("found")} then
    ${fail("API_KEY_NOT_FOUND", "API key not found", "P0002")}
  end if;
  update ${t} k set ${c("revokedAt")} = now()
  where k.${c("id")} = found.${c("id")} and (k.${c("revokedAt")} is null or k.${c("revokedAt")} > now());
  return true;
end;
$$;

-- Replaces a key with a new secret. The old key keeps working for grace,
-- so deployments can switch over.
create or replace function ${fn("rotate_api_key")}(
  key uuid,
  public_id text,
  secret_hash text,
  grace interval default interval '1 day'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  old ${t};
  created ${t};
begin
  select * into old from ${t} k where k.${c("id")} = rotate_api_key.key for update;
  if old.${c("id")} is null or not ${mayChange("old")} then
    ${fail("API_KEY_NOT_FOUND", "API key not found", "P0002")}
  end if;
  if old.${c("revokedAt")} is not null and old.${c("revokedAt")} <= now() then
    ${fail("API_KEY_REVOKED", "A revoked API key cannot be rotated", "22023")}
  end if;
  if grace is null or grace < interval '0' then
    ${fail("API_KEY_GRACE", "grace must be zero or more", "22023")}
  end if;
  insert into ${t} (${c("tenant")}, ${c("user")}, ${c("name")}, ${c("prefix")}, ${c("publicId")}, ${c("secretHash")}, ${c("scopes")}, ${c("rateLimit")}, ${c("expiresAt")}, ${c("rotatedFrom")})
  values (old.${c("tenant")}, old.${c("user")}, old.${c("name")}, old.${c("prefix")}, rotate_api_key.public_id, rotate_api_key.secret_hash, old.${c("scopes")}, old.${c("rateLimit")}, old.${c("expiresAt")}, old.${c("id")})
  returning * into created;
  update ${t} k set ${c("revokedAt")} = now() + grace where k.${c("id")} = old.${c("id")};
  return ${json("created")};
end;
$$;

-- Server-side: checks a presented key and counts the request. Returns
-- { status: 'ok', key } or { status: 'invalid' | 'rate_limited', retry_after }.
-- It never raises for a bad key, so the counter update commits.
create or replace function ${fn("verify_api_key")}(public_id text, secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  found ${t};
  started timestamptz;
  hits integer;
begin
  select * into found from ${t} k where k.${c("publicId")} = verify_api_key.public_id;
  if found.${c("id")} is null
    or found.${c("secretHash")} <> verify_api_key.secret_hash
    or (found.${c("expiresAt")} is not null and found.${c("expiresAt")} <= now())
    or (found.${c("revokedAt")} is not null and found.${c("revokedAt")} <= now())
    or (found.${c("user")} is not null and better_supabase.user_disabled(found.${c("user")}))
    or (found.${c("tenant")} is not null and better_supabase.tenant_disabled(found.${c("tenant")}))
    or (found.${c("user")} is not null and found.${c("tenant")} is not null
      and better_supabase.organization_member_role(found.${c("tenant")}, found.${c("user")}) is null)
  then
    return jsonb_build_object('status', 'invalid');
  end if;
  if found.${c("rateLimit")} is not null then
    update ${t} k set
      ${c("windowStart")} = case when k.${c("windowStart")} is null or k.${c("windowStart")} + interval '1 minute' <= now() then now() else k.${c("windowStart")} end,
      ${c("windowHits")} = case when k.${c("windowStart")} is null or k.${c("windowStart")} + interval '1 minute' <= now() then 1 else k.${c("windowHits")} + 1 end
    where k.${c("id")} = found.${c("id")}
    returning k.${c("windowStart")}, k.${c("windowHits")} into started, hits;
    if hits > found.${c("rateLimit")} then
      return jsonb_build_object(
        'status', 'rate_limited',
        'retry_after', greatest(1, ceil(extract(epoch from started + interval '1 minute' - now()))::integer)
      );
    end if;
  end if;
  if found.${c("lastUsedAt")} is null or found.${c("lastUsedAt")} + interval '${touch} seconds' <= now() then
    update ${t} k set ${c("lastUsedAt")} = now() where k.${c("id")} = found.${c("id")};
  end if;
  return jsonb_build_object('status', 'ok', 'key', ${json("found")});
end;
$$;

-- For policies: whether the request's API key carries scope. Requests
-- without an API key (a signed-in user) are not limited by scopes.
--   using (organization_id = better_supabase.api_key_tenant() and better_supabase.has_scope('deals:read'))
create or replace function ${fn("has_scope")}(scope text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when auth.jwt() -> 'api_key' is null then true
    else coalesce(auth.jwt() -> 'api_key' -> 'scopes', '[]'::jsonb) ?| array['*', has_scope.scope]
  end
$$;

-- The tenant of the request's tenant API key, or null.
create or replace function ${fn("api_key_tenant")}()
returns ${id}
language sql
stable
set search_path = ''
as $$
  select nullif(auth.jwt() -> 'api_key' ->> 'organization_id', '')::${id}
$$;

revoke execute on function ${fn("create_api_key")}(text, text, text, ${id}, boolean, text[], timestamptz, integer, text) from public, anon;
revoke execute on function ${fn("list_api_keys")}(${id}) from public, anon;
revoke execute on function ${fn("revoke_api_key")}(uuid) from public, anon;
revoke execute on function ${fn("rotate_api_key")}(uuid, text, text, interval) from public, anon;
revoke execute on function ${fn("verify_api_key")}(text, text) from public, anon, authenticated;
grant execute on function ${fn("create_api_key")}(text, text, text, ${id}, boolean, text[], timestamptz, integer, text) to authenticated, service_role;
grant execute on function ${fn("list_api_keys")}(${id}) to authenticated, service_role;
grant execute on function ${fn("revoke_api_key")}(uuid) to authenticated, service_role;
grant execute on function ${fn("rotate_api_key")}(uuid, text, text, interval) to authenticated, service_role;
grant execute on function ${fn("verify_api_key")}(text, text) to service_role;
grant execute on function ${fn("has_scope")}(text) to anon, authenticated, service_role;
grant execute on function ${fn("api_key_tenant")}() to anon, authenticated, service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "create_api_key",
      args: [
        "text",
        "text",
        "text",
        "{id}",
        "boolean",
        "text[]",
        "timestamptz",
        "integer",
        "text",
      ],
      returns: "jsonb",
    },
    { name: "list_api_keys", args: ["{id}"], returns: "jsonb" },
    { name: "revoke_api_key", args: ["uuid"], returns: "boolean" },
    {
      name: "rotate_api_key",
      args: ["uuid", "text", "text", "interval"],
      returns: "jsonb",
    },
    { name: "verify_api_key", args: ["text", "text"], returns: "jsonb" },
    { name: "has_scope", args: ["text"], returns: "boolean" },
    { name: "api_key_tenant", args: [], returns: "{id}" },
  ];
}

export const API_KEYS: ModuleDefinition = {
  name: "api-keys",
  title: "API keys",
  description:
    "Hashed API keys for tenants and users with scopes, expiry, rotation with a grace period, a per-key rate limit and throttled last-used tracking. verify_api_key() backs apiKeyResolver; has_scope() and api_key_tenant() go in policies.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
