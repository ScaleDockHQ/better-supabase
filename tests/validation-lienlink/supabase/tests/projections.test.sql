-- The Lienlink shape (ADR 0391, 0471): block tables in better_supabase, app
-- views in public over them, app ALTERs, and app triggers beside the blocks'.
-- Hand-written, so `better-supabase upgrade` never touches it.
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(16);

select extensions.has_view('public', 'organizations', 'organizations is a view');
select extensions.has_view('public', 'teams', 'teams is a view');
select extensions.has_view('public', 'job_attachments', 'job_attachments is a view');

select extensions.is(
  (
    select count(*)::int
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'v'
      and c.relname in ('organizations', 'memberships', 'teams', 'team_members', 'profiles', 'job_attachments')
      and coalesce(c.reloptions, '{}') @> array['security_invoker=true']
  ),
  6,
  'every projection view runs as the caller, so the block tables'' policies apply'
);

select extensions.col_is_pk('better_supabase', 'organizations', 'id', 'the block table keeps its key');

select extensions.has_column('public', 'teams', 'organization_id', 'teams renames tenant_id to organization_id');
select extensions.hasnt_column('public', 'teams', 'tenant_id', 'the view does not expose tenant_id');

select extensions.has_trigger(
  'public', 'job_attachments', 'job_attachments_insert',
  'job_attachments takes inserts through an instead of trigger'
);

select extensions.is(
  (
    select (t.tgtype & 64) <> 0
    from pg_trigger t
    where t.tgrelid = 'public.job_attachments'::regclass
      and t.tgname = 'job_attachments_insert'
  ),
  true,
  'the insert trigger on job_attachments is an instead of trigger'
);

select extensions.is(
  (
    select a.attgenerated::text
    from pg_attribute a
    where a.attrelid = 'better_supabase.attachments'::regclass
      and a.attname = 'job_id'
  ),
  's',
  'attachments.job_id is a stored generated column'
);

select extensions.has_index(
  'better_supabase', 'attachments', 'attachments_job_id_idx',
  'the generated job_id has its index'
);

select extensions.fk_ok(
  'public', 'jobs', array['organization_id', 'team_id'],
  'better_supabase', 'teams', array['tenant_id', 'id'],
  'jobs reference teams through a composite foreign key'
);

select extensions.has_trigger('public', 'jobs', 'jobs_audit', 'jobs carry the app''s row audit trigger');

select extensions.has_trigger('auth', 'users', 'lienlink_on_user_created', 'auth.users carries the app''s trigger');

select extensions.has_trigger('auth', 'users', 'bsb_profile_sync', 'the profiles block''s own auth.users trigger sits beside the app''s');

select extensions.has_function('public', 'jobs_audit', 'the audit function is the app''s');

select * from extensions.finish();
rollback;
