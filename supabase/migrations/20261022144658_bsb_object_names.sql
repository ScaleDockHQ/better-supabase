SET local check_function_bodies = off;

DROP EVENT TRIGGER "bs_audit_forget_dropped";

DROP POLICY "bs_drive_attachments_delete" ON "better_supabase"."attachments";

DROP POLICY "bs_drive_attachments_insert" ON "better_supabase"."attachments";

DROP POLICY "bs_drive_attachments_read" ON "better_supabase"."attachments";

DROP POLICY "bs_audit_read" ON "better_supabase"."audit_events";

DROP POLICY "bs_invitations_read" ON "better_supabase"."invitations";

DROP POLICY "bs_notification_deliveries_read" ON "better_supabase"."notification_deliveries";

DROP POLICY "bs_notification_delivery_events_read" ON "better_supabase"."notification_delivery_events";

DROP POLICY "bs_notification_events_read" ON "better_supabase"."notification_events";

DROP POLICY "bs_notification_preferences_own_delete" ON "better_supabase"."notification_preferences";

DROP POLICY "bs_notification_preferences_own_insert" ON "better_supabase"."notification_preferences";

DROP POLICY "bs_notification_preferences_own_read" ON "better_supabase"."notification_preferences";

DROP POLICY "bs_notification_preferences_own_update" ON "better_supabase"."notification_preferences";

DROP POLICY "bs_notification_recipients_read" ON "better_supabase"."notification_recipients";

DROP POLICY "bs_notification_recipients_update" ON "better_supabase"."notification_recipients";

DROP POLICY "bs_notification_subscriptions_own_delete" ON "better_supabase"."notification_subscriptions";

DROP POLICY "bs_notification_subscriptions_own_insert" ON "better_supabase"."notification_subscriptions";

DROP POLICY "bs_notification_subscriptions_own_read" ON "better_supabase"."notification_subscriptions";

DROP POLICY "bs_notification_subscriptions_own_update" ON "better_supabase"."notification_subscriptions";

DROP POLICY "bs_notification_suppressions_read" ON "better_supabase"."notification_suppressions";

DROP POLICY "bs_profiles_read" ON "better_supabase"."profiles";

DROP POLICY "bs_profiles_update" ON "better_supabase"."profiles";

DROP POLICY "bs_webhook_deliveries_read" ON "better_supabase"."webhook_deliveries";

DROP POLICY "bs_webhook_endpoints_delete" ON "better_supabase"."webhook_endpoints";

DROP POLICY "bs_webhook_endpoints_insert" ON "better_supabase"."webhook_endpoints";

DROP POLICY "bs_webhook_endpoints_read" ON "better_supabase"."webhook_endpoints";

DROP POLICY "bs_webhook_endpoints_update" ON "better_supabase"."webhook_endpoints";

DROP POLICY "bs_session_active" ON "public"."client_notes";

DROP POLICY "bs_session_active" ON "public"."contacts";

DROP POLICY "bs_session_active" ON "public"."customer_tags";

DROP POLICY "bs_session_active" ON "public"."customers";

DROP POLICY "bs_session_active" ON "public"."locations";

DROP POLICY "bs_session_active" ON "public"."memberships";

DROP POLICY "bs_session_active" ON "public"."notes";

DROP POLICY "bs_session_active" ON "public"."organizations";

DROP POLICY "bs_session_active" ON "public"."plan_features";

DROP POLICY "bs_session_active" ON "public"."plans";

DROP POLICY "bs_session_active" ON "public"."projects";

DROP POLICY "bs_session_active" ON "public"."saved_views";

DROP POLICY "bs_session_active" ON "public"."subscriptions";

DROP POLICY "bs_session_active" ON "public"."tags";

DROP POLICY "bs_session_active" ON "public"."tasks";

DROP POLICY "bs_ai_chat_receive" ON "realtime"."messages";

DROP POLICY "bs_ai_chats_receive" ON "realtime"."messages";

DROP POLICY "bs_announcements_receive" ON "realtime"."messages";

DROP POLICY "bs_documents_receive" ON "realtime"."messages";

DROP POLICY "bs_documents_send" ON "realtime"."messages";

DROP POLICY "bs_inbox_receive" ON "realtime"."messages";

DROP POLICY "bs_kitchen_receive" ON "realtime"."messages";

DROP POLICY "bs_messaging_broadcast" ON "realtime"."messages";

DROP POLICY "bs_messaging_receive" ON "realtime"."messages";

DROP POLICY "bs_notifications_receive" ON "realtime"."messages";

DROP POLICY "bs_reactions_receive" ON "realtime"."messages";

DROP POLICY "bs_realtime_tables_receive" ON "realtime"."messages";

DROP POLICY "bs_streams_receive" ON "realtime"."messages";

DROP POLICY "bs_subject_presence_receive" ON "realtime"."messages";

DROP POLICY "bs_subject_presence_send" ON "realtime"."messages";

DROP POLICY "bs_workflow_runs_receive" ON "realtime"."messages";

DROP POLICY "bs_ai_files_delete" ON "storage"."objects";

DROP POLICY "bs_ai_files_insert" ON "storage"."objects";

DROP POLICY "bs_ai_files_select" ON "storage"."objects";

DROP POLICY "bs_attachments_delete" ON "storage"."objects";

DROP POLICY "bs_attachments_insert" ON "storage"."objects";

DROP POLICY "bs_attachments_select" ON "storage"."objects";

DROP POLICY "bs_avatars_delete" ON "storage"."objects";

DROP POLICY "bs_avatars_insert" ON "storage"."objects";

DROP POLICY "bs_avatars_select" ON "storage"."objects";

DROP POLICY "bs_avatars_update" ON "storage"."objects";

DROP POLICY "bs_customer_logos_delete" ON "storage"."objects";

DROP POLICY "bs_customer_logos_insert" ON "storage"."objects";

DROP POLICY "bs_customer_logos_select" ON "storage"."objects";

DROP POLICY "bs_customer_logos_update" ON "storage"."objects";

DROP POLICY "bs_data_exports_select" ON "storage"."objects";

DROP POLICY "bs_drive_objects_delete" ON "storage"."objects";

DROP POLICY "bs_drive_objects_insert" ON "storage"."objects";

DROP POLICY "bs_drive_objects_read" ON "storage"."objects";

DROP POLICY "bs_drive_objects_update" ON "storage"."objects";

DROP POLICY "bs_inbox_files_read" ON "storage"."objects";

DROP TRIGGER "bs_profile_email" ON "auth"."users";

DROP TRIGGER "bs_profile_sync" ON "auth"."users";

DROP TRIGGER "bs_sso_auth_user" ON "auth"."users";

DROP TRIGGER "bs_waitlist_auth_user" ON "auth"."users";

DROP TRIGGER "bs_announcements_broadcast" ON "better_supabase"."announcements";

DROP TRIGGER "bs_application_guard" ON "better_supabase"."applications";

DROP TRIGGER "bs_pipeline_application" ON "better_supabase"."applications";

DROP TRIGGER "bs_pipeline_status_application" ON "better_supabase"."applications";

DROP TRIGGER "bs_asset_locations_parent" ON "better_supabase"."asset_locations";

DROP TRIGGER "bs_audit_append_only" ON "better_supabase"."audit_events";

DROP TRIGGER "bs_audit_no_truncate" ON "better_supabase"."audit_events";

DROP TRIGGER "bookings_engagement" ON "better_supabase"."bookings";

DROP TRIGGER "bs_search_calendar_event_index" ON "better_supabase"."calendar_events";

DROP TRIGGER "bs_search_channel_index" ON "better_supabase"."channels";

DROP TRIGGER "bs_field_history_company" ON "better_supabase"."companies";

DROP TRIGGER "bs_search_company_index" ON "better_supabase"."companies";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."contacts";

DROP TRIGGER "bs_search_course_index" ON "better_supabase"."courses";

DROP TRIGGER "bs_deal_lines_totals_delete" ON "better_supabase"."deal_lines";

DROP TRIGGER "bs_deal_lines_totals_insert" ON "better_supabase"."deal_lines";

DROP TRIGGER "bs_deal_lines_totals_update" ON "better_supabase"."deal_lines";

DROP TRIGGER "bs_deal_guard" ON "better_supabase"."deals";

DROP TRIGGER "bs_field_history_deal" ON "better_supabase"."deals";

DROP TRIGGER "bs_pipeline_deal" ON "better_supabase"."deals";

DROP TRIGGER "bs_pipeline_status_deal" ON "better_supabase"."deals";

DROP TRIGGER "bs_search_deal_index" ON "better_supabase"."deals";

DROP TRIGGER "bs_drive_node_moved" ON "better_supabase"."drive_nodes";

DROP TRIGGER "bs_drive_node_path" ON "better_supabase"."drive_nodes";

DROP TRIGGER "bs_drive_node_purged" ON "better_supabase"."drive_nodes";

DROP TRIGGER "bs_drive_node_purging" ON "better_supabase"."drive_nodes";

DROP TRIGGER "bs_search_drive_node_index" ON "better_supabase"."drive_nodes";

DROP TRIGGER "bs_employee_manager_guard" ON "better_supabase"."employees";

DROP TRIGGER "bs_employee_user_mirror" ON "better_supabase"."employees";

DROP TRIGGER "bs_search_employee_index" ON "better_supabase"."employees";

DROP TRIGGER "bs_search_engagement_index" ON "better_supabase"."engagements";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."inbox_conversations";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."inboxes";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."invitations";

DROP TRIGGER "bs_invoice_lines_totals_delete" ON "better_supabase"."invoice_lines";

DROP TRIGGER "bs_invoice_lines_totals_insert" ON "better_supabase"."invoice_lines";

DROP TRIGGER "bs_invoice_lines_totals_update" ON "better_supabase"."invoice_lines";

DROP TRIGGER "bs_billable_time_release" ON "better_supabase"."invoices";

DROP TRIGGER "bs_ledger_entries_append_only" ON "better_supabase"."ledger_entries";

DROP TRIGGER "bs_ledger_entries_apply" ON "better_supabase"."ledger_entries";

DROP TRIGGER "bs_ledger_entries_balanced" ON "better_supabase"."ledger_entries";

