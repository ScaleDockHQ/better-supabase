-- better-supabase module: meetings
-- @bsb-block-data meetings
-- @bsb-hash sha256:be7b5dfa4e47458b3cabb7ecef25b126f2df4669a498418ef652de3714c532db
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.meetings', target_type => 'meeting', event_prefix => 'meeting', deferred => true);
select better_supabase.audit('better_supabase.meeting_attendees', target_type => 'meeting_attendee', event_prefix => 'meeting_attendee', deferred => true);
select better_supabase.audit('better_supabase.meeting_agenda_items', target_type => 'meeting_agenda_item', event_prefix => 'meeting_agenda_item', deferred => true);
select better_supabase.audit('better_supabase.meeting_decisions', target_type => 'meeting_decision', event_prefix => 'meeting_decision', deferred => true);
select better_supabase.audit('better_supabase.meeting_action_items', target_type => 'meeting_action_item', event_prefix => 'meeting_action_item', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('meetings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
