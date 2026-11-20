SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.suggest_inbox_draft (
  conversation uuid,
  input        jsonb,
  metadata     jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_row "better_supabase"."inbox_drafts"%rowtype;
  v_input jsonb := coalesce(input, '{}'::jsonb) - 'files' - 'external_id' - 'author_type' - 'delivered_by_caller';
  v_metadata jsonb := suggest_inbox_draft.metadata;
begin
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = suggest_inbox_draft.conversation;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if length(coalesce(v_input ->> 'body', '')) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  if v_metadata is not null and jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be an object' using errcode = '22023', hint = 'INBOX_DRAFT_METADATA';
  end if;
  if v_metadata ? 'replyKey' then
    select * into v_row from "better_supabase"."inbox_drafts" x
    where x."conversation_id" = v_conv."id" and x."source" = 'ai'
      and x."metadata" ->> 'replyKey' = v_metadata ->> 'replyKey';
    if found then
      return to_jsonb(v_row);
    end if;
  end if;
  insert into "better_supabase"."inbox_drafts" ("tenant_id", "conversation_id", "author_id", "source", "input", "metadata")
  values (v_conv."tenant_id", v_conv."id", null, 'ai', v_input, coalesce(v_metadata, '{}'::jsonb))
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE UNIQUE INDEX inbox_drafts_ai_key ON better_supabase.inbox_drafts USING btree (conversation_id, ((metadata ->> 'replyKey'::text)))
  WHERE ((source = 'ai'::text) AND (metadata ? 'replyKey'::text));
