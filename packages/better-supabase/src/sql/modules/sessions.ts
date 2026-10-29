import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout, BlockSqlDefinition } from "../module-types.ts";

import { AUTHZ_EVENT, AUTHZ_TOPIC } from "../../core/authz-topic.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { tableGlobs } from "../schema-scan.ts";
import { SCHEMA } from "../shared.ts";
import { qualifiedTable } from "./grants.ts";

/** The `schema.table` names `blocks['sessions'].options.policies` covers. */
export function sessionPolicyTables(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): readonly string[] {
  if (!ctx.flag("policies", false)) {
    return [];
  }

  const exclude = tableGlobs(ctx.list("exclude", []));

  return (layout.declaredTables ?? []).filter(
    (table) => !exclude.some((pattern) => pattern.test(table)),
  );
}

/**
 * `blocks['sessions'].options.policies`: a restrictive session policy on every
 * table the schema files create in `schemas`, except `exclude`.
 */
function sessionPolicies(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  const tables = sessionPolicyTables(ctx, layout);

  if (tables.length === 0) {
    return "";
  }

  const statements = tables.map((table) => {
    const target = qualifiedTable(table);

    return renderPolicy(
      makePolicy({
        table: target,
        name: "bsb_session_active",
        roles: ["authenticated"],
        permissive: false,
        using: "(select better_supabase.session_active())",
        check: "(select better_supabase.session_active())",
      }),
      { drop: true, target },
    );
  });

  return `

-- blocks['sessions'].options.policies: every table in the schema files,
-- except blocks['sessions'].options.exclude. \`upgrade\` rewrites these.
${statements.join("\n")}`;
}

const WHERE = "blocks['sessions'].options.bootstrap";

const BOOTSTRAP_NAME = /^[a-z][a-z0-9_]*$/;

const FUNCTION_NAME = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;

/** `blocks['sessions'].options.bootstrap`: wrapper name to `schema.function`. */
function bootstrapFunctions(
  ctx: BlockSqlContext,
): readonly (readonly [string, string])[] {
  const raw = ctx.option("bootstrap");

  if (raw === undefined) {
    return [];
  }

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      `${WHERE} must map names to functions, e.g. { home: "app.home_data" }`,
    );
  }

  return Object.entries(raw).map(([name, fn]) => {
    if (!BOOTSTRAP_NAME.test(name)) {
      throw new TypeError(
        `${WHERE}.${name} must be a lowercase name (letters, digits, _)`,
      );
    }

    if (typeof fn !== "string" || !FUNCTION_NAME.test(fn)) {
      throw new TypeError(
        `${WHERE}.${name} must name a function as schema.function, e.g. "app.home_data"`,
      );
    }

    return [name, fn] as const;
  });
}

/**
 * Whether the database keeps a live authorization version: the module's own
 * table (`authzVersions`) or the provider's (`authorization.versions`).
 */
function hasVersionSource(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): boolean {
  return (
    layout.authzVersionsProvider !== undefined ||
    ctx.flag("authzVersions", false)
  );
}

/**
 * One wrapper per `bootstrap` entry: the session check, the authorization
 * version and the app function's data in one jsonb, so a page's first query
 * carries all three. It runs as the caller, so the app function's policies
 * apply. `authz_version` is the live version when the database keeps one, so a
 * seeded version cache never hides a role change the token predates;
 * `token_authz_version` is the token's.
 */
function bootstrapWrappers(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  const functions = bootstrapFunctions(ctx);

  if (functions.length === 0) {
    return "";
  }

  const live = hasVersionSource(ctx, layout)
    ? "to_jsonb(better_supabase.caller_authz_version())"
    : "auth.jwt() -> 'authz_ver'";

  const wrappers = functions.map(([name, fn]) => {
    const wrapper = `better_supabase.bootstrap_${name}`;

    return `create or replace function ${wrapper}(args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select better_supabase.session_active()) then
    return jsonb_build_object(
      'session_active', false,
      'authz_version', auth.jwt() -> 'authz_ver',
      'token_authz_version', auth.jwt() -> 'authz_ver',
      'tenant', args ->> 'tenant',
      'data', null
    );
  end if;
  return jsonb_build_object(
    'session_active', true,
    'authz_version', ${live},
    'token_authz_version', auth.jwt() -> 'authz_ver',
    'tenant', args ->> 'tenant',
    'data', to_jsonb(${fn}(args))
  );
end;
$$;

revoke execute on function ${wrapper}(jsonb) from public, anon;
grant execute on function ${wrapper}(jsonb) to authenticated;`;
  });

  return `

-- blocks['sessions'].options.bootstrap: bsb.bootstrap({ rpc }) calls these.
-- Each checks the session and returns the caller's authorization version
-- (the live one when the database keeps it, and the token's) with the app
-- function's data, so a cache miss is one query.
${wrappers.join("\n\n")}`;
}

