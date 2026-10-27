-- better-supabase upgrade: steps that run before the schema diff.

-- inbox: version 4 to 5. Widget conversations get the Chat SDK thread id <topic>:<inbox id>:<conversation id>, so channelIdFromThreadId names the inbox; Chat SDK subscriptions and thread state move with them. list_inbox_messages takes after, for pages read oldest first.
update "better_supabase"."chat_state_subscriptions" x set "thread_id" = 'inbox:' || v."inbox_id"::text || ':' || v."id"::text
from "better_supabase"."inbox_conversations" v where x."thread_id" = 'inbox:' || v."id"::text and v."thread_id" = 'inbox:' || v."id"::text;
update "better_supabase"."chat_state_cache" x set "cache_key" = 'thread-state:' || 'inbox:' || v."inbox_id"::text || ':' || v."id"::text
from "better_supabase"."inbox_conversations" v where x."cache_key" = 'thread-state:' || 'inbox:' || v."id"::text and v."thread_id" = 'inbox:' || v."id"::text;
update "better_supabase"."inbox_conversations" v set "thread_id" = 'inbox:' || v."inbox_id"::text || ':' || v."id"::text
where v."thread_id" = 'inbox:' || v."id"::text;
drop function if exists "better_supabase"."list_inbox_messages"(uuid, timestamptz, integer);
