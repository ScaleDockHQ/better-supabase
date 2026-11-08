-- The app's own tables. The blocks own the better_supabase tables, and the
-- views in 030_projections.sql project them into public.
create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references better_supabase.organizations (id) on delete cascade,
  team_id uuid,
  title text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id)
);

create index jobs_organization_id_idx on public.jobs (organization_id);
create index jobs_team_id_idx on public.jobs (organization_id, team_id);

-- A child of jobs: the people on a job. PowerSync streams it with its parent
-- (gen.powersync.children in the config).
create table public.job_parties (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null,
  organization_id uuid not null references better_supabase.organizations (id) on delete cascade,
  name text not null,
  role text not null default 'owner',
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (job_id, organization_id) references public.jobs (id, organization_id) on delete cascade
);

create index job_parties_job_id_idx on public.job_parties (job_id);
create index job_parties_organization_id_idx on public.job_parties (organization_id);

create table public.job_audit (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null,
  organization_id uuid not null,
  action text not null,
  changed jsonb not null default '{}',
  actor uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create index job_audit_job_id_idx on public.job_audit (job_id);
create index job_audit_organization_id_idx on public.job_audit (organization_id);

create table public.user_signups (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

comment on table public.jobs is '@bsb subject type=job';

alter table public.jobs enable row level security;
alter table public.job_parties enable row level security;
alter table public.job_audit enable row level security;
alter table public.user_signups enable row level security;

create policy jobs_member_select on public.jobs
  for select to authenticated
  using (organization_id in (select better_supabase.member_organization_ids()));

create policy jobs_member_insert on public.jobs
  for insert to authenticated
  with check (organization_id in (select better_supabase.member_organization_ids()));

create policy jobs_member_update on public.jobs
  for update to authenticated
  using (organization_id in (select better_supabase.member_organization_ids()))
  with check (organization_id in (select better_supabase.member_organization_ids()));

create policy job_parties_member_select on public.job_parties
  for select to authenticated
  using (organization_id in (select better_supabase.member_organization_ids()));

create policy job_parties_member_insert on public.job_parties
  for insert to authenticated
  with check (organization_id in (select better_supabase.member_organization_ids()));

create policy job_parties_member_update on public.job_parties
  for update to authenticated
  using (organization_id in (select better_supabase.member_organization_ids()))
  with check (organization_id in (select better_supabase.member_organization_ids()));

create policy job_parties_member_delete on public.job_parties
  for delete to authenticated
  using (organization_id in (select better_supabase.member_organization_ids()));

create policy job_audit_member_select on public.job_audit
  for select to authenticated
  using (organization_id in (select better_supabase.member_organization_ids()));

create policy jobs_no_delete on public.jobs
  as restrictive for delete to authenticated
  using (false);

create policy job_audit_no_insert on public.job_audit
  as restrictive for insert to authenticated
  with check (false);

create policy job_audit_no_update on public.job_audit
  as restrictive for update to authenticated
  using (false);

create policy job_audit_no_delete on public.job_audit
  as restrictive for delete to authenticated
  using (false);

create policy user_signups_own_select on public.user_signups
  for select to authenticated
  using (user_id = (select auth.uid()));
