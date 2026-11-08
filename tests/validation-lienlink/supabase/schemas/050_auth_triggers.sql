-- App triggers on auth.users, beside the profile trigger the profiles block
-- installs.
create function public.lienlink_on_user_created() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_signups (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

revoke all on function public.lienlink_on_user_created() from public, anon, authenticated;

create trigger lienlink_on_user_created
  after insert on auth.users
  for each row execute function public.lienlink_on_user_created();
