import type { BlockSqlContext } from "../context.ts";
import type {
  BlockSqlAccessProvider,
  BlockSqlLayout,
} from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { accessModel } from "./permissions-model.ts";

/**
 * `my_permissions`: the caller's permission keys in a tenant, for client checks
 * such as `usePermissions` and `<Can>`.
 */
/**
 * `bootstrap_permissions`: one compact payload for every tenant the caller
 * belongs to, instead of `my_permissions` once per tenant. The bitset matches
 * `compactBootstrapPermissions` (least significant bit first, base64url).
 */
export function bootstrapPermissionsSql(): string {
  return `-- Compact permissions for the caller: keys once, then a bitset per tenant.
create or replace function better_supabase.permission_bitset(all_keys text[], held text[])
returns text
language plpgsql
immutable
as $$
declare
  width integer := ceil(coalesce(cardinality(all_keys), 0) / 8.0);
  bytes bytea;
  i integer;
  slot integer;
  value integer;
begin
  if width < 1 then
    return '';
  end if;
  bytes := decode(repeat('00', width), 'hex');
  if held is null then
    return translate(rtrim(encode(bytes, 'base64'), '='), '+/', '-_');
  end if;
  for i in 1 .. coalesce(cardinality(all_keys), 0) loop
    if all_keys[i] = any (held) then
      slot := (i - 1) / 8;
      value := get_byte(bytes, slot) | (1 << ((i - 1) % 8));
      bytes := set_byte(bytes, slot, value);
    end if;
  end loop;
  return translate(rtrim(encode(bytes, 'base64'), '='), '+/', '-_');
end;
$$;

revoke execute on function better_supabase.permission_bitset(text[], text[]) from public, anon, authenticated;

create or replace function better_supabase.bootstrap_permissions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with keys as (
    select coalesce(array_agg(distinct key order by key), '{}'::text[]) as keys
    from better_supabase.member_organization_ids(null) as tenant(id),
      lateral unnest(better_supabase.member_permissions(auth.uid(), tenant.id)) as key
    where auth.uid() is not null
  )
  select case
    when auth.uid() is null then jsonb_build_object(
      'apiVersion', 1, 'form', 'compact', 'keys', '[]'::jsonb, 'tenants', '{}'::jsonb
    )
    else jsonb_build_object(
      'apiVersion', 1,
      'form', 'compact',
      'keys', to_jsonb(keys.keys),
      'tenants', coalesce((
        select jsonb_object_agg(
          tenant.id::text,
          better_supabase.permission_bitset(
            keys.keys,
            better_supabase.member_permissions(auth.uid(), tenant.id)
          )
        )
        from better_supabase.member_organization_ids(null) as tenant(id)
      ), '{}'::jsonb)
    )
  end
  from keys
$$;

revoke execute on function better_supabase.bootstrap_permissions() from public, anon;
grant execute on function better_supabase.bootstrap_permissions() to authenticated;
`;
}

export function myPermissionsSql(id: string): string {
  return `-- The caller's permission keys in a tenant, for client checks. With keys,
-- the ones can() grants: every model answers, including a provider and
-- delegated tokens. Without them, the keys the model lists for the member,
-- wildcards as granted (the custom model lists none).
create or replace function better_supabase.my_permissions(tenant ${id}, keys text[] default null)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when auth.uid() is null or my_permissions.tenant is null then '{}'::text[]
    when my_permissions.keys is not null then coalesce((
      select array_agg(distinct k order by k)
      from unnest(my_permissions.keys) as k
      where better_supabase.can('tenant', my_permissions.tenant, k)
    ), '{}'::text[])
    when better_supabase.tenant_disabled(my_permissions.tenant) then '{}'::text[]
    else coalesce((
      select array_agg(distinct p order by p)
      from unnest(better_supabase.member_permissions(auth.uid(), my_permissions.tenant)) as p
      where better_supabase.cap_allows(p)
    ), '{}'::text[])
  end
$$;`;
}

/**
 * `permission_claims(user_id, tenant)`: the claim for one tenant, the active
 * one, so the token stays small with many memberships.
 */
export function oneTenantClaims(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  const model = accessModel(ctx);

  const perMember =
    model === "roles" ||
    model === "catalog" ||
    (model === "provider" &&
      layout.accessProvider?.functions.permissionsFor !== undefined);

  const keys = perMember
    ? "to_jsonb(better_supabase.member_permissions(permission_claims.user_id, permission_claims.tenant))"
    : "better_supabase.permission_claims(permission_claims.user_id) -> (permission_claims.tenant::text)";

  return `-- { [tenant]: permission keys } for one tenant, the active one; {} without a
-- tenant or when the model can't answer.
create or replace function better_supabase.permission_claims(user_id uuid, tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when permission_claims.tenant is null then '{}'::jsonb
    else coalesce(jsonb_strip_nulls(jsonb_build_object(permission_claims.tenant::text, ${keys})), '{}'::jsonb)
  end
$$;`;
}

/**
 * `keys` without the keys the provider doesn't mark `sqlComplete`, so the
 * `permissions` claim never grants what the SQL functions can't decide. A
 * provider built without `sqlCompleteKeys` keeps every key.
 */
export function sqlCompleteOnly(
  provider: BlockSqlAccessProvider,
  keys: string,
): string {
  if (provider.sqlCompleteKeys === undefined) {
    return keys;
  }

  if (provider.sqlCompleteKeys.length === 0) {
    return "'{}'::text[]";
  }

  const complete = provider.sqlCompleteKeys.map(sqlString).join(", ");

  return `coalesce(array(select k from unnest(${keys}) as k where k = any(array[${complete}]::text[])), '{}'::text[])`;
}

/**
 * How an access token hook writes the `permissions` claim, as a comment. A
 * provider whose hook owns the claim gets a note instead, so the app's hook
 * doesn't write it a second time.
 */
export function permissionClaimHook(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  const claim = ctx.claims.permissions;
  const provider = layout.accessProvider;

  if (provider?.ownsPermissions === true) {
    return `-- The permission claim: ${provider.name}'s access token hook writes
-- "${claim}" itself, so leave it out of any other hook.`;
  }

  const marker = provider?.truncatedClaim ?? `${claim}_truncated`;

  return `-- The permission claim: { [tenant id]: permission keys }, for the access
-- token hook when the app checks permissions from the token. Write the
-- active tenant only, and mark the claim truncated when it outgrows the
-- token budget, so readers ask the database instead:
--   declare
--     tenant text := event #>> '{claims,app_metadata,${ctx.claims.tenant}}';
--     keys jsonb := better_supabase.permission_claims((event ->> 'user_id')::uuid, tenant::${ctx.idType});
--   begin
--     if octet_length(keys::text) > 2048 then
--       event := jsonb_set(event, '{claims,${marker}}', 'true');
--       keys := '{}'::jsonb;
--     end if;
--     return jsonb_set(event, '{claims,${claim}}', keys);`;
}
