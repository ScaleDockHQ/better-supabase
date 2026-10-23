-- better-supabase upgrade: steps that run before the schema diff.

-- workflow-editor: version 2 to 3. Event triggers go: an automation with a workflow action starts a definition on an outbox event. Triggers of kind event are deleted and workflow_event_targets is dropped.
delete from "better_supabase"."workflow_triggers" where "kind" = 'event';
drop function if exists "better_supabase"."workflow_event_targets"(text, uuid);