DROP TRIGGER "bs_ledger_transactions_append_only" ON "better_supabase"."ledger_transactions";

DROP TRIGGER "bs_mail_changed" ON "better_supabase"."mail_messages";

DROP TRIGGER "bs_replied" ON "better_supabase"."mail_messages";

DROP TRIGGER "bs_mail_linked" ON "better_supabase"."mail_thread_subjects";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."message_deliveries";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."message_templates";

DROP TRIGGER "bs_messages_moderation_guard" ON "better_supabase"."messages";

DROP TRIGGER "bs_messaging_inbox_broadcast" ON "better_supabase"."messages";

DROP TRIGGER "bs_messaging_message_broadcast" ON "better_supabase"."messages";

DROP TRIGGER "bs_messaging_message_written" ON "better_supabase"."messages";

DROP TRIGGER "bs_posts_replied" ON "better_supabase"."messages";

DROP TRIGGER "bs_posts_reply_guard" ON "better_supabase"."messages";

DROP TRIGGER "bs_search_message_index" ON "better_supabase"."messages";

DROP TRIGGER "bs_posts_moderated" ON "better_supabase"."moderation_items";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."notification_preferences";

DROP TRIGGER "bs_notification_broadcast_update" ON "better_supabase"."notification_recipients";

DROP TRIGGER "bs_notification_broadcast" ON "better_supabase"."notification_recipients";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."notification_subscriptions";

DROP TRIGGER "bs_order_line_preparations_broadcast" ON "better_supabase"."order_line_preparations";

DROP TRIGGER "bs_record_organization_setting" ON "better_supabase"."organization_settings";

DROP TRIGGER "bs_person_changed" ON "better_supabase"."people";

DROP TRIGGER "bs_search_person_index" ON "better_supabase"."people";

DROP TRIGGER "bs_record_platform_setting" ON "better_supabase"."platform_settings";

DROP TRIGGER "bs_posts_removed" ON "better_supabase"."posts";

DROP TRIGGER "bs_search_post_index" ON "better_supabase"."posts";

DROP TRIGGER "bs_approvals_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bs_attachments_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bs_comments_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bs_documents_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bs_notifications_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bs_reactions_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bs_relations_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bs_search_product_variant_index" ON "better_supabase"."product_variants";

DROP TRIGGER "bs_approvals_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bs_attachments_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bs_comments_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bs_documents_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bs_notifications_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bs_reactions_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bs_relations_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bs_search_product_index" ON "better_supabase"."products";

DROP TRIGGER "bs_profile_guard" ON "better_supabase"."profiles";

DROP TRIGGER "bs_quote_lines_totals_delete" ON "better_supabase"."quote_lines";

DROP TRIGGER "bs_quote_lines_totals_insert" ON "better_supabase"."quote_lines";

DROP TRIGGER "bs_quote_lines_totals_update" ON "better_supabase"."quote_lines";

DROP TRIGGER "bs_reactions_changed" ON "better_supabase"."reactions";

DROP TRIGGER "bs_reactions_check" ON "better_supabase"."reactions";

DROP TRIGGER "bs_reactions_tally" ON "better_supabase"."reactions";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."scheduled_inbox_messages";

DROP TRIGGER "bs_segment_changed" ON "better_supabase"."segment_members";

DROP TRIGGER "bs_contracts_signature_settled" ON "better_supabase"."signature_requests";

DROP TRIGGER "bs_signing_key_vault" ON "better_supabase"."signing_keys";

DROP TRIGGER "bs_billable_time_guard" ON "better_supabase"."time_entries";

DROP TRIGGER "bs_time_entry_guard" ON "better_supabase"."time_entries";

DROP TRIGGER "bs_webhook_secret_vault" ON "better_supabase"."webhook_endpoint_secrets";

DROP TRIGGER "bs_updated_at" ON "better_supabase"."webhook_endpoints";

DROP TRIGGER "bs_webhook_endpoint_reenable" ON "better_supabase"."webhook_endpoints";

DROP TRIGGER "bs_pipeline_status_work_item" ON "better_supabase"."work_items";

DROP TRIGGER "bs_pipeline_work_item" ON "better_supabase"."work_items";

DROP TRIGGER "bs_search_work_item_index" ON "better_supabase"."work_items";

DROP TRIGGER "bs_transition_work_item" ON "better_supabase"."work_items";

DROP TRIGGER "bs_work_item_guard" ON "better_supabase"."work_items";

DROP TRIGGER "bs_workflow_runs_alert" ON "better_supabase"."workflow_runs";

DROP TRIGGER "bs_workflow_runs_status" ON "better_supabase"."workflow_runs";

DROP TRIGGER "bs_seal_fields" ON "public"."client_notes";

DROP TRIGGER "bs_updated_at" ON "public"."client_notes";

DROP TRIGGER "bs_search_customer_index" ON "public"."customers";

DROP TRIGGER "bs_organization_owner" ON "public"."memberships";

DROP TRIGGER "bs_organization_role_guard" ON "public"."memberships";

DROP TRIGGER "bs_search_project_index" ON "public"."projects";

DROP TRIGGER "bs_updated_at" ON "public"."projects";

DROP TRIGGER "bs_versions_project_auto" ON "public"."projects";

DROP TRIGGER "bs_updated_at" ON "public"."saved_views";

DROP TRIGGER "bs_emit_event" ON "public"."tasks";

DROP TRIGGER "bs_updated_at" ON "public"."tasks";

DROP TRIGGER "bs_workflow_sdk_runs_mirror" ON "workflow"."workflow_runs";

ALTER TABLE "better_supabase"."announcements"
  DROP CONSTRAINT "bs_announcements_audience";

ALTER TABLE "better_supabase"."attachments"
  DROP CONSTRAINT "bs_attachments_bucket";

ALTER TABLE "better_supabase"."attachments"
  DROP CONSTRAINT "bs_attachments_size";

ALTER TABLE "better_supabase"."audit_events"
  DROP CONSTRAINT "bs_audit_op_check";

ALTER TABLE "better_supabase"."drive_grants"
  DROP CONSTRAINT "bs_drive_grants_role";

ALTER TABLE "better_supabase"."drive_nodes"
  DROP CONSTRAINT "bs_drive_nodes_attachment";

ALTER TABLE "better_supabase"."field_definitions"
  DROP CONSTRAINT "bs_field_definitions_type";

DROP FUNCTION "better_supabase"."bs_application_guard"();

DROP FUNCTION "better_supabase"."bs_booking_engagement"();

DROP FUNCTION "better_supabase"."bs_deal_guard"();

DROP FUNCTION "better_supabase"."bs_deal_lines_totals"();

DROP FUNCTION "better_supabase"."bs_employee_manager_guard"();

DROP FUNCTION "better_supabase"."bs_employee_user_mirror"();

DROP FUNCTION "better_supabase"."bs_field_history_company"();

DROP FUNCTION "better_supabase"."bs_field_history_deal"();

DROP FUNCTION "better_supabase"."bs_invoice_lines_totals"();

DROP FUNCTION "better_supabase"."bs_pipeline_application"();

DROP FUNCTION "better_supabase"."bs_pipeline_deal"();

DROP FUNCTION "better_supabase"."bs_pipeline_status_application"();

DROP FUNCTION "better_supabase"."bs_pipeline_status_deal"();

DROP FUNCTION "better_supabase"."bs_pipeline_status_work_item"();

DROP FUNCTION "better_supabase"."bs_pipeline_work_item"();

DROP FUNCTION "better_supabase"."bs_quote_lines_totals"();

DROP FUNCTION "better_supabase"."bs_transition_work_item"();

DROP FUNCTION "better_supabase"."bs_work_item_guard"();

