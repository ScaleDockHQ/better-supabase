-- better-supabase module: reviews
-- @bsb-block-data reviews
-- @bsb-hash sha256:eca482e72d47f7bec9778aee91022da731eeb8923934dd7c289ea657debbff27
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Puts the reviews written before the moderation module under it.
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
