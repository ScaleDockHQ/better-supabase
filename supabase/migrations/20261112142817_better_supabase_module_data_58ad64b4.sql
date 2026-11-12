-- better-supabase add --adopt: the rows and settings of updated-at, audit, memberships, invitations, reserved-slugs, queue, idempotency, webhook-inbox, realtime-tables, jsonb-schemas, grants, read-sets, entitlements, rate-limit, vector-search, permissions, organizations, profiles, outbox, notifications, webhooks-out, sessions, webhooks-in, api-keys, settings, usage, flags, drive, guests, comments, attachments, data-lifecycle, sso, enrollments, onboarding, waitlist, announcements, streams, credentials, workflows, workflow-sdk, workflow-editor, chat-sdk-state, inbox, ai-chat, ai-files, knowledge, memory, agents, connectors, ai-schedules, push, ai-cache, ai-keys, numbering, teams, tags, state-machine, custom-fields, share-links, reminders, imports, subjects, rank, saved-views, relations, bulk-actions, catalog, search, metrics, calendar, bookings, versions, trash, reactions, approvals, access-requests, documents, ledger, inventory, drive-files, orders, promotions, forms, signatures, time-entries, service-accounts, templates, cases, deals, hiring, tasks, tasks, pipelines, contacts, activities, quotes, invoices, sla, goals, employees, collections, signing-keys, security-events, domains, moderation, reviews, leave, automations, assets, scores, passes, billable-time, leases, expenses, donations, dispatch, shipments, contracts, compliance, incidents, courses, messaging, channels, timeline, mail-sync, segments, assignment, enrichment, forecasts, field-history, sequences, lead-scoring, posts, field-encryption, content, qualifications, risks, shifts, tax, accounting, acknowledgements, consents, observations, medications, care-plans, inspections, manufacturing, banking, meetings, legal-entities, funding, payroll-export, maintenance, warranty, dam, document-templates, lims, appraisals, warehouse, rfqs, tills, clinical-decision-support, periods, deadlines, commissions, referrals, recurrence, housekeeping, seeds, e-prescribing, agent-checkout, prompts, ai-evals, ai-guardrails, option-sets that no data migration holds yet.

set lock_timeout = '5s';

