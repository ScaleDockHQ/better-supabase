import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { interactiveOnlyKeys } from "./permissions-operations.ts";

/**
 * The cap check for the caller; a question about another user isn't narrowed by
 * the caller's token.
 */
export const capFor = (member: string, permission: string): string =>
  `(${member} is distinct from auth.uid() or better_supabase.cap_allows(${permission}))`;

/**
 * `scope_permissions` and `cap_allows`: a delegated token (a `client_id`, or an
 * `act` chain that is not a support or impersonation level) holds only the keys
 * its scopes map to, and a `forContext({ permissions })` cap holds only its
 * keys. The access functions apply both, so every policy and module that asks
 * them is narrowed without calling `token_scope_allows`.
 */
export function delegationSql(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  const scopes = {
    ...layout.delegationScopes,
    ...ctx.modules.permissions?.scopes,
  };

  const entries = Object.entries(scopes);

  const body =
    entries.length === 0
      ? "array[scope]"
      : `case scope
    ${entries.map(([scope, keys]) => `when ${sqlString(scope)} then array[${keys.map(sqlString).join(", ")}]::text[]`).join("\n    ")}
    else array[scope]
  end`;

  const interactive = interactiveOnlyKeys(ctx, layout);

  const owner = ctx.installedModules.includes("organizations")
    ? ctx.of("organizations").text("ownerRole", "owner")
    : undefined;

  return `
-- True for a user's own session and for no token at all. False for an API
-- key (api_key), an OAuth client (client_id) and an act chain (an agent, a
-- delegation, support or impersonation).
create or replace function better_supabase.interactive_session()
returns boolean
language sql
stable
set search_path = ''
as $$
  select auth.jwt() is null
    or (auth.jwt() -> 'api_key' is null
      and coalesce(auth.jwt() ->> 'client_id', '') = ''
      and auth.jwt() -> 'act' is null)
$$;

-- The permission keys only a signed-in user gets (the built-in
-- interactive-only operations, authorization.delegation.interactiveOnly and
-- blocks.permissions.interactiveOnly): cap_allows refuses them to every
-- other session, whatever its scopes.
create or replace function better_supabase.interactive_only(permission text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select ${interactive.length === 0 ? "false" : `coalesce(permission = any (array[${interactive.map(sqlString).join(", ")}]::text[]), false)`}
$$;

-- The roles only a signed-in user grants or takes away: the organization
-- owner role. can_assign refuses them to every other session.
create or replace function better_supabase.interactive_only_role(role text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select ${owner === undefined ? "false" : `coalesce(role = ${sqlString(owner)}, false)`}
$$;

-- The permission keys an OAuth scope grants a delegated token
-- (authorization.delegation.scopes, blocks.permissions.scopes). A scope
-- without an entry grants the key with its own name.
create or replace function better_supabase.scope_permissions(scope text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select ${body}
$$;

-- False when the token is narrower than the permission: an interactive-only
-- key outside a user's own session, a permission cap (bsb_permission_cap)
-- without the key, or a delegated token whose scopes don't map to it. True
-- for every other token, the service role included.
-- 0.14 named the cap bs_permission_cap; 0.15 still reads it when the new
-- claim is missing, so a cap from an older runAs keeps narrowing.
create or replace function better_supabase.cap_allows(permission text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when jwt is null then true
    when better_supabase.interactive_only(cap_allows.permission)
      and not better_supabase.interactive_session() then false
    when jsonb_typeof(cap) = 'array'
      and not exists (
        select 1 from jsonb_array_elements_text(cap) c(key)
        where better_supabase.permission_matches(c.key, cap_allows.permission)
      ) then false
    when coalesce(jwt ->> 'client_id', '') = ''
      and (jwt -> 'act' is null
        or (jsonb_typeof(jwt -> 'act') = 'object'
          and jwt -> 'act' ->> 'kind' in ('support', 'impersonation'))) then true
    else exists (
      select 1
      from unnest(case jsonb_typeof(jwt -> 'scope')
          when 'string' then regexp_split_to_array(btrim(jwt ->> 'scope'), '\\s+')
          when 'array' then array(select jsonb_array_elements_text(jwt -> 'scope'))
          else '{}'::text[]
        end) s(scope)
      cross join lateral unnest(better_supabase.scope_permissions(s.scope)) k(key)
      where s.scope <> ''
        and better_supabase.permission_matches(k.key, cap_allows.permission)
    )
  end
  from (select auth.jwt() as jwt) as token
  cross join lateral (
    select coalesce(jwt -> 'bsb_permission_cap', jwt -> 'bs_permission_cap') as cap
  ) as capped
$$;`;
}
