-- The caller's uploaded avatar, as an object path in the avatars bucket
-- (`{userId}/avatar-{version}.{ext}`); null removes it. A path outside the
-- caller's own folder is refused, so a profile never points at another
-- user's picture.
create or replace function public.set_my_avatar_path(avatar_path text)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  if set_my_avatar_path.avatar_path is not null
    and split_part(set_my_avatar_path.avatar_path, '/', 1) <> (select auth.uid())::text then
    raise exception 'The avatar must be in your own folder' using errcode = '42501', hint = 'AVATAR_PATH_FORBIDDEN';
  end if;
  update better_supabase.profiles p
  set avatar_path = set_my_avatar_path.avatar_path, updated_at = now()
  where p.id = (select auth.uid());
end;
$$;

revoke execute on function public.set_my_avatar_path(text) from public, anon;

grant execute on function public.set_my_avatar_path(text) to authenticated, service_role;
