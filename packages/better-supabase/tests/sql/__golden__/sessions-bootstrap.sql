-- blocks['sessions'].options.bootstrap: bsb.bootstrap({ rpc }) calls these.
-- Each checks the session and returns the caller's authorization version
-- (the live one when the database keeps it, and the token's) with the app
-- function's data, so a cache miss is one query.
create or replace function better_supabase.bootstrap_home(args jsonb default '{}'::jsonb)
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
    'authz_version', auth.jwt() -> 'authz_ver',
    'token_authz_version', auth.jwt() -> 'authz_ver',
    'tenant', args ->> 'tenant',
    'data', to_jsonb(app.home_data(args))
  );
end;
$$;

revoke execute on function better_supabase.bootstrap_home(jsonb) from public, anon;
grant execute on function better_supabase.bootstrap_home(jsonb) to authenticated;

create or replace function better_supabase.bootstrap_inbox(args jsonb default '{}'::jsonb)
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
    'authz_version', auth.jwt() -> 'authz_ver',
    'token_authz_version', auth.jwt() -> 'authz_ver',
    'tenant', args ->> 'tenant',
    'data', to_jsonb(app.inbox(args))
  );
end;
$$;

revoke execute on function better_supabase.bootstrap_inbox(jsonb) from public, anon;
grant execute on function better_supabase.bootstrap_inbox(jsonb) to authenticated;