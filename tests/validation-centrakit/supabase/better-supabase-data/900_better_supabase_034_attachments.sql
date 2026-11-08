-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:d479ca3c49bb53afc1d0fde215b4b72a12ce07df42bb1814331d8e8e56f82c27
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;
-- options.path: a row whose path no longer matches the template gets a new one.
update "better_supabase"."attachments" as x set "object_path" = null
where x."object_path" is distinct from (select "tenant_id"::text || '/attachments/' || "id"::text from (select x.*) as r);
-- A record uploaded before the storage status existed is stored.
update "better_supabase"."attachments" set "storage_status" = 'stored' where "uploaded_at" is not null and "storage_status" = 'pending_upload';

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