/**
 * `better_supabase.caller_authz_version()`: the caller's own live version, for
 * the bootstrap wrappers and for clients that catch up after a missed
 * broadcast. Reads the provider's function when it keeps the versions.
 */
function callerAuthzVersion(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  if (!hasVersionSource(ctx, layout)) {
    return "";
  }

  const provider = layout.authzVersionsProvider;

  const source = provider
    ? `${provider.function}(auth.uid())`
    : "better_supabase.authz_version(auth.uid())";

  return `

-- The caller's own authorization version, null without a signed-in user.
-- Clients compare it with the token's authz_ver to catch up on a broadcast
-- they missed.${provider ? `\n-- ${provider.name} keeps the versions in ${provider.function}.` : ""}
create or replace function better_supabase.caller_authz_version()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return null;
  end if;
  return ${source};
end;
$$;

revoke execute on function better_supabase.caller_authz_version() from public, anon;
grant execute on function better_supabase.caller_authz_version() to authenticated;`;
}

/**
 * `blocks['sessions'].options.authzVersions`: a version per user that a trigger
 * bumps, the access token hook copies into `authz_ver`, and Realtime broadcasts
 * on the shared server topic and on the user's own `authz:<uid>`. A provider
 * that keeps the versions (`authorization.versions`) owns all of that, so the
 * module writes none of it.
 */
function authzVersions(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (
    !ctx.flag("authzVersions", false) ||
    layout.authzVersionsProvider !== undefined
  ) {
    return "";
  }

  const payload =
    "jsonb_build_object('user_id', new.user_id, 'version', new.version)";

  return `

-- blocks['sessions'].options.authzVersions: one authorization version per
-- user. Attach better_supabase.bump_authz_version() to the tables a user's
-- access comes from; the access token hook reads better_supabase.authz_version().
create table if not exists better_supabase.user_authz_versions (
  user_id uuid primary key references auth.users on delete cascade,
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table better_supabase.user_authz_versions enable row level security;

revoke all on better_supabase.user_authz_versions from public, anon, authenticated;
grant select on better_supabase.user_authz_versions to supabase_auth_admin;
grant all on better_supabase.user_authz_versions to service_role;

${renderPolicy(
  makePolicy({
    table: "better_supabase.user_authz_versions",
    name: "bsb_authz_versions_auth_admin",
    command: "select",
    roles: ["supabase_auth_admin"],
    using: "true",
  }),
  { drop: true, target: "better_supabase.user_authz_versions" },
)}

-- The version the access token hook copies into authz_ver; 0 before the
-- first bump.
create or replace function better_supabase.authz_version(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select v.version from better_supabase.user_authz_versions v where v.user_id = p_user),
    0
  )
$$;

revoke execute on function better_supabase.authz_version(uuid) from public, anon, authenticated;
grant execute on function better_supabase.authz_version(uuid) to supabase_auth_admin, service_role;

-- Bumps the versions of many users at once, for changes no trigger sees.
create or replace function better_supabase.bump_authz_versions(p_users uuid[])
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into better_supabase.user_authz_versions as v (user_id)
  select distinct u from unnest(p_users) u where u is not null
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now()
$$;

revoke execute on function better_supabase.bump_authz_versions(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.bump_authz_versions(uuid[]) to service_role;

-- A row trigger: bumps the user in the row's user_id column, or in the column
-- named by the trigger's first argument, before and after an update.
create or replace function better_supabase.bump_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  col text := coalesce(tg_argv[0], 'user_id');
begin
  perform better_supabase.bump_authz_versions(array[
    (to_jsonb(new) ->> col)::uuid,
    (to_jsonb(old) ->> col)::uuid
  ]);
  return null;
end;
$$;

revoke execute on function better_supabase.bump_authz_version() from public, anon, authenticated;

-- Sends { user_id, version } as the changed event on the server topic, which
-- no user may join, and on the user's own authz:<uid> topic.
create or replace function better_supabase.broadcast_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${ctx.broadcast(`'${AUTHZ_TOPIC}'`, `'${AUTHZ_EVENT}'`, payload, { indent: "  " })}
  ${ctx.broadcast("'authz:' || new.user_id::text", `'${AUTHZ_EVENT}'`, payload, { indent: "  " })}
  return null;
end;
$$;

revoke execute on function better_supabase.broadcast_authz_version() from public, anon, authenticated;

drop trigger if exists bsb_authz_versions_broadcast on better_supabase.user_authz_versions;
create trigger bsb_authz_versions_broadcast
  after insert or update on better_supabase.user_authz_versions
  for each row execute function better_supabase.broadcast_authz_version();

do $$
begin
  if to_regclass('realtime.messages') is not null then
    ${renderPolicy(
      makePolicy({
        table: "realtime.messages",
        name: "bsb_authz_versions_receive",
        command: "select",
        roles: ["authenticated"],
        using: `realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'authz:' || (select auth.uid())::text`,
      }),
      { drop: true, target: "realtime.messages" },
    )}
  end if;
end;
$$;`;
}

