-- better-supabase add --adopt: the rows and settings of attachments that no data migration holds yet.

set lock_timeout = '5s';

-- attachments
update "better_supabase"."attachments" as x set "object_path" = null
where x."object_path" is distinct from (select "tenant_id"::text || '/attachments/' || "id"::text from (select x.*) as r)
  and not exists (select 1 from storage.objects o where o.bucket_id = x."bucket" and o.name = x."object_path");
