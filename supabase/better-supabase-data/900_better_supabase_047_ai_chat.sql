-- better-supabase module: ai-chat
-- @bsb-block-data ai-chat
-- @bsb-hash sha256:65b54053003f0bb6c6ae306cfe5ce799174a7213709e12ca2eec97a945dedf07
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.ai_chats', target_type => 'ai_chat', event_prefix => 'ai_chat', deferred => true);
select better_supabase.audit('better_supabase.ai_projects', target_type => 'ai_project', event_prefix => 'ai_project', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('ai-chat', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