CREATE OR REPLACE FUNCTION better_supabase.audit (
  target          regclass,
  ignore          text[]       DEFAULT '{}'::text[],
  replace_trigger boolean      DEFAULT false,
  redact          text[]       DEFAULT '{}'::text[],
  category        text         DEFAULT NULL::text,
  event_prefix    text         DEFAULT NULL::text,
  target_type     text         DEFAULT NULL::text,
  tenant_column   text         DEFAULT NULL::text,
  label_column    text         DEFAULT NULL::text,
  tenant_path     text         DEFAULT NULL::text,
  tenant_function regprocedure DEFAULT NULL::regprocedure
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  keys text[];
  path_steps jsonb := '[]';
  path_column text;
  parts text[];
  cur_rel regclass := target;
  cur_col text;
  ref_rel regclass;
  ref_col text;
  segment text;
  seg_table text;
  seg_read text;
  base_settings jsonb;
begin
  if audit.tenant_path is not null then
    parts := regexp_split_to_array(btrim(audit.tenant_path), '\s*->\s*');
    if coalesce(array_length(parts, 1), 0) < 2 then
      raise exception 'tenant_path % needs a column and at least one table.column hop', audit.tenant_path;
    end if;
    path_column := parts[1];
    cur_col := path_column;
    for i in 2..array_length(parts, 1) loop
      segment := parts[i];
      seg_read := substring(segment from '[^.]+$');
      seg_table := substring(segment from '^(.*)\.[^.]+$');
      if seg_read is null or seg_table is null then
        raise exception 'tenant_path hop % must be table.column', segment;
      end if;
      select con.confrelid::regclass, a.attname::text into ref_rel, ref_col
      from pg_catalog.pg_constraint con
      join pg_catalog.pg_attribute a on a.attrelid = con.confrelid and a.attnum = con.confkey[1]
      where con.contype = 'f' and con.conrelid = cur_rel and array_length(con.conkey, 1) = 1
        and con.conkey[1] = (
          select c.attnum from pg_catalog.pg_attribute c
          where c.attrelid = cur_rel and c.attname = cur_col and not c.attisdropped
        );
      if ref_rel is null then
        raise exception 'tenant_path: % has no foreign key on column %', cur_rel, cur_col;
      end if;
      if pg_catalog.to_regclass(case when position('.' in seg_table) > 0 then seg_table else (select n.nspname from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace where c.oid = audit.target) || '.' || seg_table end) is distinct from ref_rel then
        raise exception 'tenant_path: % does not reference %', cur_col, seg_table;
      end if;
      path_steps := path_steps || jsonb_build_array(jsonb_build_object('table', ref_rel::text, 'ref', ref_col, 'read', seg_read));
      cur_rel := ref_rel;
      cur_col := seg_read;
    end loop;
  end if;
  perform better_supabase.replace_equivalent_triggers(
    target, 'bsb_audit', 'audit', replace_trigger
  );
  select array_agg(c.attname::text order by k.ord) into keys
  from pg_catalog.pg_index i
  cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
  join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
  where i.indrelid = audit.target and i.indisprimary;
  delete from better_supabase.audited_tables a where a.target = audit.target;
  base_settings := jsonb_strip_nulls(jsonb_build_object(
    'ignore', to_jsonb(coalesce(audit.ignore, '{}')),
    'redact', to_jsonb(coalesce(audit.redact, '{}')),
    'key_columns', to_jsonb(keys),
    'category', audit.category,
    'event_prefix', audit.event_prefix,
    'target_type', audit.target_type,
    'tenant_column', audit.tenant_column,
    'label_column', audit.label_column,
    'tenant_path', case when audit.tenant_path is not null then jsonb_build_object('column', path_column, 'steps', path_steps) end,
    'tenant_function', audit.tenant_function::text
  ));
  execute format('drop trigger if exists bsb_audit on %s', target);
  execute format('drop trigger if exists bsb_audit_update on %s', target);
  if cardinality(coalesce(audit.ignore, '{}')) > 0 then
    execute format(
      'create trigger bsb_audit after insert or delete on %s for each row execute function better_supabase.audit_row_change(%L)',
      target, base_settings::text
    );
    execute format(
      'create trigger bsb_audit_update after update on %s for each row when ((to_jsonb(old) - %L::text[]) is distinct from (to_jsonb(new) - %L::text[])) execute function better_supabase.audit_row_change(%L)',
      target, audit.ignore, audit.ignore, base_settings::text
    );
  else
    execute format(
      'create trigger bsb_audit after insert or update or delete on %s for each row execute function better_supabase.audit_row_change(%L)',
      target, base_settings::text
    );
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_schema (
  schema_name   text,
  tenant_column text,
  exempt        text[] DEFAULT '{}'::text[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  registered integer := 0;
  target regclass;
begin
  for target in
    select format('%I.%I', n.nspname, c.relname)::regclass
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = schema_name
      and c.relkind in ('r', 'p')
      and not c.relispartition
      and exists (
        select 1 from pg_catalog.pg_attribute a
        where a.attrelid = c.oid and a.attname = audit_schema.tenant_column and a.attnum > 0 and not a.attisdropped
      )
      and not exists (select 1 from unnest(exempt) e where c.relname like e)
      and not exists (
        select 1 from pg_catalog.pg_trigger t where t.tgrelid = c.oid and t.tgname = 'bsb_audit'
      )
    order by c.relname
  loop
    perform better_supabase.audit(target);
    registered := registered + 1;
  end loop;
  return registered;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_settings (
  target regclass
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(
    (select convert_from(substring(t.tgargs from 1 for position('\x00'::bytea in t.tgargs) - 1), 'utf8')::jsonb
     from pg_catalog.pg_trigger t
     where t.tgrelid = audit_settings.target and t.tgname = 'bsb_audit' and t.tgnargs > 0),
    (select jsonb_strip_nulls(jsonb_build_object(
       'ignore', to_jsonb(a.ignore), 'redact', to_jsonb(a.redact), 'key_columns', to_jsonb(a.key_columns),
       'category', a.category, 'event_prefix', a.event_prefix, 'target_type', a.target_type,
       'tenant_column', a.tenant_column, 'label_column', a.label_column))
     from better_supabase.audited_tables a where a.target = audit_settings.target)
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.broadcast_topic()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  topic text;
  event text := tg_op;
  private boolean := true;
  mode text := 'keys';
  cache_key text := 'bsb_topic.r' || tg_relid::text || '_' || md5(tg_name);
  stamp text := statement_timestamp()::text;
  plan jsonb;
  placeholder text;
  param text;
  col text;
  placeholders text[] := '{}';
  params text[] := '{}';
  cols text[] := '{}';
  keys text[];
  id_sql text;
  vals text[];
  value text;
  payload_vals jsonb := '{}';
  id jsonb;
begin
  if tg_level <> 'ROW' then
    raise exception 'better_supabase.broadcast_topic() runs for each row'
      using errcode = '39P01';
  end if;
  if tg_when <> 'AFTER' then
    raise exception 'better_supabase.broadcast_topic() runs after the write; as a % trigger it would cancel the write', lower(tg_when)
      using errcode = '39P01';
  end if;
  if tg_nargs = 0 or tg_argv[0] = '' then
    raise exception 'better_supabase.broadcast_topic() needs the topic as its first argument'
      using errcode = '39P01';
  end if;
  topic := tg_argv[0];
  if tg_nargs > 1 and tg_argv[1] <> '' then event := tg_argv[1]; end if;
  if tg_nargs > 2 and tg_argv[2] <> '' then private := tg_argv[2]::boolean; end if;
  if tg_nargs > 3 and tg_argv[3] <> '' then mode := tg_argv[3]; end if;
  if mode not in ('keys', 'row') then
    raise exception 'better_supabase.broadcast_topic() payload must be keys or row, not %', mode
      using errcode = '22023';
  end if;
  plan := nullif(current_setting(cache_key, true), '')::jsonb;
  if plan is null or plan ->> 'stamp' is distinct from stamp then
    for placeholder in select distinct m[1] from regexp_matches(tg_argv[0], '\{([^}]+)\}', 'g') as m loop
      param := split_part(placeholder, '=', 1);
      col := coalesce(nullif(split_part(placeholder, '=', 2), ''), param);
      if not exists (
        select 1 from pg_catalog.pg_attribute a
        where a.attrelid = tg_relid and a.attname = col and a.attnum > 0 and not a.attisdropped
      ) then
        raise exception '%.% has no column % for the topic %', tg_table_schema, tg_table_name, col, tg_argv[0]
          using errcode = '42703';
      end if;
      placeholders := placeholders || placeholder;
      params := params || param;
      cols := cols || col;
    end loop;
    select array_agg(a.attname::text order by array_position(i.indkey::int2[], a.attnum))
      into keys
      from pg_catalog.pg_index i
      join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey::int2[])
      where i.indrelid = tg_relid and i.indisprimary;
    id_sql := case
      when keys is null then 'null::jsonb'
      when cardinality(keys) = 1 then format('to_jsonb(($1).%I)', keys[1])
      else 'jsonb_build_object(' || (select string_agg(format('%L, ($1).%I', k, k), ', ') from unnest(keys) as k) || ')'
    end;
    plan := jsonb_build_object(
      'stamp', stamp,
      'placeholders', to_jsonb(placeholders),
      'params', to_jsonb(params),
      'cols', to_jsonb(cols),
      'sql', format(
        'select array[%s]::text[], %s',
        coalesce((select string_agg(format('($1).%I::text', c), ', ') from unnest(cols) as c), ''),
        id_sql
      )
    );
    perform set_config(cache_key, plan::text, true);
  end if;
  execute plan ->> 'sql' using case when tg_op = 'DELETE' then old else new end into vals, id;
  for i in 1 .. coalesce(cardinality(vals), 0) loop
    value := vals[i];
    if value is null then
      return null;
    end if;
    if value !~ '^[\w.@+=-]+$' then
      raise warning 'skipped the broadcast on %: topic value % of %.%.% contains characters topics do not allow', tg_argv[0], value, tg_table_schema, tg_table_name, plan -> 'cols' ->> (i - 1);
      return null;
    end if;
    payload_vals := payload_vals || jsonb_build_object(plan -> 'params' ->> (i - 1), value);
    topic := replace(topic, '{' || (plan -> 'placeholders' ->> (i - 1)) || '}', value);
  end loop;
  if mode = 'row' then
    perform realtime.send(
      jsonb_build_object('old_record', old, 'record', new, 'operation', tg_op, 'table', tg_table_name, 'schema', tg_table_schema),
      event, topic, private
    );
    return null;
  end if;
  perform realtime.send(
    jsonb_build_object('operation', tg_op, 'schema', tg_table_schema, 'table', tg_table_name, 'id', id, 'values', payload_vals),
    event, topic, private
  );
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_application_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."state" is not distinct from old."state" then
    new."updated_at" := now();
    return new;
  end if;
  new."hired_at" := case when new."state" = 'hired' then now() end;
  if new."state" <> 'rejected' then
    new."rejection_reason" := null;
  end if;
  case new."state"
    when 'hired' then perform "better_supabase".emit_event('application.hired', jsonb_build_object('organizationId', new."tenant_id", 'applicationId', new."id", 'subjectType', 'application', 'subjectId', new."id"::text, 'jobId', new."job_id", 'candidateType', new."candidate_type", 'candidateId', new."candidate_id"), 'applications/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/hiring');
    when 'rejected' then perform "better_supabase".emit_event('application.rejected', jsonb_build_object('organizationId', new."tenant_id", 'applicationId', new."id", 'subjectType', 'application', 'subjectId', new."id"::text, 'jobId', new."job_id", 'candidateType', new."candidate_type", 'candidateId', new."candidate_id", 'reason', new."rejection_reason"), 'applications/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/hiring');
    when 'withdrawn' then perform "better_supabase".emit_event('application.retracted', jsonb_build_object('organizationId', new."tenant_id", 'applicationId', new."id", 'subjectType', 'application', 'subjectId', new."id"::text, 'jobId', new."job_id", 'candidateType', new."candidate_type", 'candidateId', new."candidate_id"), 'applications/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/hiring');
    else null;
  end case;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_booking_engagement()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_ref text := 'booking:' || new."id"::text;
  v_tenant uuid := new."tenant_id";
  v_id uuid;
  v_inserted boolean;
  v_title text;
  v_owner uuid := new."created_by";
  v_person uuid;
  v_person_owner uuid;
  v_subjects jsonb;
  v_first jsonb;
begin
  if new."status" = 'confirmed' then
    if tg_op = 'UPDATE' and old."status" = 'confirmed' and old."during" = new."during" then
      return null;
    end if;
    select p."id", p."owner_user_id" into v_person, v_person_owner
    from "better_supabase"."people" p
    where p."tenant_id" = v_tenant and p."archived_at" is null and p."merged_into" is null
      and ((new."customer_user_id" is not null and p."user_id" = new."customer_user_id")
        or (new."customer_email" is not null and lower(p."email") = lower(new."customer_email")))
    order by (new."customer_user_id" is not null and p."user_id" = new."customer_user_id") desc, p."created_at"
    limit 1;
    v_owner := coalesce(v_owner, v_person_owner);
    select left(coalesce(sv."name", 'Booking') || coalesce(' with ' || nullif(trim(new."customer_name"), ''), ''), 500)
    into v_title
    from "better_supabase"."booking_services" sv where sv."id" = new."service_id";
    insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "owner_user_id", "due_at", "duration_seconds", "external_ref", "created_by")
    values (v_tenant, 'meeting', coalesce(v_title, 'Booking'), new."notes", v_owner, lower(new."during"),
      extract(epoch from upper(new."during") - lower(new."during"))::integer, v_ref, new."created_by")
    on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
      "due_at" = excluded."due_at", "duration_seconds" = excluded."duration_seconds",
      "done_at" = null, "outcome" = null, "updated_at" = now()
    returning "id", (xmax = 0) into v_id, v_inserted;
    if v_person is not null then
      insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
      values (v_tenant, v_id, 'person', v_person::text, 1)
      on conflict do nothing;
      insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
      select v_tenant, v_id, 'company', c."id"::text, 2
      from "better_supabase"."company_people" k
      join "better_supabase"."companies" c on c."id" = k."company_id"
      where k."person_id" = v_person and c."archived_at" is null
      order by k."is_primary" desc, k."created_at"
      limit 1
      on conflict do nothing;
    end if;
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
    if v_inserted then
      perform "better_supabase".emit_event('engagement.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/engagements');
    else
      perform "better_supabase".emit_event('engagement.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/engagements');
    end if;
  elsif new."status" = 'cancelled' and tg_op = 'UPDATE' and old."status" = 'confirmed' then
    update "better_supabase"."engagements" x set
      "done_at" = coalesce(new."cancelled_at", now()),
      "outcome" = left('cancelled' || coalesce(': ' || nullif(trim(new."cancel_reason"), ''), ''), 500),
      "updated_at" = now()
    where x."tenant_id" = v_tenant and x."external_ref" = v_ref and x."done_at" is null
    returning x."id" into v_id;
    if v_id is not null then
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
      perform "better_supabase".emit_event('engagement.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/engagements');
    end if;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_deal_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claims text;
begin
  if tg_op = 'INSERT' then
    new."closed_at" := case when new."outcome" <> 'open' then now() end;
    if new."owner_user_id" is not null then
      insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
    end if;
    return new;
  end if;
  if old."locked" and not (auth.role() = 'service_role') and (
      new."name" is distinct from old."name"
      or new."company_type" is distinct from old."company_type"
      or new."company_id" is distinct from old."company_id"
      or new."motion" is distinct from old."motion"
      or new."priority" is distinct from old."priority"
      or new."owner_user_id" is distinct from old."owner_user_id"
      or new."product" is distinct from old."product"
      or new."seats" is distinct from old."seats"
      or new."amount" is distinct from old."amount"
      or new."existing_amount" is distinct from old."existing_amount"
      or new."currency" is distinct from old."currency"
      or new."value_period" is distinct from old."value_period"
      or new."pipeline_id" is distinct from old."pipeline_id"
      or new."stage_id" is distinct from old."stage_id"
      or new."probability" is distinct from old."probability"
      or new."forecast_category" is distinct from old."forecast_category"
      or new."expected_close_on" is distinct from old."expected_close_on"
      or new."next_step" is distinct from old."next_step"
      or new."next_at" is distinct from old."next_at"
      or new."next_kind" is distinct from old."next_kind"
      or new."flags" is distinct from old."flags"
      or new."source" is distinct from old."source"
      or new."lost_reason" is distinct from old."lost_reason"
    ) then
    raise exception 'the deal is locked; only its note can change' using errcode = '55000', hint = 'DEAL_LOCKED';
  end if;
  if new."opened_on" is distinct from old."opened_on" and not (auth.role() = 'service_role') then
    raise exception 'the open date never moves' using errcode = '22023', hint = 'DEAL_OPENED_ON_FIXED';
  end if;
  if new."expected_close_on" > old."expected_close_on" and old."outcome" = 'open' then
    new."slipped_from" := coalesce(old."slipped_from", old."expected_close_on");
    new."push_count" := old."push_count" + 1;
  end if;
  if new."forecast_category" is distinct from old."forecast_category" and new."outcome" <> 'open' and old."outcome" <> 'open' then
    raise exception 'a closed deal is called by its stage, not a forecast' using errcode = '22023', hint = 'DEAL_FORECAST_CLOSED';
  end if;
  if new."outcome" is distinct from old."outcome" then
    new."closed_at" := case when new."outcome" <> 'open' then now() end;
    if new."outcome" = 'open' then
      new."lost_reason" := null;
      perform "better_supabase".emit_event('deal.reopened', jsonb_build_object('organizationId', new."tenant_id", 'dealId', new."id", 'subjectType', 'deal', 'subjectId', new."id"::text, 'name', new."name"), 'deals/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/deals');
    else
      perform "better_supabase".emit_event('deal.closed', jsonb_build_object('organizationId', new."tenant_id", 'dealId', new."id", 'subjectType', 'deal', 'subjectId', new."id"::text, 'name', new."name", 'outcome', new."outcome", 'amount', new."amount"::text, 'currency', new."currency", 'reason', new."lost_reason"), 'deals/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/deals');
    end if;
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'deal.closed',
      'tenant', new."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'deal',
      'subject_id', new."id"::text,
      'summary', new."name",
      'key', 'deal.outcome:' || new."id"::text || ':' || new."outcome" || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('dealId', new."id", 'outcome', new."outcome")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if new."owner_user_id" is not null and new."owner_user_id" is distinct from old."owner_user_id" then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_deal_lines_totals()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid;
begin
  for v_parent in execute case tg_op
    when 'INSERT' then 'select distinct n."parent_id" from new_rows n order by 1'
    when 'DELETE' then 'select distinct o."parent_id" from old_rows o order by 1'
    else 'select n."parent_id" from new_rows n union select o."parent_id" from old_rows o order by 1'
  end loop
    perform "better_supabase"."set_deal_lines_recount"(v_parent);
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_employee_manager_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."manager_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."employees" m
    where m."id" = new."manager_id" and m."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the manager is not an employee of this organization' using errcode = '23503', hint = 'EMPLOYEE_MANAGER_NOT_FOUND';
  end if;
  if new."manager_id" = new."id" or exists (
    with recursive up (id) as (
      select m."manager_id" from "better_supabase"."employees" m where m."id" = new."manager_id"
      union
      select m."manager_id" from "better_supabase"."employees" m join up on m."id" = up.id
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'an employee can''t report to one of their own reports' using errcode = '22023', hint = 'EMPLOYEE_MANAGER_CYCLE';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_employee_user_mirror()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."employee_private_details" x set "user_id" = new."user_id"
  where x."employee_id" = new."id"
    and x."user_id" is distinct from new."user_id";
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_field_history_company()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'company', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('owner_user_id', to_jsonb(old."owner_user_id"), to_jsonb(new."owner_user_id")),
      ('lifecycle', to_jsonb(old."lifecycle"), to_jsonb(new."lifecycle"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_field_history_deal()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'deal', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('amount', to_jsonb(old."amount"), to_jsonb(new."amount")),
      ('stage_id', to_jsonb(old."stage_id"), to_jsonb(new."stage_id")),
      ('owner_user_id', to_jsonb(old."owner_user_id"), to_jsonb(new."owner_user_id")),
      ('expected_close_on', to_jsonb(old."expected_close_on"), to_jsonb(new."expected_close_on"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_invoice_lines_totals()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid;
begin
  for v_parent in execute case tg_op
    when 'INSERT' then 'select distinct n."parent_id" from new_rows n order by 1'
    when 'DELETE' then 'select distinct o."parent_id" from old_rows o order by 1'
    else 'select n."parent_id" from new_rows n union select o."parent_id" from old_rows o order by 1'
  end loop
    perform "better_supabase"."set_invoice_lines_recount"(v_parent);
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_application()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'application', new."job_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'application'
    and p."scope_id" is not distinct from new."job_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'application' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'application', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'application', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'application',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_deal()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'deal', null);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'deal'
    and p."scope_id" is not distinct from null;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'deal' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'deal', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, new."amount", new."currency", auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'deal', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'deal',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_status_application()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_status text;
begin
  select case s."category" when 'active' then 'active' when 'hired' then 'hired' when 'rejected' then 'rejected' when 'withdrawn' then 'withdrawn' end into v_status
  from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
  if v_status is not null and v_status is distinct from new."state"::text then
    update "better_supabase"."applications" r set "state" = (jsonb_populate_record(null::"better_supabase"."applications", jsonb_build_object('state', v_status)))."state"
    where r."id" = new."id";
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_status_deal()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_status text;
begin
  select case s."category" when 'open' then 'open' when 'won' then 'won' when 'lost' then 'lost' end into v_status
  from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
  if v_status is not null and v_status is distinct from new."outcome"::text then
    update "better_supabase"."deals" r set "outcome" = (jsonb_populate_record(null::"better_supabase"."deals", jsonb_build_object('outcome', v_status)))."outcome"
    where r."id" = new."id";
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_status_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_status text;
begin
  select case s."category" when 'triage' then 'triage' when 'backlog' then 'backlog' when 'unstarted' then 'unstarted' when 'started' then 'started' when 'completed' then 'completed' when 'canceled' then 'canceled' end into v_status
  from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
  if v_status is not null and v_status is distinct from new."state"::text then
    update "better_supabase"."work_items" r set "state" = (jsonb_populate_record(null::"better_supabase"."work_items", jsonb_build_object('state', v_status)))."state"
    where r."id" = new."id";
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'work_item', new."team_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'work_item'
    and p."scope_id" is not distinct from new."team_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'work_item', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'work_item' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'work_item', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'work_item',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'work_item', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_quote_lines_totals()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid;
begin
  for v_parent in execute case tg_op
    when 'INSERT' then 'select distinct n."parent_id" from new_rows n order by 1'
    when 'DELETE' then 'select distinct o."parent_id" from old_rows o order by 1'
    else 'select n."parent_id" from new_rows n union select o."parent_id" from old_rows o order by 1'
  end loop
    perform "better_supabase"."set_quote_lines_recount"(v_parent);
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    if new."state" is null then
      new."state" := 'backlog';
    end if;
    
    
    return new;
  end if;
  if new."state" is not distinct from old."state" then
    return new;
  end if;
  if not (case old."state" when 'triage' then new."state" = any ('{backlog,unstarted,started,completed,canceled}'::text[]) when 'backlog' then new."state" = any ('{triage,unstarted,started,completed,canceled}'::text[]) when 'unstarted' then new."state" = any ('{triage,backlog,started,completed,canceled}'::text[]) when 'started' then new."state" = any ('{triage,backlog,unstarted,completed,canceled}'::text[]) when 'completed' then new."state" = any ('{triage,backlog,unstarted,started,canceled}'::text[]) when 'canceled' then new."state" = any ('{triage,backlog,unstarted,started,completed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason")
        values (new."tenant_id", 'work_item', new."id"::text, old."state", new."state", auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'from', old."state"::text, 'to', new."state"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/work_item/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_work_item_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."work_items" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'WORK_ITEM_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'WORK_ITEM_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'WORK_ITEM_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      perform "better_supabase".emit_event('work_item.closed', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/work-items');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      perform "better_supabase".emit_event('work_item.reopened', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/work-items');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.client_notes_reveal (
  ids uuid[]
)
  RETURNS TABLE (
    id         uuid,
    diagnosis  text,
    birth_date date
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_read record;
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role reveal client_notes' using errcode = '42501', hint = 'APP_REVEAL_FORBIDDEN';
  end if;
  if coalesce(cardinality(client_notes_reveal.ids), 0) > 500 then
    raise exception 'reveal at most 500 rows of client_notes per call' using errcode = '22023', hint = 'APP_REVEAL_TOO_MANY';
  end if;
  for v_read in
    select t."organization_id" as tenant, jsonb_agg(t.id order by t.id) as ids
    from "public"."client_notes" t
    where t.id = any (client_notes_reveal.ids) and (v_service or ("organization_id" in (select better_supabase.member_organization_ids()) and (select better_supabase.session_active())))
    group by 1
  loop
    perform better_supabase.audit_event(
    event_type => 'client_notes.viewed',
    category => 'read',
    target_type => 'client_notes',
    record_id => case when jsonb_array_length(v_read.ids) = 1 then v_read.ids ->> 0 end,
    summary => 'Revealed ' || jsonb_array_length(v_read.ids)::text || ' ' || 'client_notes' || ' record(s)',
    tenant => (v_read.tenant)::uuid,
    metadata => jsonb_build_object('ids', v_read.ids, 'columns', '["diagnosis","birth_date"]'::jsonb)
  );
  end loop;
  return query
    with r as materialized (
      select t.id, 'tenant:' || (t."organization_id")::text as bsb_owner, t."diagnosis", t."birth_date"
      from "public"."client_notes" t
      where t.id = any (client_notes_reveal.ids) and (v_service or ("organization_id" in (select better_supabase.member_organization_ids()) and (select better_supabase.session_active())))
    ),
    k as materialized (
      select o.bsb_owner, "better_supabase"."field_key"(o.bsb_owner, false) as bsb_key
      from (select distinct r.bsb_owner from r) o
    )
    select r.id, ("better_supabase"."field_open"(k.bsb_key, r."diagnosis"))::text, ("better_supabase"."field_open"(k.bsb_key, r."birth_date"))::date
    from r join k on k.bsb_owner = r.bsb_owner;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reactions_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."reactions"%rowtype;
begin
  if current_setting('better_supabase.bsb_reactions_backfill', true) = 'on' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    v_row := new;
    perform "better_supabase".emit_event('reaction.added', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'emoji', v_row."emoji", 'actor', v_row."actor", 'kind', v_row."kind", 'value', v_row."value"), 'reactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reactions');
  else
    v_row := old;
    perform "better_supabase".emit_event('reaction.removed', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'emoji', v_row."emoji", 'actor', v_row."actor", 'kind', v_row."kind", 'value', v_row."value"), 'reactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reactions');
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'reactions:' || v_row."tenant_id"::text, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_service_principal (
  principal  uuid,
  tenant     uuid,
  name       text,
  role       text,
  is_default boolean DEFAULT false,
  created_by uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if register_service_principal.created_by is not null and not (
    coalesce(better_supabase.member_can(register_service_principal.created_by, register_service_principal.tenant, 'service_principals.manage'), false)
    and coalesce(better_supabase.can_assign_as(register_service_principal.created_by, register_service_principal.tenant, register_service_principal.role), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if not exists (
    select 1 from auth.users u
    where u.id = register_service_principal.principal
      and coalesce((u.raw_app_meta_data ->> 'bsb_service_principal')::boolean, false)
      and u.banned_until > now() + interval '50 years'
  ) then
    raise exception 'The user is not a service principal: create it with createServicePrincipals().create' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_USER';
  end if;
  if not (register_service_principal.role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', register_service_principal.role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if register_service_principal.is_default then
    update "better_supabase"."service_principals" set "is_default" = false
    where "tenant_id" = register_service_principal.tenant and "is_default";
  end if;
  insert into "better_supabase"."service_principals" ("id", "tenant_id", "name", "role", "is_default", "created_by")
  values (register_service_principal.principal, register_service_principal.tenant, register_service_principal.name,
    register_service_principal.role, coalesce(register_service_principal.is_default, false), register_service_principal.created_by);
  perform "better_supabase".emit_event('service_principal.created', jsonb_build_object('organizationId', register_service_principal.tenant::text, 'id', register_service_principal.principal, 'name', register_service_principal.name, 'role', register_service_principal.role), 'service-principals/' || register_service_principal.principal::text, (register_service_principal.tenant)::text, null, 'better-supabase/service-principals');
  perform better_supabase.audit_event(
    event_type => 'service_principal.created',
    category => 'access',
    target_type => 'service_principal',
    record_id => register_service_principal.principal::text,
    target_label => register_service_principal.name,
    tenant => (register_service_principal.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', register_service_principal.tenant::text, 'id', register_service_principal.principal, 'name', register_service_principal.name, 'role', register_service_principal.role),
    actor_id => coalesce(register_service_principal.created_by, auth.uid())
  );
  return jsonb_build_object('id', register_service_principal.principal, 'tenant', register_service_principal.tenant,
    'name', register_service_principal.name, 'role', register_service_principal.role,
    'isDefault', coalesce(register_service_principal.is_default, false));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.track_events (
  target        regclass,
  type_prefix   text     DEFAULT NULL::text,
  tenant_column text     DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  execute format('drop trigger if exists "bsb_outbox_events" on %s', target);
  execute format('drop trigger if exists "bsb_outbox_events_update" on %s', target);
  execute format(
    'create trigger "bsb_outbox_events" after insert or delete on %s for each row execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
  -- jsonb, not the row: a row comparison fails on columns without equality (json).
  execute format(
    'create trigger "bsb_outbox_events_update" after update on %s for each row when (to_jsonb(old) is distinct from to_jsonb(new)) execute function "better_supabase"."outbox_row_event"(%L, %L)',
    target, coalesce(type_prefix, ''), coalesce(tenant_column, '')
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.track_realtime (
  target        regclass,
  tenant_column text     DEFAULT NULL::text,
  user_column   text     DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  scope_column text := coalesce(user_column, tenant_column);
  scope_kind text := case when user_column is null then 'tenant' else 'user' end;
begin
  if scope_column is not null and not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = target and a.attname = scope_column and a.attnum > 0 and not a.attisdropped
  ) then
    raise exception '% has no column %', target, scope_column
      using errcode = '42703',
        hint = case when user_column is null
          then 'Add the tenant column, or list the table in realtime.global to broadcast it to every signed-in user'
          else 'Check the column in realtime.users' end;
  end if;
  execute format('drop trigger if exists bsb_realtime on %s', target);
  execute format('drop trigger if exists bsb_realtime_insert on %s', target);
  execute format('drop trigger if exists bsb_realtime_update on %s', target);
  execute format('drop trigger if exists bsb_realtime_delete on %s', target);
  if scope_column is null then
    execute format(
      'create trigger bsb_realtime after insert or update or delete on %s for each statement execute function better_supabase.broadcast_changes()',
      target
    );
    return;
  end if;
  execute format(
    'create trigger bsb_realtime_insert after insert on %s referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L, %L)',
    target, scope_column, scope_kind
  );
  execute format(
    'create trigger bsb_realtime_update after update on %s referencing old table as old_rows new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L, %L)',
    target, scope_column, scope_kind
  );
  execute format(
    'create trigger bsb_realtime_delete after delete on %s referencing old table as old_rows for each statement execute function better_supabase.broadcast_changes(%L, %L)',
    target, scope_column, scope_kind
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.track_updated_at (
  target          regclass,
  column_name     text     DEFAULT 'updated_at'::text,
  replace_trigger boolean  DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.replace_equivalent_triggers(
    target, 'bsb_updated_at', 'updated_at|moddatetime|touch', replace_trigger
  );
  execute format('drop trigger if exists bsb_updated_at on %s', target);
  execute format(
    'create trigger bsb_updated_at before update on %s for each row execute function better_supabase.set_updated_at(%L)',
    target,
    column_name
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unaudit (
  target regclass
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  execute format('drop trigger if exists bsb_audit on %s', target);
  execute format('drop trigger if exists bsb_audit_update on %s', target);
  delete from better_supabase.audited_tables a where a.target = unaudit.target;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.untrack_realtime (
  target regclass
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  execute format('drop trigger if exists bsb_realtime on %s', target);
  execute format('drop trigger if exists bsb_realtime_insert on %s', target);
  execute format('drop trigger if exists bsb_realtime_update on %s', target);
  execute format('drop trigger if exists bsb_realtime_delete on %s', target);
end;
$function$;

ALTER TABLE "better_supabase"."announcements"
  ADD CONSTRAINT "bsb_announcements_audience" CHECK ((audience = ANY (ARRAY['all'::text, 'tenant'::text, 'role'::text, 'plan'::text])));

ALTER TABLE "better_supabase"."attachments"
  ADD CONSTRAINT "bsb_attachments_bucket" CHECK ((bucket = 'attachments'::text)) NOT VALID;

ALTER TABLE "better_supabase"."attachments"
  ADD CONSTRAINT "bsb_attachments_size" CHECK (((size >= 0) AND (size <= 52428800)));

ALTER TABLE "better_supabase"."audit_events"
  ADD CONSTRAINT "bsb_audit_op_check" CHECK ((op = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text, 'event'::text])));

ALTER TABLE "better_supabase"."drive_grants"
  ADD CONSTRAINT "bsb_drive_grants_role" CHECK ((role = ANY (ARRAY['viewer'::text, 'editor'::text, 'owner'::text])));

ALTER TABLE "better_supabase"."drive_nodes"
  ADD CONSTRAINT "bsb_drive_nodes_attachment" FOREIGN KEY (attachment_id) REFERENCES better_supabase.attachments(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."field_definitions"
  ADD CONSTRAINT "bsb_field_definitions_type"
    CHECK
    ((type = ANY (ARRAY['text'::text, 'number'::text, 'date'::text, 'bool'::text, 'option'::text, 'json'::text, 'email'::text, 'url'::text, 'multi_option'::text, 'user'::text,
    'rating'::text, 'currency'::text])));

CREATE TRIGGER bsb_profile_email
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.mirror_profile_email();

CREATE TRIGGER bsb_profile_sync
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.on_auth_user_created();

CREATE TRIGGER bsb_sso_auth_user
  AFTER INSERT OR UPDATE OF email, email_confirmed_at ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.sso_on_auth_user();

CREATE TRIGGER bsb_waitlist_auth_user
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.waitlist_on_auth_user();

CREATE TRIGGER bsb_announcements_broadcast
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.announcements
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.broadcast_announcement();

CREATE TRIGGER bsb_application_guard
  BEFORE UPDATE OF state ON better_supabase.applications
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_application_guard();

CREATE TRIGGER bsb_pipeline_application
  BEFORE INSERT OR UPDATE OF stage_id, pipeline_id, owner_user_id ON better_supabase.applications
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_pipeline_application();

CREATE TRIGGER bsb_pipeline_status_application
  AFTER INSERT OR UPDATE OF stage_id ON better_supabase.applications
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_pipeline_status_application();

CREATE TRIGGER bsb_asset_locations_parent
  BEFORE INSERT OR UPDATE OF parent_id ON better_supabase.asset_locations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.asset_location_check_parent();

CREATE TRIGGER bsb_audit_append_only
  BEFORE DELETE OR UPDATE ON better_supabase.audit_events
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_append_only();

CREATE TRIGGER bsb_audit_no_truncate
  BEFORE TRUNCATE ON better_supabase.audit_events
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.audit_append_only();

CREATE TRIGGER bookings_engagement
  AFTER INSERT OR UPDATE OF status, during ON better_supabase.bookings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_booking_engagement();

CREATE TRIGGER bsb_search_calendar_event_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, description, location ON better_supabase.calendar_events
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('calendar_event', 'id');

CREATE TRIGGER bsb_search_channel_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, topic, purpose ON better_supabase.channels
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('channel', 'id');

CREATE TRIGGER bsb_field_history_company
  AFTER UPDATE OF owner_user_id, lifecycle ON better_supabase.companies
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_field_history_company();

CREATE TRIGGER bsb_search_company_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, DOMAIN ON better_supabase.companies
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('company', 'id');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.contacts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_search_course_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, summary ON better_supabase.courses
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('course', 'id');

CREATE TRIGGER bsb_deal_lines_totals_delete
  AFTER DELETE ON better_supabase.deal_lines REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bsb_deal_lines_totals();

CREATE TRIGGER bsb_deal_lines_totals_insert
  AFTER INSERT ON better_supabase.deal_lines REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bsb_deal_lines_totals();

CREATE TRIGGER bsb_deal_lines_totals_update
  AFTER UPDATE ON better_supabase.deal_lines REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bsb_deal_lines_totals();

CREATE TRIGGER bsb_deal_guard
  BEFORE INSERT OR UPDATE ON better_supabase.deals
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_deal_guard();

CREATE TRIGGER bsb_field_history_deal
  AFTER UPDATE OF amount, stage_id, owner_user_id, expected_close_on ON better_supabase.deals
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_field_history_deal();

CREATE TRIGGER bsb_pipeline_deal
  BEFORE INSERT OR UPDATE OF stage_id, pipeline_id, owner_user_id ON better_supabase.deals
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_pipeline_deal();

CREATE TRIGGER bsb_pipeline_status_deal
  AFTER INSERT OR UPDATE OF stage_id ON better_supabase.deals
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_pipeline_status_deal();

CREATE TRIGGER bsb_search_deal_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, identifier, note, archived_at ON better_supabase.deals
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('deal', 'id');

CREATE TRIGGER bsb_drive_node_moved
  AFTER UPDATE OF parent_id ON better_supabase.drive_nodes
  FOR EACH ROW
  WHEN ((old.parent_id IS DISTINCT FROM new.parent_id))
  EXECUTE FUNCTION better_supabase.drive_node_moved();

CREATE TRIGGER bsb_drive_node_path
  BEFORE INSERT OR UPDATE OF parent_id ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.drive_node_path();

CREATE TRIGGER bsb_drive_node_purged
  AFTER DELETE ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.drive_node_purged();

CREATE TRIGGER bsb_drive_node_purging
  BEFORE DELETE ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.drive_node_purging();

CREATE TRIGGER bsb_search_drive_node_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, deleted_at ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('drive_node', 'id');

CREATE TRIGGER bsb_employee_manager_guard
  BEFORE INSERT OR UPDATE OF manager_id ON better_supabase.employees
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_employee_manager_guard();

CREATE TRIGGER bsb_employee_user_mirror
  AFTER UPDATE OF user_id ON better_supabase.employees
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_employee_user_mirror();

CREATE TRIGGER bsb_search_employee_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, email, job_title ON better_supabase.employees
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('employee', 'id');

CREATE TRIGGER bsb_search_engagement_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, body, outcome ON better_supabase.engagements
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('engagement', 'id');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.inbox_conversations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.inboxes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.invitations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_invoice_lines_totals_delete
  AFTER DELETE ON better_supabase.invoice_lines REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bsb_invoice_lines_totals();

CREATE TRIGGER bsb_invoice_lines_totals_insert
  AFTER INSERT ON better_supabase.invoice_lines REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bsb_invoice_lines_totals();

CREATE TRIGGER bsb_invoice_lines_totals_update
  AFTER UPDATE ON better_supabase.invoice_lines REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bsb_invoice_lines_totals();

CREATE TRIGGER bsb_billable_time_release
  AFTER UPDATE OF status ON better_supabase.invoices
  FOR EACH ROW
  WHEN (((new.status = 'void'::text) AND (old.status <> 'void'::text)))
  EXECUTE FUNCTION better_supabase.billable_time_release();

CREATE TRIGGER bsb_ledger_entries_append_only
  BEFORE DELETE OR UPDATE ON better_supabase.ledger_entries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_append_only();

CREATE TRIGGER bsb_ledger_entries_apply
  AFTER INSERT ON better_supabase.ledger_entries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_apply_entry();

CREATE CONSTRAINT TRIGGER bsb_ledger_entries_balanced
  AFTER INSERT ON better_supabase.ledger_entries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_check_balanced();

CREATE TRIGGER bsb_ledger_transactions_append_only
  BEFORE DELETE OR UPDATE ON better_supabase.ledger_transactions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_append_only();

CREATE TRIGGER bsb_mail_changed
  AFTER INSERT OR UPDATE OF opened_at, clicked_at ON better_supabase.mail_messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.lead_mail_changed();

CREATE TRIGGER bsb_replied
  AFTER INSERT ON better_supabase.mail_messages
  FOR EACH ROW
  WHEN ((new.direction = 'inbound'::text))
  EXECUTE FUNCTION better_supabase.sequence_mail_replied();

CREATE TRIGGER bsb_mail_linked
  AFTER INSERT ON better_supabase.mail_thread_subjects
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.lead_mail_linked();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.message_deliveries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.message_templates
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_messages_moderation_guard
  BEFORE INSERT ON better_supabase.messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.messages_moderation_guard();

CREATE TRIGGER bsb_messaging_inbox_broadcast
  AFTER INSERT OR UPDATE ON better_supabase.messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.inbox_message_broadcast();

CREATE TRIGGER bsb_messaging_message_broadcast
  AFTER INSERT OR UPDATE ON better_supabase.messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.messaging_message_broadcast();

CREATE TRIGGER bsb_messaging_message_written
  AFTER INSERT OR UPDATE OF sent_at, deleted_at ON better_supabase.messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.messaging_message_written();

CREATE TRIGGER bsb_posts_replied
  AFTER INSERT OR UPDATE OF sent_at, deleted_at ON better_supabase.messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.posts_replied();

CREATE TRIGGER bsb_posts_reply_guard
  BEFORE INSERT ON better_supabase.messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.posts_reply_guard();

CREATE TRIGGER bsb_search_message_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, body, deleted_at ON better_supabase.messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('message', 'id');

CREATE TRIGGER bsb_posts_moderated
  AFTER UPDATE OF status, decided_at ON better_supabase.moderation_items
  FOR EACH ROW
  WHEN ((new.subject_type = 'post'::text))
  EXECUTE FUNCTION better_supabase.posts_moderated();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_notification_broadcast_update
  AFTER UPDATE OF read_at, dismissed_at, resolved_at ON better_supabase.notification_recipients
  FOR EACH ROW
  WHEN (((old.read_at IS DISTINCT FROM new.read_at) OR (old.dismissed_at IS DISTINCT FROM new.dismissed_at) OR (old.resolved_at IS DISTINCT FROM new.resolved_at)))
  EXECUTE FUNCTION better_supabase.broadcast_notification();

CREATE TRIGGER bsb_notification_broadcast
  AFTER INSERT ON better_supabase.notification_recipients
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.broadcast_notification();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.notification_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_order_line_preparations_broadcast
  AFTER INSERT OR UPDATE ON better_supabase.order_line_preparations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.order_line_preparations_changed();

CREATE TRIGGER bsb_record_organization_setting
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.organization_settings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.record_organization_setting();

CREATE TRIGGER bsb_person_changed
  AFTER INSERT OR UPDATE ON better_supabase.people
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.lead_person_changed();

CREATE TRIGGER bsb_search_person_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, email, title ON better_supabase.people
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('person', 'id');

CREATE TRIGGER bsb_record_platform_setting
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.platform_settings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.record_platform_setting();

CREATE TRIGGER bsb_posts_removed
  AFTER DELETE ON better_supabase.posts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.posts_removed();

CREATE TRIGGER bsb_search_post_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, body ON better_supabase.posts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('post', 'id');

CREATE TRIGGER bsb_approvals_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.approvals_subject_deleted('product_variant', 'id');

CREATE TRIGGER bsb_attachments_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachments_subject_deleted('product_variant', 'id');

CREATE TRIGGER bsb_comments_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.comments_subject_deleted('product_variant', 'id', 'tenant_id');

CREATE TRIGGER bsb_documents_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.documents_subject_deleted('product_variant', 'id');

CREATE TRIGGER bsb_notifications_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted('product_variant', 'id', 'tenant_id');

CREATE TRIGGER bsb_reactions_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_subject_deleted('product_variant', 'id');

CREATE TRIGGER bsb_relations_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.relations_subject_deleted('product_variant', 'id');

CREATE TRIGGER bsb_search_product_variant_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, sku, title, barcode ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('product_variant', 'id');

CREATE TRIGGER bsb_approvals_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.approvals_subject_deleted('product', 'id');

CREATE TRIGGER bsb_attachments_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachments_subject_deleted('product', 'id');

CREATE TRIGGER bsb_comments_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.comments_subject_deleted('product', 'id', 'tenant_id');

CREATE TRIGGER bsb_documents_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.documents_subject_deleted('product', 'id');

CREATE TRIGGER bsb_notifications_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted('product', 'id', 'tenant_id');

CREATE TRIGGER bsb_reactions_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_subject_deleted('product', 'id');

CREATE TRIGGER bsb_relations_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.relations_subject_deleted('product', 'id');

CREATE TRIGGER bsb_search_product_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, description, slug ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('product', 'id');

CREATE TRIGGER bsb_profile_guard
  BEFORE UPDATE ON better_supabase.profiles
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.guard_profile();

CREATE TRIGGER bsb_quote_lines_totals_delete
  AFTER DELETE ON better_supabase.quote_lines REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bsb_quote_lines_totals();

CREATE TRIGGER bsb_quote_lines_totals_insert
  AFTER INSERT ON better_supabase.quote_lines REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bsb_quote_lines_totals();

CREATE TRIGGER bsb_quote_lines_totals_update
  AFTER UPDATE ON better_supabase.quote_lines REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.bsb_quote_lines_totals();

CREATE TRIGGER bsb_reactions_changed
  AFTER INSERT OR DELETE ON better_supabase.reactions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_changed();

CREATE TRIGGER bsb_reactions_check
  BEFORE INSERT ON better_supabase.reactions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_check();

CREATE TRIGGER bsb_reactions_tally
  AFTER INSERT OR DELETE ON better_supabase.reactions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_tally();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.scheduled_inbox_messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_segment_changed
  AFTER INSERT OR DELETE ON better_supabase.segment_members
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.lead_segment_changed();

CREATE TRIGGER bsb_contracts_signature_settled
  AFTER UPDATE OF status ON better_supabase.signature_requests
  FOR EACH ROW
  WHEN (((old.status = 'pending'::text) AND (new.status <> 'pending'::text)))
  EXECUTE FUNCTION better_supabase.contract_signature_settled();

CREATE TRIGGER bsb_signing_key_vault
  AFTER DELETE ON better_supabase.signing_keys
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.drop_signing_key_vault_secret();

CREATE TRIGGER bsb_billable_time_guard
  BEFORE DELETE OR UPDATE ON better_supabase.time_entries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.billable_time_guard();

CREATE TRIGGER bsb_time_entry_guard
  BEFORE INSERT OR DELETE OR UPDATE ON better_supabase.time_entries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.time_entry_guard();

CREATE TRIGGER bsb_webhook_secret_vault
  AFTER DELETE ON better_supabase.webhook_endpoint_secrets
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.drop_webhook_vault_secret();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.webhook_endpoints
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_webhook_endpoint_reenable
  BEFORE UPDATE OF enabled ON better_supabase.webhook_endpoints
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reset_webhook_endpoint();

CREATE TRIGGER bsb_pipeline_status_work_item
  AFTER INSERT OR UPDATE OF stage_id ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_pipeline_status_work_item();

CREATE TRIGGER bsb_pipeline_work_item
  BEFORE INSERT OR UPDATE OF stage_id, pipeline_id ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_pipeline_work_item();

CREATE TRIGGER bsb_search_work_item_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, identifier, body, archived_at ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('work_item', 'id');

CREATE TRIGGER bsb_transition_work_item
  BEFORE INSERT OR UPDATE OF state ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_transition_work_item();

CREATE TRIGGER bsb_work_item_guard
  BEFORE INSERT OR UPDATE ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_work_item_guard();

CREATE TRIGGER bsb_workflow_runs_alert
  AFTER INSERT OR UPDATE OF status ON better_supabase.workflow_runs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.workflow_runs_alert();

CREATE TRIGGER bsb_workflow_runs_status
  AFTER INSERT OR UPDATE OF status ON better_supabase.workflow_runs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.workflow_runs_changed();

CREATE TRIGGER bsb_seal_fields
  BEFORE INSERT OR UPDATE OF organization_id, diagnosis, birth_date ON public.client_notes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.client_notes_seal();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON public.client_notes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER bsb_search_customer_index
  AFTER INSERT OR DELETE OR UPDATE OF id, organization_id, name, archived_at ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('customer', 'id');

CREATE CONSTRAINT TRIGGER bsb_organization_owner
  AFTER DELETE OR UPDATE OF ROLE, organization_id ON public.memberships DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ensure_organization_owner();

CREATE TRIGGER bsb_organization_role_guard
  BEFORE INSERT OR UPDATE ON public.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.guard_membership();

CREATE TRIGGER bsb_search_project_index
  AFTER INSERT OR DELETE OR UPDATE OF id, organization_id, name, deleted_at ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('project', 'id');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER bsb_versions_project_auto
  AFTER INSERT OR UPDATE OF name, budget_minor, currency ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.versions_capture('project', 'id', 'organization_id', 'name,budget_minor,currency', '', '');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON public.saved_views
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER bsb_emit_event
  AFTER INSERT OR DELETE OR UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.tasks_emit_event();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER bsb_workflow_sdk_runs_mirror
  AFTER INSERT OR UPDATE OF status, attributes, error ON workflow.workflow_runs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.workflow_sdk_mirror_run();

CREATE POLICY "bsb_drive_attachments_delete" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR DELETE
  TO "authenticated"
  USING ((better_supabase.drive_attachment_allowed(subject_type, subject_id, true) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_drive_attachments_insert" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((better_supabase.drive_attachment_allowed(subject_type, subject_id, true) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_drive_attachments_read" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR SELECT
  TO "authenticated"
  USING (better_supabase.drive_attachment_allowed(subject_type, subject_id, false));

CREATE POLICY "bsb_audit_read" ON "better_supabase"."audit_events"
  FOR SELECT
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.audit_read_tenants() AS audit_read_tenants)) OR ( SELECT better_supabase.audit_reads_all() AS audit_reads_all)));

CREATE POLICY "bsb_invitations_read" ON "better_supabase"."invitations"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.invitation_tenant_ids() AS invitation_tenant_ids)));

CREATE POLICY "bsb_notification_deliveries_read" ON "better_supabase"."notification_deliveries"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.notification_recipients r
  WHERE ((r.id = notification_deliveries.recipient_id) AND (r.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "bsb_notification_delivery_events_read" ON "better_supabase"."notification_delivery_events"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM (better_supabase.notification_deliveries d
     JOIN better_supabase.notification_recipients r ON ((r.id = d.recipient_id)))
  WHERE ((d.id = notification_delivery_events.delivery_id) AND (r.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "bsb_notification_events_read" ON "better_supabase"."notification_events"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.notification_recipients r
  WHERE ((r.event_id = notification_events.id) AND (r.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "bsb_notification_preferences_own_delete" ON "better_supabase"."notification_preferences"
  FOR DELETE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_notification_preferences_own_insert" ON "better_supabase"."notification_preferences"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with))) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_notification_preferences_own_read" ON "better_supabase"."notification_preferences"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bsb_notification_preferences_own_update" ON "better_supabase"."notification_preferences"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with))) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_notification_recipients_read" ON "better_supabase"."notification_recipients"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bsb_notification_recipients_update" ON "better_supabase"."notification_recipients"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_notification_subscriptions_own_delete" ON "better_supabase"."notification_subscriptions"
  FOR DELETE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_notification_subscriptions_own_insert" ON "better_supabase"."notification_subscriptions"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with))) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_notification_subscriptions_own_read" ON "better_supabase"."notification_subscriptions"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bsb_notification_subscriptions_own_update" ON "better_supabase"."notification_subscriptions"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with))) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_notification_suppressions_read" ON "better_supabase"."notification_suppressions"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bsb_profiles_read" ON "better_supabase"."profiles"
  FOR SELECT
  TO "authenticated"
  USING ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bsb_profiles_update" ON "better_supabase"."profiles"
  FOR UPDATE
  TO "authenticated"
  USING (((id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH CHECK (((id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_webhook_deliveries_read" ON "better_supabase"."webhook_deliveries"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.tenant_ids_with('webhooks.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_webhook_endpoints_delete" ON "better_supabase"."webhook_endpoints"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('webhooks.manage'::text) AS tenant_ids_with)) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bsb_webhook_endpoints_insert" ON "better_supabase"."webhook_endpoints"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('webhooks.manage'::text) AS tenant_ids_with)) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bsb_webhook_endpoints_read" ON "better_supabase"."webhook_endpoints"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.tenant_ids_with('webhooks.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_webhook_endpoints_update" ON "better_supabase"."webhook_endpoints"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('webhooks.manage'::text) AS tenant_ids_with)) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)))
  WITH
    CHECK
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('webhooks.manage'::text) AS tenant_ids_with)) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bsb_session_active" ON "public"."client_notes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."contacts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."customer_tags"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."customers"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."locations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."memberships"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."notes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."organizations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."plan_features"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."plans"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."projects"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."saved_views"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."subscriptions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."tags"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_session_active" ON "public"."tasks"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "bsb_ai_chat_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'ai-chat:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 9) ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'::text) AND better_supabase.ai_chat_can_read((substr(( SELECT realtime.topic() AS topic), 9))::uuid)));

CREATE POLICY "bsb_ai_chats_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) = ('ai-chats:'::text || (( SELECT auth.uid() AS uid))::text))));

CREATE POLICY "bsb_announcements_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) = 'announcements'::text)));

CREATE POLICY "bsb_documents_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = ANY (ARRAY['broadcast'::text, 'presence'::text])) AND better_supabase.document_topic_access(( SELECT realtime.topic() AS topic), false)));

CREATE POLICY "bsb_documents_send" ON "realtime"."messages"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((((extension = 'broadcast'::text) AND better_supabase.document_topic_access(( SELECT realtime.topic() AS topic), true)) OR ((extension = 'presence'::text) AND
    better_supabase.document_topic_access(( SELECT realtime.topic() AS topic), false))) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_inbox_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'inbox:org:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 11) IN ( SELECT (x.x)::text
    AS x
   FROM better_supabase.tenant_ids_with('inbox.read'::text) x(x)))));

CREATE POLICY "bsb_kitchen_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'kitchen:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 9) IN ( SELECT (t.t)::text AS
    t
   FROM better_supabase.tenant_ids_with('orders.read'::text) t(t)
UNION ALL
 SELECT (t.t)::text AS t
   FROM better_supabase.tenant_ids_with('orders.prepare'::text) t(t)))));

CREATE POLICY "bsb_messaging_broadcast" ON "realtime"."messages"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((extension = ANY (ARRAY['broadcast'::text, 'presence'::text])) AND (( SELECT realtime.topic() AS topic) ~~ ('messages:'::text || '%'::text)) AND
    better_supabase.conversation_topic_allowed(substr(( SELECT realtime.topic() AS topic), 10)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_messaging_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = ANY (ARRAY['broadcast'::text, 'presence'::text])) AND (( SELECT realtime.topic() AS topic) ~~ ('messages:'::text || '%'::text)) AND
    better_supabase.conversation_topic_allowed(substr(( SELECT realtime.topic() AS topic), 10))));

CREATE POLICY "bsb_notifications_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~ ((('^'::text || 'notifications:'::text) || (( SELECT auth.uid() AS uid))::text) || '$'::text))));

CREATE POLICY "bsb_reactions_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'reactions:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 11) IN ( SELECT (x.x)::text
    AS x
   FROM better_supabase.tenant_ids_with('reactions.read'::text) x(x)))));

CREATE POLICY "bsb_realtime_tables_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'bsb:t:%'::text) AND (NOT COALESCE(((( SELECT auth.jwt() AS jwt) ->>
    'is_anonymous'::text))::boolean,
    false)) AND
    ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = ''::text) OR ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 5) = ''::text) AND (split_part((
    SELECT realtime.topic() AS topic),
    ':'::text,
    4) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text), ''::text))) OR
    ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = 'u'::text) AND (split_part(( SELECT realtime.topic() AS topic), ':'::text, 5) = (( SELECT auth.uid() AS
    uid))::text)))));

