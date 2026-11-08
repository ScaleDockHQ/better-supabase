-- better-supabase module: share-links
-- @bsb-block-data share-links
-- @bsb-hash sha256:6ed67e724fec9e3222ee8f093207411f31e082def1b0eceea1dbd9e018277ee0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- ai-chat sharing is this block: links of the old ai_chat_shares table.
insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "created_by", "leaf_id")
select c.tenant_id, 'ai-chat', s.chat_id::text, s.token_hash, s.created_by, s.leaf_id
from "better_supabase".ai_chat_shares s
join "better_supabase".ai_chats c on c.id = s.chat_id
on conflict ("token_hash") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('share-links', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
