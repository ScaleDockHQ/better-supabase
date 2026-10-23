-- Sends `{ user_id, version }` as the `changed` event on the private
-- `authz-versions` topic. No `realtime.messages` policy admits users, so only
-- a service-role client receives it.
create or replace function rbac.broadcast_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('user_id', new.user_id, 'version', new.version),
    'changed',
    'authz-versions',
    true
  );

  return null;
end;
$$;

revoke execute on function rbac.broadcast_authz_version() from authenticated, anon, public;
