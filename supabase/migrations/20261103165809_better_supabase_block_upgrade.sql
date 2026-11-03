-- better-supabase upgrade: steps that run before the schema diff.

-- rate-limit: version 1 to 2. rate_limit_rules gets organization_id: a scope has one global rule and one rule per organization, set with set_organization_rate_limit. hit_rate_limit and check_rate_limit take organization_id, and check_rate_limits reads it from each hit.
alter table "better_supabase"."rate_limit_rules" add column if not exists "organization_id" uuid;
alter table "better_supabase"."rate_limit_rules" drop constraint if exists "rate_limit_rules_pkey";

-- streams: version 2 to 3. Adds stream_kv and the stream_kv_get, stream_kv_set, stream_kv_incr and stream_kv_publish functions for postgresPublisher, and the purgeSchedule option; purge_streams also clears expired keys.
-- Version 3 only adds objects; the module file below creates them.

-- inbox: version 8 to 9. Inbound events take the status processing, count an attempt only when processing starts, wait for available_at after a failure and are offered again once their lease (locked_until) ran out; set_inbound_event_status takes retry_in and lease. Deliveries record delivered_at, read_at and failed_at, and conversations keep last_inbound_at and active_stream_id (set_active_stream claims or releases it and broadcasts stream). Option realtimeColumns adds the listed conversation columns to the staff ping, and timeline events broadcast event.created.
alter table "better_supabase"."inbox_inbound_events" add column if not exists "available_at" timestamptz not null default now();
alter table "better_supabase"."inbox_inbound_events" add column if not exists "locked_until" timestamptz;
alter table "better_supabase"."inbox_message_deliveries" add column if not exists "delivered_at" timestamptz;
alter table "better_supabase"."inbox_message_deliveries" add column if not exists "read_at" timestamptz;
alter table "better_supabase"."inbox_message_deliveries" add column if not exists "failed_at" timestamptz;
alter table "better_supabase"."inbox_conversations" add column if not exists "last_inbound_at" timestamptz;
alter table "better_supabase"."inbox_conversations" add column if not exists "active_stream_id" text;
update "better_supabase"."inbox_conversations" v set "last_inbound_at" = (
  select max(m."created_at")
  from "better_supabase"."inbox_message_details" d
  join "better_supabase"."messages" m on m."id" = d."message_id"
  where d."conversation_id" = v."id" and d."direction" = 'inbound' and m."kind" = 'message'
);
drop function if exists "better_supabase"."set_inbound_event_status"(uuid, text, text);

-- ai-files: version 2 to 3. Documents take the kind spec, a json-render spec kept as JSON text in the version content.
do $bsb$
declare
  v_name text;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."ai_documents"'::regclass and c.contype = 'c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%kind%'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%''sheet''%'
  loop
    execute pg_catalog.format('alter table "better_supabase"."ai_documents" drop constraint %I', v_name);
  end loop;
  alter table "better_supabase"."ai_documents" add constraint "ai_documents_kind_check"
    check ("kind" in ('text', 'code', 'sheet', 'image', 'spec'));
end
$bsb$;

-- agents: version 1 to 2. Adds name, files, content_hash, latest_version and provider_refs to agent skills, and record_skill_sync.
alter table "better_supabase"."agent_skills"
  add column if not exists "name" text,
  add column if not exists "files" jsonb not null default '[]',
  add column if not exists "content_hash" text,
  add column if not exists "latest_version" text,
  add column if not exists "provider_refs" jsonb not null default '{}';

-- contacts: version 2 to 3. resolve_person is granted to service_role, so record_inbound resolves senders when the service role calls it.
grant execute on function "better_supabase"."resolve_person"(uuid, jsonb) to service_role;