CREATE POLICY "bsb_streams_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'stream:%'::text) AND (EXISTS ( SELECT 1
   FROM better_supabase.streams st
  WHERE ((st.id = substr(( SELECT realtime.topic() AS topic), 8)) AND (st.owner_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY "bsb_subject_presence_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'presence'::text) AND (( SELECT realtime.topic() AS topic) ~~ ('presence:'::text || '%'::text)) AND better_supabase.subject_presence_allowed(( SELECT
    realtime.topic() AS topic))));

CREATE POLICY "bsb_subject_presence_send" ON "realtime"."messages"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((extension = 'presence'::text) AND (( SELECT realtime.topic() AS topic) ~~ ('presence:'::text || '%'::text)) AND better_supabase.subject_presence_allowed(( SELECT
    realtime.topic() AS topic)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_workflow_runs_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (((( SELECT realtime.topic() AS topic) ~~ 'workflow-run:%'::text) AND (EXISTS ( SELECT 1
   FROM better_supabase.workflow_runs x
  WHERE ((x.id)::text = substr(( SELECT realtime.topic() AS topic), 14))))) OR
    ((( SELECT realtime.topic() AS topic) ~~ 'workflow-runs:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 15) IN ( SELECT (t.t)::text AS t
   FROM better_supabase.tenant_ids_with('workflow.read'::text) t(t)))))));

