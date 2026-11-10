-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:b070f56f5c58ec8adc66538ad4afebb82803f638ed5d7c964a7aaa919c33fb8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;
-- options.path: a row whose path no longer matches the template, and that has no stored object, gets a new one.
update "better_supabase"."attachments" as x set "object_path" = null
where x."object_path" is distinct from (select "tenant_id"::text || '/attachments/' || "id"::text from (select x.*) as r)
  and not exists (select 1 from storage.objects o where o.bucket_id = x."bucket" and o.name = x."object_path");
-- A record uploaded before the storage status existed is stored.
update "better_supabase"."attachments" set "storage_status" = 'stored' where "uploaded_at" is not null and "storage_status" = 'pending_upload';

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
