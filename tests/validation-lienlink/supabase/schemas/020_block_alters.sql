-- What the app adds to the block tables. better-supabase never drops or copies
-- back anything in this file.
alter table better_supabase.memberships add column id uuid not null default gen_random_uuid();
alter table better_supabase.memberships add constraint memberships_id_key unique (id);

alter table better_supabase.teams add constraint teams_tenant_id_id_key unique (tenant_id, id);
alter table better_supabase.teams add constraint teams_name_length check (length(name) <= 80);

alter table better_supabase.organizations add constraint organizations_slug_format check (slug ~ '^[a-z0-9-]+$');
alter table better_supabase.profiles add constraint profiles_username_format check (username is null or username ~ '^[a-z0-9_]+$');

alter table better_supabase.attachments add column job_id uuid generated always as (
  case when subject_type = 'job' then subject_id::uuid end
) stored;

create index attachments_job_id_idx on better_supabase.attachments (job_id);

alter table public.jobs add constraint jobs_team_fkey
  foreign key (organization_id, team_id) references better_supabase.teams (tenant_id, id);