export const SESSIONS: BlockSqlDefinition = {
  internal: ["session_active"],
  name: "sessions",
  names: {
    tables: {},
    options: ["authzVersions", "bootstrap", "exclude", "policies"],
  },
  title: "Session revocation",
  description:
    "session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.",
  requires: [],
  target: "schema",
  build: (ctx, layout) => `${SCHEMA}

-- An access token stays valid until it expires, even after its session is
-- signed out or its user is deleted. This checks the session behind it.
-- Tokens without a session_id claim (signed by the app) and support tokens
-- (with an act claim, whose session the support module ends) pass.
-- authenticated can't read auth.sessions, so the check runs as the owner.
create or replace function better_supabase.session_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  session text := claims ->> 'session_id';
begin
  if claims -> 'act' is not null or session is null then
    return true;
  end if;
  if session !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1
    from auth.sessions s
    join auth.users u on u.id = s.user_id
    where s.id = session::uuid
      and s.user_id = auth.uid()
      and (s.not_after is null or s.not_after > now())
      and (u.banned_until is null or u.banned_until <= now())
      and u.deleted_at is null
  );
end;
$$;

revoke execute on function better_supabase.session_active() from public, anon;
grant execute on function better_supabase.session_active() to authenticated;

-- The last sign-in of many users in one query, for admin lists. auth.users
-- isn't readable through the Data API, so only the service role calls this.
create or replace function better_supabase.last_sign_ins(p_users uuid[])
returns table (user_id uuid, last_sign_in_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.last_sign_in_at
  from auth.users u
  where u.id = any(p_users)
$$;

revoke execute on function better_supabase.last_sign_ins(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.last_sign_ins(uuid[]) to service_role;

-- The caller's own unexpired sessions, most recently active first, with the
-- one behind the current token marked.
create or replace function better_supabase.list_my_sessions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'createdAt', s.created_at,
    'lastActiveAt', coalesce(s.updated_at, s.created_at),
    'userAgent', s.user_agent,
    'ip', host(s.ip),
    'aal', s.aal,
    'current', s.id::text = auth.jwt() ->> 'session_id'
  ) order by coalesce(s.updated_at, s.created_at) desc), '[]'::jsonb)
  from auth.sessions s
  where s.user_id = (select auth.uid())
    and (s.not_after is null or s.not_after > now())
$$;

revoke execute on function better_supabase.list_my_sessions() from public, anon;
grant execute on function better_supabase.list_my_sessions() to authenticated;

-- Ends one of the caller's sessions: its refresh tokens go with it, and
-- session_active() turns false for its access tokens.
create or replace function better_supabase.end_my_session(session uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  delete from auth.sessions s
  where s.id = end_my_session.session
    and s.user_id = (select auth.uid());
  return found;
end;
$$;

revoke execute on function better_supabase.end_my_session(uuid) from public, anon;
grant execute on function better_supabase.end_my_session(uuid) to authenticated;

-- Restrictive, so it applies on top of the table's other policies. Wrapped in
-- a select, it runs one indexed lookup per statement:
-- create policy session_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.session_active()))
--   with check ((select better_supabase.session_active()));${sessionPolicies(ctx, layout)}${authzVersions(ctx, layout)}${callerAuthzVersion(ctx, layout)}${bootstrapWrappers(ctx, layout)}`,
};
