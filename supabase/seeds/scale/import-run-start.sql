-- Opens the import run the tier seed writes under. Inside a run, import mode
-- (better_supabase.importing()) skips the row triggers that made the 1,000,000
-- row seed unfinishable (ADR 0427): the audit log keeps one summary per entity,
-- the outbox applies the imports.events policy and search refreshes once.
-- The run id is fixed, so a second seed reuses the row.
insert into better_supabase.import_runs (id, tenant_id, source, status, started_at, lease_expires_at)
values ('00000000-0000-4000-8000-5ca1e5eed000', '00000000-0000-4000-8000-000000000001', 'scale-seed', 'running', now(), now() + interval '12 hours')
on conflict (id) do update set status = 'running', started_at = now(), finished_at = null, lease_expires_at = now() + interval '12 hours';