CREATE POLICY "bsb_ai_files_delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING
    (((bucket_id = 'ai-files'::text) AND better_supabase.ai_file_object_allowed(bucket_id, name, 'delete'::text) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bsb_ai_files_insert" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((bucket_id = 'ai-files'::text) AND better_supabase.ai_file_object_allowed(bucket_id, name, 'insert'::text) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bsb_ai_files_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (((bucket_id = 'ai-files'::text) AND better_supabase.ai_file_object_allowed(bucket_id, name, 'select'::text)));

CREATE POLICY "bsb_attachments_delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING
    (((bucket_id = 'attachments'::text) AND better_supabase.attachment_object_allowed(bucket_id, name, 'delete'::text) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bsb_attachments_insert" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((bucket_id = 'attachments'::text) AND better_supabase.attachment_object_allowed(bucket_id, name, 'insert'::text) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bsb_attachments_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING
    (((bucket_id = 'attachments'::text) AND better_supabase.attachment_object_allowed(bucket_id, name, 'select'::text) AND better_supabase.attachment_object_visible(bucket_id,
    name)));

CREATE POLICY "bsb_avatars_delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text)));

CREATE POLICY "bsb_avatars_insert" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text) AND (name ~ '^[^/]+/avatar-[^/]+\.[^/]+$'::text)));

CREATE POLICY "bsb_avatars_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text)));

CREATE POLICY "bsb_avatars_update" ON "storage"."objects"
  FOR UPDATE
  TO "authenticated"
  USING
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text)))
  WITH
    CHECK
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text) AND (name ~ '^[^/]+/avatar-[^/]+\.[^/]+$'::text)));

