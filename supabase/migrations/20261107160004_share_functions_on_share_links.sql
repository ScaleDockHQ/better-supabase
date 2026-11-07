SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_shared_ai_chat (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_shared_ai_chat"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_chat_shares (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_chat_shares"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_shared_ai_chat (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_subject text;
  v_tenant text;
  v_leaf text;
  v_chat_id uuid;
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select l."subject_id", l."tenant_id"::text, l."leaf_id"
    into v_subject, v_tenant, v_leaf
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(get_shared_ai_chat.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'ai-chat'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
  if not found or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_chat_id := v_subject::uuid;
  -- The chat must still live in the tenant the link was created in.
  if not exists (select 1 from "better_supabase".ai_chats where id = v_chat_id and organization_id::text = v_tenant) then
    return null;
  end if;
  return jsonb_build_object(
    'chat', (select jsonb_build_object('id', id, 'title', title, 'model', model, 'created_at', created_at) from "better_supabase".ai_chats where id = v_chat_id),
    'leaf_id', v_leaf,
    'messages', "better_supabase"."ai_message_path_of"(v_chat_id, v_leaf, false)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_chat_shares (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select "better_supabase"."list_share_links"('ai-chat', list_ai_chat_shares.chat::text)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_ai_chat_share (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_chat text;
  v_tenant uuid;
  v_owner uuid;
  v_ok boolean;
begin
  select "subject_id", "tenant_id" into v_chat, v_tenant
  from "better_supabase"."share_links" where "id" = revoke_ai_chat_share.id and "subject_type" = 'ai-chat';
  v_ok := "better_supabase"."revoke_share_link"(revoke_ai_chat_share.id);
  if v_ok and v_chat is not null then
    select owner_id into v_owner from "better_supabase".ai_chats where id::text = v_chat;
    perform "better_supabase".emit_event('ai_chat.share_revoked', jsonb_build_object('chatId', v_chat, 'shareId', revoke_ai_chat_share.id, 'organizationId', v_tenant::text, 'ownerId', v_owner), 'ai-chats/' || v_chat, (v_tenant)::text, null, 'better-supabase/ai-chat');
  perform better_supabase.audit_event(
    event_type => 'ai_chat.share_revoked',
    category => 'ai',
    target_type => 'ai_chat_share',
    record_id => revoke_ai_chat_share.id::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('chatId', v_chat, 'shareId', revoke_ai_chat_share.id, 'organizationId', v_tenant::text, 'ownerId', v_owner)
  );
  end if;
  return v_ok;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.share_ai_chat (
  chat uuid,
  leaf text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_owner uuid;
  v_leaf text;
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select organization_id, owner_id, current_leaf_id into v_tenant, v_owner, v_leaf
  from "better_supabase".ai_chats where id = share_ai_chat.chat;
  if not found or v_owner is distinct from auth.uid() then
    raise exception 'no chat' using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_leaf);
  insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "role", "created_by", "leaf_id")
  values (v_tenant, 'ai-chat', share_ai_chat.chat::text, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), 'view', auth.uid(), v_leaf)
  returning "id" into v_id;
  perform "better_supabase".emit_event('ai_chat.shared', jsonb_build_object('chatId', share_ai_chat.chat, 'shareId', v_id, 'organizationId', v_tenant::text, 'ownerId', v_owner, 'leafId', v_leaf), 'ai-chats/' || share_ai_chat.chat::text, (v_tenant)::text, 'ai_chat.shared:' || v_id::text, 'better-supabase/ai-chat');
  perform better_supabase.audit_event(
    event_type => 'ai_chat.shared',
    category => 'ai',
    target_type => 'ai_chat_share',
    record_id => v_id::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('chatId', share_ai_chat.chat, 'shareId', v_id, 'organizationId', v_tenant::text, 'ownerId', v_owner, 'leafId', v_leaf),
    idempotency_key => 'ai_chat.shared:' || v_id::text
  );
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf);
end;
$function$;
