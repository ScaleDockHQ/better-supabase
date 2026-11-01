-- better-supabase module: inbox
-- @bsb-block-data inbox
-- @bsb-hash sha256:4d349c0c75ea101102a2ea37caa240bbf52f32ba02a2246f35879565e54ccc94
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('inbox.conversation_to_task', 'inbox', 'inbox_conversation', 'inbox_conversation.opened', 'Open a task for each new conversation', 'Creates a task from the conversation''s subject and preview, assigned to the conversation''s assignee and linked created_from the conversation.', '[{"kind":"tasks.from_conversation","config":{"targetType":"work_item"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.inboxes', target_type => 'inbox', event_prefix => 'inbox', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('inbox', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
