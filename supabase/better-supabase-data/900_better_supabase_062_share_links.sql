-- better-supabase module: share-links
-- @bsb-block-data share-links
-- @bsb-hash sha256:9251791ace46a9836a21e4d30588d10e717391e7de637955ccee5fcd5dd5ca93
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- ai-chat sharing is this block: links of the old ai_chat_shares table.
insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "created_by", "leaf_id")
select c.organization_id, 'ai-chat', s.chat_id::text, s.token_hash, s.created_by, s.leaf_id
from "better_supabase".ai_chat_shares s
join "better_supabase".ai_chats c on c.id = s.chat_id
on conflict ("token_hash") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('share-links', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
