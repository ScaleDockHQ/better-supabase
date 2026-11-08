-- better-supabase add --adopt: the rows and settings of audit, memberships, invitations, queue, webhook-inbox, organizations, profiles, outbox, notifications, webhooks-out, webhooks-in, drive, comments, attachments, data-lifecycle, credentials, numbering, teams, tags, state-machine, custom-fields, share-links, reminders, imports, drive-files, housekeeping, seeds that no data migration holds yet.

set lock_timeout = '5s';

-- audit
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

-- queue
insert into better_supabase.blocks (name, version, mode)
values ('queue', 11, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhook-inbox
insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- organizations
insert into better_supabase.blocks (name, version, mode)
values ('organizations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- profiles
insert into better_supabase.blocks (name, version, mode)
values ('profiles', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- outbox
insert into better_supabase.blocks (name, version, mode)
values ('outbox', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- notifications
insert into better_supabase.blocks (name, version, mode)
values ('notifications', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhooks-out
insert into better_supabase.blocks (name, version, mode)
values ('webhooks-out', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhooks-in
insert into better_supabase.blocks (name, version, mode)
values ('webhooks-in', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- drive
insert into better_supabase.blocks (name, version, mode)
values ('drive', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- comments
insert into better_supabase.blocks (name, version, mode)
values ('comments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- attachments
update "better_supabase"."attachments" as x set "object_path" = null
where x."object_path" is distinct from (select "tenant_id"::text || '/attachments/' || "id"::text from (select x.*) as r);

update "better_supabase"."attachments" set "storage_status" = 'stored' where "uploaded_at" is not null and "storage_status" = 'pending_upload';

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- data-lifecycle
insert into better_supabase.blocks (name, version, mode)
values ('data-lifecycle', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- credentials
insert into better_supabase.blocks (name, version, mode)
values ('credentials', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- numbering
insert into better_supabase.blocks (name, version, mode)
values ('numbering', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- teams
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

-- drive-files
insert into better_supabase.blocks (name, version, mode)
values ('drive-files', 2, 'managed')
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
