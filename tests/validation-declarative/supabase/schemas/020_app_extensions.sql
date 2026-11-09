-- What the app adds to the adopted tables and on top of them. better-supabase
-- never drops or copies back anything in this file.
alter table public.memberships add column invited_by uuid references auth.users (id) on delete set null;
alter table public.organizations add constraint organizations_slug_format check (slug ~ '^[a-z0-9-]+$');
create unique index organizations_slug_key on public.organizations (lower(slug));
comment on column public.memberships.invited_by is 'The member who sent the invitation.';

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  archived_at timestamptz,
  created_at timestamptz not null default now()
);

create index projects_organization_id_idx on public.projects (organization_id);

alter table public.projects enable row level security;

grant select, insert, update, delete on public.projects to authenticated;
grant all on public.projects to service_role;

create policy projects_member_select on public.projects
  for select to authenticated
  using (organization_id in (select better_supabase.member_organization_ids()));

create policy projects_member_insert on public.projects
  for insert to authenticated
  with check (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')));

create policy projects_member_update on public.projects
  for update to authenticated
  using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
  with check (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')));

create policy projects_member_delete on public.projects
  for delete to authenticated
  using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')));

create function public.projects_reject_archived_rename() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.archived_at is not null and new.name <> old.name then
    raise exception 'an archived project cannot be renamed'
      using hint = 'PROJECT_ARCHIVED';
  end if;
  return new;
end;
$$;

create trigger projects_reject_archived_rename
  before update on public.projects
  for each row execute function public.projects_reject_archived_rename();

create view public.my_organizations with (security_invoker = true) as
  select o.id, o.name, o.slug
  from public.organizations o
  where o.id in (select better_supabase.member_organization_ids());

grant select on public.my_organizations to authenticated;
