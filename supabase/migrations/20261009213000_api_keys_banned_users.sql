create or replace function "better_supabase"."verify_api_key"(public_id text, secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  found "better_supabase"."api_keys";
  started timestamptz;
  hits integer;
begin
  select * into found from "better_supabase"."api_keys" k where k."public_id" = verify_api_key.public_id;
  if found."id" is null
    or found."secret_hash" <> verify_api_key.secret_hash
    or (found."expires_at" is not null and found."expires_at" <= now())
    or (found."revoked_at" is not null and found."revoked_at" <= now())
    or (found."user_id" is not null and better_supabase.user_disabled(found."user_id"))
    or (found."user_id" is not null and exists (
      select 1 from auth.users u
      where u.id = found."user_id" and (u.banned_until > now() or u.deleted_at is not null)
    ))
    or (found."organization_id" is not null and better_supabase.tenant_disabled(found."organization_id"))
    or (found."user_id" is not null and found."organization_id" is not null
      and better_supabase.organization_member_role(found."organization_id", found."user_id") is null)
  then
    return jsonb_build_object('status', 'invalid');
  end if;
  if found."rate_limit" is not null then
    update "better_supabase"."api_keys" k set
      "window_start" = case when (k."window_start" is null or k."window_start" + interval '1 minute' <= now()) then now() else k."window_start" end,
      "window_hits" = case when (k."window_start" is null or k."window_start" + interval '1 minute' <= now()) then 1 else k."window_hits" + 1 end,
      "last_used_at" = case when case when (k."window_start" is null or k."window_start" + interval '1 minute' <= now()) then 1 else k."window_hits" + 1 end <= k."rate_limit" and (k."last_used_at" is null or k."last_used_at" + interval '60 seconds' <= now()) then now() else k."last_used_at" end
    where k."id" = found."id"
    returning k."window_start", k."window_hits" into started, hits;
    if hits > found."rate_limit" then
      return jsonb_build_object(
        'status', 'rate_limited',
        'retry_after', greatest(1, ceil(extract(epoch from started + interval '1 minute' - now()))::integer)
      );
    end if;
  elsif (found."last_used_at" is null or found."last_used_at" + interval '60 seconds' <= now()) then
    update "better_supabase"."api_keys" k set "last_used_at" = now() where k."id" = found."id";
  end if;
  return jsonb_build_object('status', 'ok', 'key', jsonb_build_object(
    'id', found."id",
    'organization_id', found."organization_id",
    'user_id', found."user_id",
    'name', found."name",
    'prefix', found."prefix",
    'public_id', found."public_id",
    'scopes', to_jsonb(found."scopes"),
    'rate_limit', found."rate_limit",
    'expires_at', found."expires_at",
    'last_used_at', found."last_used_at",
    'revoked_at', found."revoked_at",
    'rotated_from', found."rotated_from",
    'created_by', found."created_by",
    'created_at', found."created_at",
    'state', case
      when found."revoked_at" is not null and found."revoked_at" <= now() then 'revoked'
      when found."expires_at" is not null and found."expires_at" <= now() then 'expired'
      when found."revoked_at" is not null then 'grace'
      else 'active'
    end
  ));
end;
$$;
