-- Policies on realtime.messages and triggers on auth.users. A schema diff skips the
-- schemas Supabase manages, so the declarative files carry them as plain statements.

create policy bsb_realtime_tables_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) like 'bsb:t:%'
    and not coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false)
    and (
      split_part((select realtime.topic()), ':', 4) = ''
      or (split_part((select realtime.topic()), ':', 5) = '' and split_part((select realtime.topic()), ':', 4) in (
        select t.m::text from (select better_supabase.member_organization_ids() as m) t
      ))
      or (split_part((select realtime.topic()), ':', 4) = 'u'
        and split_part((select realtime.topic()), ':', 5) = (select auth.uid())::text)
    ));

create policy bsb_notifications_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ ('^' || 'notifications:' || (select auth.uid())::text || '$'));

create policy bsb_authz_versions_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'authz:' || (select auth.uid())::text);

create policy bsb_attachments_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'attachments:%'
        and substr((select realtime.topic()), 13) in (select x::text from better_supabase.tenant_ids_with('attachments.read') x));

create policy bsb_announcements_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');

create policy bsb_streams_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'stream:%'
        and exists (
          select 1 from "better_supabase"."streams" st
          where st."id" = substr((select realtime.topic()), 8)
            and st."owner_id" = (select auth.uid())
        ));

create policy bsb_workflow_runs_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (
          (
            (select realtime.topic()) like 'workflow-run:%'
            and exists (
              select 1 from "better_supabase"."workflow_runs" x
              where x."id"::text = substr((select realtime.topic()), 14)
            )
          )
          or (
            (select realtime.topic()) like 'workflow-runs:%'
            and substr((select realtime.topic()), 15) in (
              select t::text from better_supabase.tenant_ids_with('workflows.read') t
            )
          )
        ));

create policy bsb_inbox_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'inbox:org:%'
        and substr((select realtime.topic()), 11) in (select x::text from better_supabase.tenant_ids_with('inbox.read') x));

create policy bsb_ai_chat_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'ai-chat:%'
        and substr((select realtime.topic()), 9) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and "better_supabase"."ai_chat_can_read"(substr((select realtime.topic()), 9)::uuid));

create policy bsb_ai_chats_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) = 'ai-chats:' || (select auth.uid())::text);

create policy bsb_subject_presence_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'presence'
        and (select realtime.topic()) like 'presence:' || '%'
        and "better_supabase"."subject_presence_allowed"((select realtime.topic())));

create policy bsb_subject_presence_send on realtime.messages
  for insert to authenticated
  with check ((realtime.messages.extension = 'presence'
        and (select realtime.topic()) like 'presence:' || '%'
        and "better_supabase"."subject_presence_allowed"((select realtime.topic()))) and (select better_supabase.actor_may_write()));

create policy bsb_reactions_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'reactions:%'
        and substr((select realtime.topic()), 11) in (select x::text from better_supabase.tenant_ids_with('reactions.read') x));

create policy bsb_documents_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension in ('broadcast', 'presence')
        and "better_supabase"."document_topic_access"((select realtime.topic()), false));

create policy bsb_documents_send on realtime.messages
  for insert to authenticated
  with check (((realtime.messages.extension = 'broadcast' and "better_supabase"."document_topic_access"((select realtime.topic()), true))
        or (realtime.messages.extension = 'presence' and "better_supabase"."document_topic_access"((select realtime.topic()), false))) and (select better_supabase.actor_may_write()));

create policy bsb_kitchen_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'kitchen:%'
        and substr((select realtime.topic()), 9) in (
          select t::text from better_supabase.tenant_ids_with('orders.read') t
          union all
          select t::text from better_supabase.tenant_ids_with('orders.prepare') t
        ));

create policy bsb_messaging_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like 'messages:' || '%'
        and "better_supabase"."conversation_topic_allowed"(substr((select realtime.topic()), 10)));

create policy bsb_messaging_broadcast on realtime.messages
  for insert to authenticated
  with check ((realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like 'messages:' || '%'
        and "better_supabase"."conversation_topic_allowed"(substr((select realtime.topic()), 10))) and (select better_supabase.actor_may_write()));

create trigger "bsb_profile_sync" after insert on auth.users
  for each row execute function "better_supabase"."on_auth_user_created"();

create trigger "bsb_profile_email" after update of email on auth.users
  for each row execute function "better_supabase"."mirror_profile_email"();

create trigger "bsb_sso_auth_user" after insert or update of email, email_confirmed_at on auth.users
  for each row execute function "better_supabase"."sso_on_auth_user"();

create trigger "bsb_waitlist_auth_user" after insert on auth.users
  for each row execute function "better_supabase"."waitlist_on_auth_user"();