-- updated-at
insert into better_supabase.blocks (name, version, mode)
values ('updated-at', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- audit
drop event trigger if exists bsb_audit_forget_dropped;

create event trigger bsb_audit_forget_dropped on sql_drop
  when tag in ('DROP TABLE', 'DROP SCHEMA')
  execute function better_supabase.audit_forget_dropped();

delete from "better_supabase"."audited_tables" a
where not exists (select 1 from pg_catalog.pg_class c where c.oid = a."target"::oid);

insert into better_supabase.blocks (name, version, mode)
values ('audit', 13, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- memberships
insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- invitations
insert into better_supabase.blocks (name, version, mode)
values ('invitations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- reserved-slugs
insert into "better_supabase"."reserved_slugs" ("slug", "reason")
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict ("slug") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reserved-slugs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- queue
create extension if not exists "pgmq";

select better_supabase.index_job_queue(q.queue_name) from pgmq.list_queues() q;

insert into better_supabase.blocks (name, version, mode)
values ('queue', 12, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- idempotency
insert into better_supabase.blocks (name, version, mode)
values ('idempotency', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhook-inbox
insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- realtime-tables
insert into better_supabase.blocks (name, version, mode)
values ('realtime-tables', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- jsonb-schemas
create extension if not exists "pg_jsonschema" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('jsonb-schemas', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- grants
insert into better_supabase.blocks (name, version, mode)
values ('grants', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- read-sets
insert into better_supabase.blocks (name, version, mode)
values ('read-sets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- entitlements
insert into better_supabase.blocks (name, version, mode)
values ('entitlements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- rate-limit
do $$
declare
  current_hook text;
begin
  select split_part(setting, '=', 2) into current_hook
  from pg_catalog.pg_db_role_setting s
  join pg_catalog.pg_roles r on r.oid = s.setrole
  cross join lateral unnest(s.setconfig) setting
  where r.rolname = 'authenticator' and s.setdatabase = 0 and setting like 'pgrst.db_pre_request=%';
  if current_hook is null then
    alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';
  elsif current_hook <> 'better_supabase.check_request' then
    raise notice 'pgrst.db_pre_request is %; call better_supabase.check_request() from it', current_hook;
  end if;
end
$$;

notify pgrst, 'reload config';

insert into better_supabase.blocks (name, version, mode)
values ('rate-limit', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- vector-search
create extension if not exists "vector" with schema "extensions";

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_index i
    join pg_catalog.pg_class c on c.oid = i.indexrelid
    join pg_catalog.pg_am am on am.oid = c.relam
    join pg_catalog.pg_opclass oc on oc.oid = i.indclass[0]
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
    where i.indrelid = '"public"."notes"'::regclass
      and a.attname = 'embedding'
      and am.amname in ('hnsw', 'ivfflat')
      and oc.opcname = 'vector_cosine_ops'
  ) then
    raise notice '%', 'notes.embedding has no hnsw or ivfflat index with vector_cosine_ops, so search_notes scans the table';
  end if;
end;
$$;

insert into better_supabase.blocks (name, version, mode)
values ('vector-search', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- permissions
insert into "better_supabase"."roles" ("key", "scope")
select v.k, v.s
from (values ('owner', 'tenant'), ('admin', 'tenant'), ('member', 'tenant')) as v (k, s)
where not exists (select 1 from "better_supabase"."roles" x where x."key" = v.k);

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- organizations
insert into better_supabase.blocks (name, version, mode)
values ('organizations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- profiles
select better_supabase.replace_equivalent_triggers('auth.users', 'bsb_profile_sync', '(handle_new_user|create_profile|new_user_profile)', false);

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- outbox
insert into better_supabase.blocks (name, version, mode)
values ('outbox', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- notifications
insert into better_supabase.blocks (name, version, mode)
values ('notifications', 11, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhooks-out
insert into better_supabase.blocks (name, version, mode)
values ('webhooks-out', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- sessions
insert into better_supabase.blocks (name, version, mode)
values ('sessions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhooks-in
insert into better_supabase.blocks (name, version, mode)
values ('webhooks-in', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- api-keys
insert into better_supabase.blocks (name, version, mode)
values ('api-keys', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- settings
insert into better_supabase.blocks (name, version, mode)
values ('settings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- usage
insert into better_supabase.blocks (name, version, mode)
values ('usage', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- flags
create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('flags', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- drive
insert into better_supabase.blocks (name, version, mode)
values ('drive', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- guests
insert into better_supabase.blocks (name, version, mode)
values ('guests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- comments
insert into better_supabase.blocks (name, version, mode)
values ('comments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- attachments
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

update "better_supabase"."attachments" as x set "object_path" = null
where x."object_path" is distinct from (select "tenant_id"::text || '/attachments/' || "id"::text from (select x.*) as r)
  and not exists (select 1 from storage.objects o where o.bucket_id = x."bucket" and o.name = x."object_path");

update "better_supabase"."attachments" set "storage_status" = 'stored' where "uploaded_at" is not null and "storage_status" = 'pending_upload';

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- data-lifecycle
insert into storage.buckets (id, name, public)
values ('data-exports', 'data-exports', false)
on conflict (id) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('data-lifecycle', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- sso
insert into better_supabase.blocks (name, version, mode)
values ('sso', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- enrollments
insert into better_supabase.blocks (name, version, mode)
values ('enrollments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- onboarding
insert into better_supabase.blocks (name, version, mode)
values ('onboarding', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- waitlist
insert into better_supabase.blocks (name, version, mode)
values ('waitlist', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- announcements
insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- streams
insert into better_supabase.blocks (name, version, mode)
values ('streams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- credentials
insert into better_supabase.blocks (name, version, mode)
values ('credentials', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- workflows
insert into better_supabase.blocks (name, version, mode)
values ('workflows', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- workflow-sdk
do $$
declare
  c record;
begin
  for c in select table_name, column_name from information_schema.columns
    where table_schema = 'workflow' and data_type = 'timestamp without time zone'
  loop
    execute format('alter table workflow.%I alter column %I type timestamptz using %I at time zone ''UTC''', c.table_name, c.column_name, c.column_name);
  end loop;
end
$$;

insert into better_supabase.blocks (name, version, mode)
values ('workflow-sdk', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- workflow-editor
insert into better_supabase.blocks (name, version, mode)
values ('workflow-editor', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- chat-sdk-state
insert into better_supabase.blocks (name, version, mode)
values ('chat-sdk-state', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- inbox
insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('inbox.conversation_to_task', 'inbox', 'inbox_conversation', 'inbox_conversation.opened', 'Open a task for each new conversation', 'Creates a task from the conversation''s subject and preview, assigned to the conversation''s assignee and linked created_from the conversation.', '[{"kind":"tasks.from_conversation","config":{"targetType":"work_item"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

insert into better_supabase.blocks (name, version, mode)
values ('inbox', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-chat
insert into better_supabase.blocks (name, version, mode)
values ('ai-chat', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-files
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ai-files', 'ai-files', false, 52428800, null)
on conflict (id) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('ai-files', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- knowledge
insert into better_supabase.blocks (name, version, mode)
values ('knowledge', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- memory
insert into better_supabase.blocks (name, version, mode)
values ('memory', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- agents
insert into better_supabase.blocks (name, version, mode)
values ('agents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- connectors
insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-schedules
insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- push
insert into better_supabase.blocks (name, version, mode)
values ('push', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-cache
insert into better_supabase.blocks (name, version, mode)
values ('ai-cache', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-keys
insert into better_supabase.blocks (name, version, mode)
values ('ai-keys', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- numbering
insert into better_supabase.blocks (name, version, mode)
values ('numbering', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- teams
update "better_supabase"."team_members" y set "employee_id" = x."id"
from "better_supabase"."employees" x
where y."employee_id" is null and x."tenant_id" = y."tenant_id" and x."user_id" = y."user_id"
  and not exists (
    select 1 from "better_supabase"."team_members" z
    where z."team_id" = y."team_id" and z."employee_id" = x."id"
  );

insert into "better_supabase"."team_members" ("team_id", "user_id", "employee_id", "tenant_id")
select t."id",
  case when exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = x."tenant_id"
      and m."user_id" = x."user_id"
  ) then x."user_id" end,
  x."id", x."tenant_id"
from "better_supabase"."employees" x
join "better_supabase"."teams" t on t."id" = x."team_id" and t."tenant_id" = x."tenant_id"
on conflict do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- tags
insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- state-machine
insert into better_supabase.blocks (name, version, mode)
values ('state-machine', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- custom-fields
insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- share-links
insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "created_by", "leaf_id")
select c.tenant_id, 'ai-chat', s.chat_id::text, s.token_hash, s.created_by, s.leaf_id
from "better_supabase".ai_chat_shares s
join "better_supabase".ai_chats c on c.id = s.chat_id
on conflict ("token_hash") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('share-links', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- reminders
insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- imports
insert into better_supabase.blocks (name, version, mode)
values ('imports', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- subjects
insert into better_supabase.blocks (name, version, mode)
values ('subjects', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- rank
insert into better_supabase.blocks (name, version, mode)
values ('rank', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- saved-views
insert into better_supabase.blocks (name, version, mode)
values ('saved-views', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- relations
insert into better_supabase.blocks (name, version, mode)
values ('relations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- bulk-actions
delete from better_supabase.blocks
  where name = 'bulk'
    and exists (select 1 from better_supabase.blocks where name = 'bulk-actions');

update better_supabase.blocks set name = 'bulk-actions'
  where name = 'bulk'
    and not exists (select 1 from better_supabase.blocks where name = 'bulk-actions');

insert into better_supabase.blocks (name, version, mode)
values ('bulk-actions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- catalog
insert into better_supabase.blocks (name, version, mode)
values ('catalog', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- search
create extension if not exists "pg_trgm" with schema "extensions";

create extension if not exists "unaccent" with schema "extensions";

select "better_supabase"."search_reindex"();

insert into better_supabase.blocks (name, version, mode)
values ('search', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- metrics
insert into better_supabase.blocks (name, version, mode)
values ('metrics', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- calendar
insert into better_supabase.blocks (name, version, mode)
values ('calendar', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- bookings
create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('bookings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- versions
insert into better_supabase.blocks (name, version, mode)
values ('versions', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- trash
insert into better_supabase.blocks (name, version, mode)
values ('trash', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- reactions
insert into better_supabase.blocks (name, version, mode)
values ('reactions', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- approvals
insert into better_supabase.blocks (name, version, mode)
values ('approvals', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- access-requests
insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- documents
insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ledger
insert into better_supabase.blocks (name, version, mode)
values ('ledger', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- inventory
insert into better_supabase.blocks (name, version, mode)
values ('inventory', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- drive-files
insert into better_supabase.blocks (name, version, mode)
values ('drive-files', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- orders
insert into better_supabase.blocks (name, version, mode)
values ('orders', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- promotions
insert into better_supabase.blocks (name, version, mode)
values ('promotions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- forms
insert into better_supabase.blocks (name, version, mode)
values ('forms', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- signatures
insert into better_supabase.blocks (name, version, mode)
values ('signatures', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- time-entries
delete from better_supabase.blocks
  where name = 'time-tracking'
    and exists (select 1 from better_supabase.blocks where name = 'time-entries');

update better_supabase.blocks set name = 'time-entries'
  where name = 'time-tracking'
    and not exists (select 1 from better_supabase.blocks where name = 'time-entries');

insert into better_supabase.blocks (name, version, mode)
values ('time-entries', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- service-accounts
insert into better_supabase.blocks (name, version, mode)
values ('service-accounts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- templates
insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- cases
insert into better_supabase.blocks (name, version, mode)
values ('cases', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- deals
insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- hiring
insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('hiring.application_to_employee', 'hiring', 'application', 'application.hired', 'Preboard each hired candidate', 'Creates an employee in preboarding from the hired application''s candidate and job, linked created_from the application.', '[{"kind":"employees.from_application","config":{"targetType":"employee"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- tasks
select "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
from "better_supabase"."work_projects" x
where exists (select 1 from "better_supabase"."accounting_settings" s where s."tenant_id" = x."tenant_id");

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- tasks
insert into better_supabase.blocks (name, block, version, mode)
values ('facilities', 'tasks', 5, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();

-- pipelines
insert into better_supabase.blocks (name, version, mode)
values ('pipelines', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- contacts
insert into better_supabase.blocks (name, version, mode)
values ('contacts', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- activities
insert into better_supabase.blocks (name, version, mode)
values ('activities', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- quotes
insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('quotes.quote_to_order', 'quotes', 'quote', 'quote.accepted', 'Order each accepted quote', 'Creates an order for the accepted quote, linked created_from the quote, so an accepted quote orders once.', '[{"kind":"orders.from_quote","config":{"targetType":"order"}}]'::jsonb, false)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- invoices
insert into better_supabase.blocks (name, version, mode)
values ('invoices', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- sla
insert into better_supabase.blocks (name, version, mode)
values ('sla', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- goals
insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- employees
insert into better_supabase.blocks (name, version, mode)
values ('employees', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- collections
insert into better_supabase.blocks (name, version, mode)
values ('collections', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- signing-keys
insert into better_supabase.blocks (name, version, mode)
values ('signing-keys', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- security-events
insert into better_supabase.blocks (name, version, mode)
values ('security-events', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- domains
insert into better_supabase.blocks (name, version, mode)
values ('domains', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- moderation
insert into better_supabase.blocks (name, version, mode)
values ('moderation', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- reviews
insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id", "author_id", "status", "reason", "decided_by", "decided_at", "created_at", "updated_at")
  select x."tenant_id", 'review', x."id"::text, x."author_id",
    case x."status"::text when 'published' then 'visible' when 'rejected' then 'hidden' else 'pending' end,
    case when x."status" = 'rejected' then x."rejection_reason" end, null, null, x."created_at", x."updated_at"
  from "better_supabase"."reviews" x
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('reviews', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- leave
insert into better_supabase.blocks (name, version, mode)
values ('leave', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- automations
insert into better_supabase.blocks (name, version, mode)
values ('automations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- assets
create extension if not exists "postgis" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- scores
insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- passes
insert into better_supabase.blocks (name, version, mode)
values ('passes', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- billable-time
insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- leases
insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- expenses
insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- donations
insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- dispatch
insert into better_supabase.blocks (name, version, mode)
values ('dispatch', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- shipments
insert into better_supabase.blocks (name, version, mode)
values ('shipments', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- contracts
insert into better_supabase.blocks (name, version, mode)
values ('contracts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- compliance
do $$
begin
  if to_regclass('"better_supabase"."acknowledgement_assignments"') is null then
    return;
  end if;
  update "better_supabase"."acknowledgement_assignments" x
  set "principal_id" = '*'
  where x."subject_type" = 'compliance_policy'
    and x."principal_type" = 'role'
    and x."principal_id" = 'member'
    and not exists (
      select 1 from "better_supabase"."acknowledgement_assignments" y
      where y."tenant_id" = x."tenant_id"
        and y."subject_type" = x."subject_type"
        and y."subject_id" = x."subject_id"
        and y."principal_type" = 'role'
        and y."principal_id" = '*'
    );
end;
$$;

insert into better_supabase.blocks (name, version, mode)
values ('compliance', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- incidents
insert into better_supabase.blocks (name, version, mode)
values ('incidents', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- courses
insert into better_supabase.blocks (name, version, mode)
values ('courses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- messaging
insert into better_supabase.blocks (name, version, mode)
values ('messaging', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- channels
insert into better_supabase.blocks (name, version, mode)
values ('channels', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- timeline
insert into better_supabase.blocks (name, version, mode)
values ('timeline', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- mail-sync
insert into better_supabase.blocks (name, version, mode)
values ('mail-sync', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- segments
insert into better_supabase.blocks (name, version, mode)
values ('segments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- assignment
insert into better_supabase.blocks (name, version, mode)
values ('assignment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- enrichment
insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- forecasts
insert into better_supabase.blocks (name, version, mode)
values ('forecasts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- field-history
insert into better_supabase.blocks (name, version, mode)
values ('field-history', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- sequences
insert into better_supabase.blocks (name, version, mode)
values ('sequences', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- lead-scoring
insert into better_supabase.blocks (name, version, mode)
values ('lead-scoring', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- posts
insert into better_supabase.blocks (name, version, mode)
values ('posts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- field-encryption
insert into better_supabase.blocks (name, version, mode)
values ('field-encryption', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- content
insert into better_supabase.blocks (name, version, mode)
values ('content', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- qualifications
insert into better_supabase.blocks (name, version, mode)
values ('qualifications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- risks
insert into better_supabase.blocks (name, version, mode)
values ('risks', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- shifts
insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- tax
insert into better_supabase.blocks (name, version, mode)
values ('tax', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- accounting
insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable")
select s."tenant_id", c.code, c.name, c.type, c.subtype, false
from "better_supabase"."accounting_settings" s
cross join (values ('disposal_gain', '4910', 'Gains on asset disposals', 'income', 'other_income'), ('disposal_loss', '6910', 'Losses on asset disposals', 'expense', 'other_expense')) c (role, code, name, type, subtype)
where exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = s."tenant_id")
  and not exists (select 1 from "better_supabase"."accounting_account_roles" z where z."tenant_id" = s."tenant_id" and z."role" = c.role)
  and not exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = s."tenant_id" and y."code" = c.code);

insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
select s."tenant_id", c.role, y."id"
from "better_supabase"."accounting_settings" s
cross join (values ('disposal_gain', '4910', 'Gains on asset disposals'), ('disposal_loss', '6910', 'Losses on asset disposals')) c (role, code, name)
join "better_supabase"."accounting_accounts" y on y."tenant_id" = s."tenant_id" and y."code" = c.code and y."name" = c.name
where not exists (select 1 from "better_supabase"."accounting_account_roles" z where z."tenant_id" = s."tenant_id" and z."role" = c.role)
on conflict ("tenant_id", "role") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('accounting', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- acknowledgements
insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- consents
insert into "better_supabase"."consent_purposes" ("tenant_id", "key", "title", "legal_basis", "description")
values (null, 'notification_email', 'Notification email', 'consent', 'Notifications sent by email under a named consent purpose.')
on conflict do nothing;

insert into "better_supabase"."consent_purposes" ("tenant_id", "key", "title", "legal_basis", "description")
values (null, 'outreach_email', 'Outreach email', 'consent', 'Email steps of outreach sequences.')
on conflict do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('consents', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- observations
insert into "better_supabase"."observation_definitions" ("tenant_id", "key", "title", "value_type", "unit", "code_system", "code", "components", "decimals", "valid_low", "valid_high", "reference_low", "reference_high", "critical_low", "critical_high")
values
  (null, 'heart_rate', 'Heart rate', 'integer', '/min', 'http://loinc.org', '8867-4', null, null, 0, 350, 51, 90, 40, 131),
  (null, 'blood_pressure', 'Blood pressure', 'components', null, 'http://loinc.org', '85354-9', '[{"key":"systolic","title":"Systolic","unit":"mm[Hg]","code":"8480-6","validLow":0,"validHigh":350,"referenceLow":100,"referenceHigh":140,"criticalLow":90,"criticalHigh":220}, {"key":"diastolic","title":"Diastolic","unit":"mm[Hg]","code":"8462-4","validLow":0,"validHigh":250,"referenceLow":60,"referenceHigh":90,"criticalLow":40,"criticalHigh":130}]'::jsonb, null, null, null, null, null, null, null),
  (null, 'body_temperature', 'Body temperature', 'number', 'Cel', 'http://loinc.org', '8310-5', null, 1, 20, 46, 36.1, 38, 35, 39.1),
  (null, 'respiratory_rate', 'Respiratory rate', 'integer', '/min', 'http://loinc.org', '9279-1', null, null, 0, 100, 12, 20, 8, 25),
  (null, 'oxygen_saturation', 'Oxygen saturation', 'integer', '%', 'http://loinc.org', '2708-6', null, null, 0, 100, 96, null, 91, null),
  (null, 'body_weight', 'Body weight', 'number', 'kg', 'http://loinc.org', '29463-7', null, 1, 0, 700, null, null, null, null),
  (null, 'body_height', 'Body height', 'number', 'cm', 'http://loinc.org', '8302-2', null, 1, 0, 300, null, null, null, null),
  (null, 'pain_score', 'Pain score', 'integer', '{score}', 'http://loinc.org', '72514-3', null, null, 0, 10, null, 3, null, null),
  (null, 'blood_glucose', 'Blood glucose', 'number', 'mmol/L', 'http://loinc.org', '15074-8', null, 1, 0, 60, 4, 7.8, 3, 20)
on conflict ("tenant_id", "key") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('observations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- medications
insert into better_supabase.blocks (name, version, mode)
values ('medications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- care-plans
insert into better_supabase.blocks (name, version, mode)
values ('care-plans', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- inspections
insert into better_supabase.blocks (name, version, mode)
values ('inspections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- manufacturing
insert into better_supabase.blocks (name, version, mode)
values ('manufacturing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- banking
insert into better_supabase.blocks (name, version, mode)
values ('banking', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- meetings
insert into better_supabase.blocks (name, version, mode)
values ('meetings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- legal-entities
do $$
begin
  if exists (
    select 1 from "better_supabase"."invoices" x
    join "better_supabase"."legal_entities" d on d."tenant_id" = x."tenant_id" and d."is_default" and x.legal_entity_id = d."id"
    join "better_supabase"."invoices" y on y."tenant_id" = x."tenant_id" and y.legal_entity_id is null and (x."number" = y."number" or x."identifier" = y."identifier") and x."direction" is not distinct from y."direction" and x."kind" is not distinct from y."kind"
  ) then
    raise warning 'invoices holds numbers twice for the default legal entity and for documents without one; list them with legal_entities_disable_check and renumber one of each pair'
      using hint = 'LEGAL_ENTITY_NUMBER_DUPLICATE';
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from "better_supabase"."quotes" x
    join "better_supabase"."legal_entities" d on d."tenant_id" = x."tenant_id" and d."is_default" and x.legal_entity_id = d."id"
    join "better_supabase"."quotes" y on y."tenant_id" = x."tenant_id" and y.legal_entity_id is null and (x."number" = y."number") and x."revision" is not distinct from y."revision"
  ) then
    raise warning 'quotes holds numbers twice for the default legal entity and for documents without one; list them with legal_entities_disable_check and renumber one of each pair'
      using hint = 'LEGAL_ENTITY_NUMBER_DUPLICATE';
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from "better_supabase"."orders" x
    join "better_supabase"."legal_entities" d on d."tenant_id" = x."tenant_id" and d."is_default" and x.legal_entity_id = d."id"
    join "better_supabase"."orders" y on y."tenant_id" = x."tenant_id" and y.legal_entity_id is null and (x."number" = y."number" or x."invoice_number" = y."invoice_number")
  ) then
    raise warning 'orders holds numbers twice for the default legal entity and for documents without one; list them with legal_entities_disable_check and renumber one of each pair'
      using hint = 'LEGAL_ENTITY_NUMBER_DUPLICATE';
  end if;
end $$;

do $$
declare
  v_constraint name;
begin
  if to_regclass('"better_supabase"."field_values"') is null then
    return;
  end if;
  for v_constraint in
    select c.conname from pg_constraint c
    where c.conrelid = '"better_supabase"."field_values"'::regclass and c.contype = 'u'
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = c.conrelid and a.attnum = any (c.conkey))
        @> array['tenant_id', 'subject_type', 'subject_id', 'definition_id']
      and cardinality(c.conkey) = 4
  loop
    execute format('alter table "better_supabase"."field_values" drop constraint %I', v_constraint);
  end loop;
end $$;

insert into better_supabase.blocks (name, version, mode)
values ('legal-entities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- funding
insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- payroll-export
insert into better_supabase.blocks (name, version, mode)
values ('payroll-export', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- maintenance
insert into better_supabase.blocks (name, version, mode)
values ('maintenance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- warranty
insert into better_supabase.blocks (name, version, mode)
values ('warranty', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- dam
insert into better_supabase.blocks (name, version, mode)
values ('dam', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- document-templates
insert into better_supabase.blocks (name, version, mode)
values ('document-templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- lims
insert into better_supabase.blocks (name, version, mode)
values ('lims', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- appraisals
insert into better_supabase.blocks (name, version, mode)
values ('appraisals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- warehouse
insert into better_supabase.blocks (name, version, mode)
values ('warehouse', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- rfqs
insert into better_supabase.blocks (name, version, mode)
values ('rfqs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- tills
insert into better_supabase.blocks (name, version, mode)
values ('tills', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- clinical-decision-support
insert into better_supabase.blocks (name, version, mode)
values ('clinical-decision-support', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- periods
insert into better_supabase.blocks (name, version, mode)
values ('periods', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- deadlines
insert into better_supabase.blocks (name, version, mode)
values ('deadlines', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- commissions
insert into better_supabase.blocks (name, version, mode)
values ('commissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- referrals
insert into better_supabase.blocks (name, version, mode)
values ('referrals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- recurrence
insert into better_supabase.blocks (name, version, mode)
values ('recurrence', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- housekeeping
insert into better_supabase.blocks (name, version, mode)
values ('housekeeping', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- seeds
insert into better_supabase.blocks (name, version, mode)
values ('seeds', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- e-prescribing
insert into better_supabase.blocks (name, version, mode)
values ('e-prescribing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- agent-checkout
insert into better_supabase.blocks (name, version, mode)
values ('agent-checkout', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- prompts
insert into better_supabase.blocks (name, version, mode)
values ('prompts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-evals
insert into better_supabase.blocks (name, version, mode)
values ('ai-evals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-guardrails
insert into better_supabase.blocks (name, version, mode)
values ('ai-guardrails', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- option-sets
insert into better_supabase.blocks (name, version, mode)
values ('option-sets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