CREATE POLICY "bsb_customer_logos_delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->>
    'tenant_id'::text)))));

CREATE POLICY "bsb_customer_logos_insert" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)))
    AND (name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$'::text)));

CREATE POLICY "bsb_customer_logos_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->>
    'tenant_id'::text)))));

CREATE POLICY "bsb_customer_logos_update" ON "storage"."objects"
  FOR UPDATE
  TO "authenticated"
  USING
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->>
    'tenant_id'::text)))))
  WITH
    CHECK
    (((bucket_id = 'customer-logos'::text) AND ((name COLLATE "C") >= (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) ->
    'app_metadata'::text) ->> 'tenant_id'::text)) || '/'::text)) AND
    ((name COLLATE "C") < (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)) ||
    '0'::text)) AND
    (split_part(name, '/'::text, 1) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text)))
    AND (name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$'::text)));

CREATE POLICY "bsb_data_exports_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (((bucket_id = 'data-exports'::text) AND better_supabase.data_export_object_allowed(name)));

CREATE POLICY "bsb_drive_objects_delete" ON "storage"."objects"
  AS RESTRICTIVE
  FOR DELETE
  TO "authenticated"
  USING ((better_supabase.drive_object_allowed(bucket_id, name, 'delete'::text) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_drive_objects_insert" ON "storage"."objects"
  AS RESTRICTIVE
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((better_supabase.drive_object_allowed(bucket_id, name, 'insert'::text) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_drive_objects_read" ON "storage"."objects"
  AS RESTRICTIVE
  FOR SELECT
  TO "authenticated"
  USING (better_supabase.drive_object_allowed(bucket_id, name, 'select'::text));

CREATE POLICY "bsb_drive_objects_update" ON "storage"."objects"
  AS RESTRICTIVE
  FOR UPDATE
  TO "authenticated"
  USING ((better_supabase.drive_object_allowed(bucket_id, name, 'update'::text) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_inbox_files_read" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (better_supabase.inbox_file_allowed(bucket_id, name));

CREATE EVENT TRIGGER "bsb_audit_forget_dropped"
  ON sql_drop
  WHEN TAG IN ('DROP SCHEMA', 'DROP TABLE')
  EXECUTE FUNCTION "better_supabase"."audit_forget_dropped"();

COMMENT ON CONSTRAINT "bsb_attachments_bucket" ON "better_supabase"."attachments" IS 'better-supabase check 06ecf11d';

COMMENT ON CONSTRAINT "bsb_attachments_size" ON "better_supabase"."attachments" IS 'better-supabase check 65b1c9ef';

COMMENT ON CONSTRAINT "bsb_audit_op_check" ON "better_supabase"."audit_events" IS 'better-supabase check 50fe4698';

COMMENT ON CONSTRAINT "bsb_drive_grants_role" ON "better_supabase"."drive_grants" IS 'better-supabase check d20245e0';

COMMENT ON CONSTRAINT "bsb_field_definitions_type" ON "better_supabase"."field_definitions" IS 'better-supabase check 41e34c72';

REVOKE ALL ON FUNCTION "better_supabase"."bsb_application_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_booking_engagement"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_deal_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_deal_lines_totals"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_employee_manager_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_employee_user_mirror"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_field_history_company"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_field_history_deal"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_invoice_lines_totals"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_quote_lines_totals"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_work_item_guard"() FROM PUBLIC;
