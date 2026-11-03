-- better-supabase upgrade: steps that run before the schema diff.

-- streams: version 1 to 2. Chunks are bytea: stream_append takes bytea[] and stream_read returns base64 text, so binary frames survive.
do $bsb$
begin
  if (select a.atttypid from pg_attribute a where a.attrelid = '"better_supabase"."stream_chunks"'::regclass and a.attname = 'data') = 'text'::regtype then
    alter table "better_supabase"."stream_chunks" alter column "data" type bytea using convert_to("data", 'UTF8');
  end if;
end
$bsb$;
drop function if exists "better_supabase"."stream_append"(text, integer, text[]);

-- chat-sdk-state: version 1 to 2. Every ttl_ms is a bigint, so a 30-day TTL fits; append and enqueue serialize on an advisory lock before they trim; an append without a TTL keeps the list's expiry; chat_state_delete also clears a list; dequeue returns expired entries for the SDK to report.
drop function if exists better_supabase.chat_state_acquire_lock(text, text, text, integer);
drop function if exists better_supabase.chat_state_extend_lock(text, text, text, integer);
drop function if exists better_supabase.chat_state_set(text, text, jsonb, integer);
drop function if exists better_supabase.chat_state_set_if_not_exists(text, text, jsonb, integer);
drop function if exists better_supabase.chat_state_append_to_list(text, text, jsonb, integer, integer);

-- ai-chat: version 5 to 6. Chats are private (owner only), organization or shared (owner, participants, teams and the live link). A private chat that has participants becomes shared. Participants have a surrogate id and a kind (user, team, customer or external), the live link is rotatable (ai_chat_links) and chats take an optional mode column. options.teamMembership names the function that tells whether a user belongs to a team.
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = '"better_supabase"."ai_chats"'::regclass and c.contype = 'c'
      and cardinality(c.conkey) = 1 and a.attname = 'visibility'
  loop
    execute format('alter table %s drop constraint %I', '"better_supabase"."ai_chats"', v_name);
  end loop;
end;
$$;
alter table "better_supabase"."ai_chats" add constraint "ai_chats_visibility_check" check ("visibility" in ('private', 'organization', 'shared'));
alter table "better_supabase"."ai_chats" add column if not exists "mode" text check (length("mode") <= 100);
alter table "better_supabase"."ai_chat_participants" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."ai_chat_participants" add column if not exists "kind" text not null default 'user' check ("kind" in ('user', 'team', 'customer', 'external'));
alter table "better_supabase"."ai_chat_participants" add column if not exists "team_id" uuid;
alter table "better_supabase"."ai_chat_participants" add column if not exists "customer_user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."ai_chat_participants" add column if not exists "email" text check (length("email") <= 320);
alter table "better_supabase"."ai_chat_participants" alter column "id" set not null;
do $$
declare
  v_key name;
begin
  select c.conname into v_key from pg_catalog.pg_constraint c
  where c.conrelid = '"better_supabase"."ai_chat_participants"'::regclass and c.contype = 'p'
    and not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = c.conrelid and a.attnum = any (c.conkey) and a.attname = 'id'
    );
  if v_key is not null then
    execute format('alter table %s drop constraint %I', '"better_supabase"."ai_chat_participants"', v_key);
  end if;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = '"better_supabase"."ai_chat_participants"'::regclass and contype = 'p') then
    alter table "better_supabase"."ai_chat_participants" add primary key ("id");
  end if;
  alter table "better_supabase"."ai_chat_participants" alter column "user_id" drop not null;
  if not exists (select 1 from pg_catalog.pg_constraint where conrelid = '"better_supabase"."ai_chat_participants"'::regclass and conname = 'ai_chat_participants_shape_check') then
    alter table "better_supabase"."ai_chat_participants" add constraint "ai_chat_participants_shape_check" check (
      ("kind" = 'user' and "user_id" is not null)
      or ("kind" = 'team' and "team_id" is not null)
      or ("kind" = 'customer' and "customer_user_id" is not null)
      or ("kind" = 'external' and "email" is not null)
    );
  end if;
end;
$$;
update "better_supabase"."ai_chats" x set "visibility" = 'shared'
where x."visibility" = 'private'
  and exists (select 1 from "better_supabase"."ai_chat_participants" p where p."chat_id" = x."id");
