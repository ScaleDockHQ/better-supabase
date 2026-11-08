-- The app's views over the block tables. Clients read these; writes go through
-- the blocks' functions, except job_attachments, which takes inserts through
-- an instead of trigger. better-supabase never creates or drops them.
create view public.organizations with (security_invoker = true) as
  select id, name, slug, created_at, disabled_at, deleted_at
  from better_supabase.organizations;

create view public.memberships with (security_invoker = true) as
  select id, organization_id, user_id, role, created_at
  from better_supabase.memberships;

create view public.teams with (security_invoker = true) as
  select id, tenant_id as organization_id, name, slug, description, status, created_at, updated_at
  from better_supabase.teams;

create view public.team_members with (security_invoker = true) as
  select team_id, user_id, created_at
  from better_supabase.team_members;

create view public.profiles with (security_invoker = true) as
  select id, email, username, full_name, avatar_url, locale, active_organization_id, active_team_id, created_at, updated_at
  from better_supabase.profiles;

create view public.job_attachments with (security_invoker = true) as
  select id, tenant_id as organization_id, job_id, bucket, object_path, name, mime_type, size, status, uploaded_by, created_at
  from better_supabase.attachments
  where subject_type = 'job';

create function public.job_attachments_insert() returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  insert into better_supabase.attachments (tenant_id, subject_type, subject_id, bucket, object_path, name, mime_type, size)
  values (new.organization_id, 'job', new.job_id::text, coalesce(new.bucket, 'attachments'), new.object_path, new.name, new.mime_type, new.size)
  returning id into new.id;
  return new;
end;
$$;

create trigger job_attachments_insert
  instead of insert on public.job_attachments
  for each row execute function public.job_attachments_insert();
