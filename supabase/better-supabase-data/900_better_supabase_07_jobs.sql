-- better-supabase module: jobs (0.5.1)
-- @bs-module-data jobs
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgmq";

-- Indexes the queues that existed before the module.
select better_supabase.index_job_queue(q.queue_name) from pgmq.list_queues() q;

insert into better_supabase.modules (name, version, mode)
values ('jobs', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
