set lock_timeout = '5s';

create or replace function "better_supabase"."revoke_ai_chat_share"(id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_chat text;
  v_tenant uuid;
  v_owner uuid;
  v_ok boolean;
begin
  select l."subject_id", l."tenant_id" into v_chat, v_tenant
  from "better_supabase"."share_links" as l where l."id" = revoke_ai_chat_share.id and l."subject_type" = 'ai-chat';
  v_ok := "better_supabase"."revoke_share_link"(revoke_ai_chat_share.id);
  if v_ok and v_chat is not null then
    select t.owner_id into v_owner from "better_supabase".ai_chats as t where t.id::text = v_chat;
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
$$;
