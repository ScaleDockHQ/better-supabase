import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout, BlockSqlDefinition } from "../module-types.ts";

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

export const SESSIONS: BlockSqlDefinition = {
  internal: ["session_active"],
  name: "sessions",
  names: { tables: {}, options: ["exclude", "policies"] },
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
--   with check ((select better_supabase.session_active()));${sessionPolicies(ctx, layout)}`,
};
