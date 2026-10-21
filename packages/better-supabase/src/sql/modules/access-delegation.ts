import type { ModuleContext } from "../context.ts";
import type { ModuleLayout } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";

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
  ctx: ModuleContext,
  layout: ModuleLayout,
): string {
  const scopes = { ...layout.delegationScopes, ...ctx.modules.access?.scopes };

  const entries = Object.entries(scopes);

  const body =
    entries.length === 0
      ? "array[scope]"
      : `case scope
    ${entries.map(([scope, keys]) => `when ${sqlString(scope)} then array[${keys.map(sqlString).join(", ")}]::text[]`).join("\n    ")}
    else array[scope]
  end`;

  return `
-- The permission keys an OAuth scope grants a delegated token
-- (authorization.delegation.scopes, blocks.access.scopes). A scope
-- without an entry grants the key with its own name.
create or replace function better_supabase.scope_permissions(scope text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select ${body}
$$;

-- False when the token is narrower than the permission: a permission cap
-- (bs_permission_cap) without the key, or a delegated token whose scopes
-- don't map to it. True for every other token, the service role included.
create or replace function better_supabase.cap_allows(permission text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when jwt is null then true
    when jsonb_typeof(jwt -> 'bs_permission_cap') = 'array'
      and not exists (
        select 1 from jsonb_array_elements_text(jwt -> 'bs_permission_cap') c(key)
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
$$;`;
}
