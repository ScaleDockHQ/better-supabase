SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."purchase_orders"
  DROP CONSTRAINT "purchase_orders_location_id_fkey";

ALTER TABLE "better_supabase"."stock_levels"
  DROP CONSTRAINT "stock_levels_location_id_fkey";

ALTER TABLE "better_supabase"."stock_reservations"
  DROP CONSTRAINT "stock_reservations_location_id_fkey";

ALTER TABLE "better_supabase"."stock_transfers"
  DROP CONSTRAINT "stock_transfers_from_location_id_fkey";

ALTER TABLE "better_supabase"."stock_transfers"
  DROP CONSTRAINT "stock_transfers_to_location_id_fkey";

ALTER TABLE "better_supabase"."work_order_parts"
  DROP CONSTRAINT "work_order_parts_location_fkey";

CREATE TABLE "better_supabase"."inventory_locations" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "code"       text                     NOT NULL,
  "name"       text                     NOT NULL,
  "kind"       text                     NOT NULL DEFAULT 'warehouse'::text,
  "active"     boolean                  NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inventory_locations_kind_check" CHECK ((kind = ANY (ARRAY['warehouse'::text, 'store'::text, 'virtual'::text]))),
  CONSTRAINT "inventory_locations_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "inventory_locations_pkey" PRIMARY KEY (id),
  CONSTRAINT "inventory_locations_tenant_id_code_key" UNIQUE (tenant_id, code)
);

ALTER TABLE "better_supabase"."inventory_locations"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION better_supabase.adjust_stock (
  variant  uuid,
  location uuid,
  quantity integer,
  reason   text,
  note     text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_on_hand integer;
  v_available integer;
begin
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = adjust_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = adjust_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if adjust_stock.quantity is null or adjust_stock.quantity = 0 then
    raise exception 'the quantity must be a non-zero whole number' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if adjust_stock.reason is null or adjust_stock.reason not in ('adjustment', 'damage', 'loss', 'return', 'receipt') then
    raise exception 'the reason must be one of adjustment, damage, loss, return, receipt' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_adjust"(uuid, uuid, integer, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::integer, $4::text)', v_hook::oid::regproc)
        using adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason;
    end if;
  end;
  v_movement := "better_supabase"."move_stock"(v_tenant, adjust_stock.variant, adjust_stock.location, adjust_stock.quantity, adjust_stock.reason, null, null, adjust_stock.note);
  select x."on_hand", x."available" into v_on_hand, v_available from "better_supabase"."stock_levels" x
  where x."variant_id" = adjust_stock.variant and x."location_id" = adjust_stock.location;
  perform "better_supabase".emit_event('stock.adjusted', jsonb_build_object('organizationId', v_tenant, 'id', v_movement, 'variantId', adjust_stock.variant, 'locationId', adjust_stock.location, 'quantity', adjust_stock.quantity::text, 'reason', adjust_stock.reason, 'available', v_available::text), 'stock-movements/' || v_movement::text, (v_tenant)::text, null, 'better-supabase/inventory');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_adjust"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_movement;
    end if;
  end;
  return jsonb_build_object('movementId', v_movement, 'onHand', v_on_hand, 'available', v_available);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.count_stock (
  variant  uuid,
  location uuid,
  counted  integer,
  note     text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_active boolean;
  v_movement uuid;
  v_delta integer;
  v_available integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = count_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = count_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if count_stock.counted is null or count_stock.counted < 0 then
    raise exception 'the counted quantity must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, count_stock.variant, count_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location for update;
  select count_stock.counted - x."on_hand" into v_delta from "better_supabase"."stock_levels" x
  where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
  if v_delta <> 0 then
    v_movement := "better_supabase"."move_stock"(v_tenant, count_stock.variant, count_stock.location, v_delta, 'count', null, null, count_stock.note);
    select x."available" into v_available from "better_supabase"."stock_levels" x
    where x."variant_id" = count_stock.variant and x."location_id" = count_stock.location;
    perform "better_supabase".emit_event('stock.adjusted', jsonb_build_object('organizationId', v_tenant, 'id', v_movement, 'variantId', count_stock.variant, 'locationId', count_stock.location, 'quantity', v_delta::text, 'reason', 'count', 'available', v_available::text), 'stock-movements/' || v_movement::text, (v_tenant)::text, null, 'better-supabase/inventory');
  end if;
  return jsonb_build_object('movementId', v_movement, 'delta', v_delta, 'onHand', count_stock.counted);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_transfer (
  tenant        uuid,
  from_location uuid,
  to_location   uuid,
  lines         jsonb,
  note          text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_transfer.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if create_transfer.from_location is not distinct from create_transfer.to_location then
    raise exception 'a transfer needs two different locations' using errcode = '22023', hint = 'INVENTORY_TRANSFER_SAME_LOCATION';
  end if;
  if (select count(*) from "better_supabase"."inventory_locations" x where x."id" in (create_transfer.from_location, create_transfer.to_location) and x."tenant_id" = create_transfer.tenant) <> 2 then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if jsonb_typeof(create_transfer.lines) is distinct from 'array' or jsonb_array_length(create_transfer.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(create_transfer.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or coalesce(e ->> 'quantity', '') !~ '^[1-9][0-9]{0,8}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(create_transfer.lines) e) <> jsonb_array_length(create_transfer.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive whole quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(create_transfer.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = create_transfer.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  insert into "better_supabase"."stock_transfers" ("tenant_id", "from_location_id", "to_location_id", "note")
  values (create_transfer.tenant, create_transfer.from_location, create_transfer.to_location, create_transfer.note)
  returning "id" into v_id;
  insert into "better_supabase"."stock_transfer_lines" ("tenant_id", "transfer_id", "variant_id", "quantity")
  select create_transfer.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::integer
  from jsonb_array_elements(create_transfer.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_tables()
  RETURNS TABLE (
    subject  text,
    name     text,
    tbl      text,
    col      text,
    purge    boolean,
    omit     text[],
    exported boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* 'token|secret|_hash|password|api_key|license_key'
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'public.memberships', '"public"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.contacts', '"better_supabase"."contacts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_document_versions', '"better_supabase"."ai_document_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', false, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.courses', '"better_supabase"."courses"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.sequences', '"better_supabase"."sequences"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'enrolled_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'organization_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contacts', '"better_supabase"."contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contact_identities', '"better_supabase"."contact_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.price_lists', '"better_supabase"."price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.categories', '"better_supabase"."categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', false, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_transactions', '"better_supabase"."ledger_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_entries', '"better_supabase"."ledger_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_balances', '"better_supabase"."ledger_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_holds', '"better_supabase"."ledger_holds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipping_rates', '"better_supabase"."shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillments', '"better_supabase"."fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillment_lines', '"better_supabase"."fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_answer_keys', '"better_supabase"."form_answer_keys"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_inbox_contacts', '"better_supabase"."person_inbox_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagements', '"better_supabase"."engagements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_charges', '"better_supabase"."lease_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_categories', '"better_supabase"."expense_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_lines', '"better_supabase"."expense_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_funds', '"better_supabase"."donation_funds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pledges', '"better_supabase"."pledges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_receipts', '"better_supabase"."donation_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donations', '"better_supabase"."donations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_route_stops', '"better_supabase"."dispatch_route_stops"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipments', '"better_supabase"."shipments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_packages', '"better_supabase"."shipment_packages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_tracking_events', '"better_supabase"."shipment_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policies', '"better_supabase"."policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_components', '"better_supabase"."status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_component_history', '"better_supabase"."status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_pages', '"better_supabase"."status_pages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.courses', '"better_supabase"."courses"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_modules', '"better_supabase"."course_modules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lessons', '"better_supabase"."course_lessons"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_summaries', '"better_supabase"."thread_summaries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.mail_threads', '"better_supabase"."mail_threads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_messages', '"better_supabase"."mail_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracked_links', '"better_supabase"."mail_tracked_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracking_events', '"better_supabase"."mail_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segments', '"better_supabase"."segments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segment_members', '"better_supabase"."segment_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queues', '"better_supabase"."assignment_queues"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrichments', '"better_supabase"."enrichments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshots', '"better_supabase"."forecast_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshot_deals', '"better_supabase"."forecast_snapshot_deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_changes', '"better_supabase"."field_changes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequences', '"better_supabase"."sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_location (
  location uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_entries" y on y."account_id" = x."id"
      where x."tenant_id" = v_tenant and x."managed_by" = 'inventory' and x."kind" = 'stock'
        and x."metadata" ->> 'locationId' = delete_location.location::text)
    or exists (select 1 from "better_supabase"."stock_reservations" x where x."location_id" = delete_location.location and x."status" = 'active') then
    raise exception 'the location has stock history; deactivate it instead' using errcode = '23503', hint = 'INVENTORY_LOCATION_IN_USE';
  end if;
  delete from "better_supabase"."inventory_locations" x where x."id" = delete_location.location;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.place_order (
  cart           uuid,
  tax            jsonb  DEFAULT NULL::jsonb,
  expected_total bigint DEFAULT NULL::bigint,
  location       uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_cart record;
  v_order record;
  v_line record;
  v_priced jsonb;
  v_tax bigint := 0;
  v_line_tax bigint;
  v_invalid boolean;
  v_inclusive boolean := false;
  v_total bigint;
  v_seq bigint;
  v_number text;
  v_id uuid;
  v_location uuid;
  v_reservation jsonb;
  v_claims text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status, x."currency" as currency,
    x."email" as email, x."shipping_address" as shipping_address, x."billing_address" as billing_address
  into v_cart from "better_supabase"."carts" x where x."id" = place_order.cart for update;
  if not found then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status = 'converted' then
    select x."id" into v_id from "better_supabase"."orders" x where x."cart_id" = place_order.cart;
    if v_id is not null then
      return "better_supabase"."order_json"(v_id) || jsonb_build_object('created', false);
    end if;
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_order_place"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using place_order.cart;
    end if;
  end;
  v_priced := "better_supabase"."cart_totals"(place_order.cart);
  if jsonb_array_length(v_priced -> 'lines') = 0 then
    raise exception 'the cart has no lines to order' using errcode = '55000', hint = 'ORDERS_CART_EMPTY';
  end if;
  if jsonb_array_length(v_priced -> 'problems') > 0 then
    raise exception 'the cart can''t be ordered: %', v_priced -> 'problems' using errcode = '55000', hint = 'ORDERS_CART_INVALID';
  end if;
  if place_order.expected_total is not null and (v_priced ->> 'total')::bigint <> place_order.expected_total then
    raise exception 'the cart''s total changed; price it and quote tax again' using errcode = '40001', hint = 'ORDERS_PRICE_CHANGED';
  end if;
  if place_order.tax is not null then
    if jsonb_typeof(place_order.tax) <> 'object' or (case when (place_order.tax ->> 'totalTax') ~ '^[0-9]{1,18}$' then (place_order.tax ->> 'totalTax')::bigint end) is null
      or coalesce(place_order.tax ->> 'currency', v_cart.currency) <> v_cart.currency then
      raise exception 'tax is a quote in the cart''s currency with a totalTax of zero or more' using errcode = '22023', hint = 'ORDERS_TAX_INVALID';
    end if;
    v_tax := (case when (place_order.tax ->> 'totalTax') ~ '^[0-9]{1,18}$' then (place_order.tax ->> 'totalTax')::bigint end);
    v_inclusive := coalesce((place_order.tax ->> 'inclusive')::boolean, false);
    select coalesce(sum((case when (e ->> 'tax') ~ '^[0-9]{1,18}$' then (e ->> 'tax')::bigint end)), 0), coalesce(bool_or((case when (e ->> 'tax') ~ '^[0-9]{1,18}$' then (e ->> 'tax')::bigint end) is null), false)
    into v_line_tax, v_invalid
    from jsonb_array_elements(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) e;
    if v_invalid or (jsonb_array_length(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) > 0 and v_line_tax <> v_tax) then
      raise exception 'the tax lines don''t add up to totalTax' using errcode = '22023', hint = 'ORDERS_TAX_INVALID';
    end if;
  end if;
  v_total := (v_priced ->> 'total')::bigint + case when v_inclusive then 0 else v_tax end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_cart.tenant::text || ':commerce:order', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."orders" x where x."tenant_id" = v_cart.tenant;
  v_number := v_seq::text;
  insert into "better_supabase"."orders" ("tenant_id", "number", "sequence", "cart_id", "customer_id", "email", "currency",
    "subtotal", "discount_total", "shipping_total", "tax_total", "total", "tax_inclusive",
    "shipping_address", "billing_address", "shipping", "promotions", "tax")
  values (v_cart.tenant, v_number, v_seq, place_order.cart, v_cart.owner, v_cart.email, v_cart.currency,
    (v_priced ->> 'subtotal')::bigint, (v_priced ->> 'discountTotal')::bigint, (v_priced ->> 'shippingTotal')::bigint,
    v_tax, v_total, v_inclusive, v_cart.shipping_address, v_cart.billing_address, v_priced -> 'shipping',
    v_priced -> 'promotions', place_order.tax)
  returning "id" into v_id;
  insert into "better_supabase"."order_lines" ("tenant_id", "order_id", "position", "variant_id", "product_id", "sku", "title",
    "quantity", "unit_amount", "subtotal", "discount", "tax", "total", "requires_shipping")
  select v_cart.tenant, v_id, e.n, (e.l ->> 'variantId')::uuid, (e.l ->> 'productId')::uuid, e.l ->> 'sku', e.l ->> 'title',
    (e.l ->> 'quantity')::integer, (e.l ->> 'unitAmount')::bigint, (e.l ->> 'subtotal')::bigint, (e.l ->> 'discount')::bigint,
    coalesce((select (case when (t ->> 'tax') ~ '^[0-9]{1,18}$' then (t ->> 'tax')::bigint end) from jsonb_array_elements(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) t
      where t ->> 'lineId' = e.l ->> 'id' limit 1), 0),
    (e.l ->> 'total')::bigint, (e.l ->> 'requiresShipping')::boolean
  from jsonb_array_elements(v_priced -> 'lines') with ordinality as e(l, n);
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_id;
  for v_line in
    select x."id" as id, x."variant_id" as variant, x."quantity" as quantity,
      cv."track_inventory" as tracked, cv."allow_backorder" as backorder
    from "better_supabase"."order_lines" x join "better_supabase"."product_variants" cv on cv."id" = x."variant_id"
    where x."order_id" = v_order.id
    order by x."position"
  loop
    continue when not v_line.tracked;
    select loc."id" into v_location
    from "better_supabase"."inventory_locations" loc
    left join "better_supabase"."stock_levels" s on s."location_id" = loc."id" and s."variant_id" = v_line.variant
    where loc."tenant_id" = v_cart.tenant and loc."active" and (place_order.location is null or loc."id" = place_order.location)
    order by (coalesce(s."available", 0) >= v_line.quantity) desc, coalesce(s."available", 0) desc, loc."code"
    limit 1;
    if v_location is null then
      if not v_line.backorder then
        raise exception 'a line is out of stock' using errcode = '23514', hint = 'ORDERS_OUT_OF_STOCK';
      end if;
      update "better_supabase"."order_lines" x set "backordered" = true where x."id" = v_line.id;
      continue;
    end if;
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_reservation := "better_supabase"."reserve_stock"(v_line.variant, v_location, v_line.quantity, 'order', v_order.id::text, now() + interval '30 minutes');
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    update "better_supabase"."order_lines" x set "location_id" = v_location, "reservation_id" = (v_reservation ->> 'id')::uuid,
      "backordered" = (v_reservation ->> 'available')::integer < 0
    where x."id" = v_line.id;
  end loop;
  perform "better_supabase"."redeem_promotions"(v_order.id, v_priced -> 'promotions');
  update "better_supabase"."carts" x set "status" = 'converted', "converted_at" = now(), "updated_at" = now()
  where x."id" = place_order.cart;
  perform "better_supabase".emit_event('order.placed', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer, 'currency', v_order.currency, 'subtotal', v_priced ->> 'subtotal', 'discountTotal', v_priced ->> 'discountTotal', 'shippingTotal', v_priced ->> 'shippingTotal', 'taxTotal', v_tax::text, 'total', v_order.total::text, 'units', (select coalesce(sum(l."quantity"), 0)::text from "better_supabase"."order_lines" l where l."order_id" = v_order.id)), 'orders/' || v_order.id::text, (v_order.tenant)::text, null, 'better-supabase/orders');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_order_place"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_order.id;
    end if;
  end;
  return "better_supabase"."order_json"(v_order.id) || jsonb_build_object('created', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_work_order_part (
  work_order_id uuid,
  name          text,
  quantity      numeric DEFAULT 1,
  unit          text    DEFAULT NULL::text,
  asset_id      uuid    DEFAULT NULL::uuid,
  variant_id    uuid    DEFAULT NULL::uuid,
  location_id   uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_order "better_supabase"."work_orders"%rowtype;
  v_row "better_supabase"."work_order_parts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_order from "better_supabase"."work_orders" x where x."id" = record_work_order_part.work_order_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_order."tenant_id", 'dispatch.manage'), false)) or (v_order."technician_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_order."tenant_id", 'dispatch.work'), false))) then
    raise exception 'work order not found' using errcode = 'P0002', hint = 'DISPATCH_NOT_FOUND';
  end if;
  if v_order."status" = 'cancelled' then
    raise exception 'a cancelled work order takes no parts' using errcode = '55000', hint = 'DISPATCH_STATUS_INVALID';
  end if;
  if record_work_order_part.asset_id is not null and not exists (
    select 1 from "better_supabase"."assets" a
    where a."id" = record_work_order_part.asset_id and a."tenant_id" = v_order."tenant_id"
  ) then
    raise exception 'the asset does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_ASSET_NOT_FOUND';
  end if;
  if record_work_order_part.variant_id is not null and not exists (
    select 1 from "better_supabase"."product_variants" v
    where v."id" = record_work_order_part.variant_id and v."tenant_id" = v_order."tenant_id"
  ) then
    raise exception 'the product variant does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_VARIANT_NOT_FOUND';
  end if;
  if record_work_order_part.location_id is not null and not exists (
    select 1 from "better_supabase"."inventory_locations" il
    where il."id" = record_work_order_part.location_id and il."tenant_id" = v_order."tenant_id"
  ) then
    raise exception 'the inventory location does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_INVENTORY_LOCATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."work_order_parts" ("tenant_id", "work_order_id", "name", "quantity", "unit", "asset_id", "variant_id", "location_id", "recorded_by")
    values (v_order."tenant_id", v_order."id", btrim(record_work_order_part.name), coalesce(record_work_order_part.quantity, 1),
      record_work_order_part.unit, record_work_order_part.asset_id, record_work_order_part.variant_id, record_work_order_part.location_id, auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or numeric_value_out_of_range then
    raise exception 'a part needs a name of 1 to 200 characters and a positive quantity' using errcode = '22023', hint = 'DISPATCH_PART_INVALID';
  end;
  perform "better_supabase".emit_event('work_order.part_used', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."work_order_id", 'partId', v_row."id", 'assetId', v_row."asset_id", 'variantId', v_row."variant_id", 'quantity', v_row."quantity"::text), 'work-orders/' || v_row."work_order_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'workOrderId', v_row."work_order_id", 'name', v_row."name", 'quantity', v_row."quantity"::text, 'unit', v_row."unit", 'assetId', v_row."asset_id", 'variantId', v_row."variant_id", 'locationId', v_row."location_id", 'recordedBy', v_row."recorded_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reserve_stock (
  variant        uuid,
  location       uuid,
  quantity       integer,
  reference_type text,
  reference_id   text,
  expires_at     timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_active boolean;
  v_id uuid;
  v_before integer;
  v_after integer;
  v_point integer;
  v_expires timestamptz := coalesce(reserve_stock.expires_at, now() + interval '15 minutes');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = reserve_stock.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not v_active then
    raise exception 'the location is inactive' using errcode = '55000', hint = 'INVENTORY_LOCATION_INACTIVE';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if reserve_stock.quantity is null or reserve_stock.quantity <= 0 then
    raise exception 'the quantity must be a positive whole number' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if v_expires <= now() then
    raise exception 'the reservation must expire in the future' using errcode = '22023', hint = 'INVENTORY_EXPIRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_stock_reserve"(uuid, uuid, integer, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::integer, $4::text, $5::text)', v_hook::oid::regproc)
        using reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id;
    end if;
  end;
  insert into "better_supabase"."stock_levels" ("tenant_id", "variant_id", "location_id")
  values (v_tenant, reserve_stock.variant, reserve_stock.location)
  on conflict ("variant_id", "location_id") do nothing;
  perform 1 from "better_supabase"."stock_levels" x where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location for update;
  with expired as (
    update "better_supabase"."stock_reservations" x set "status" = 'expired', "updated_at" = now()
    where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
      and x."status" = 'active' and x."expires_at" <= now()
    returning x."quantity" as quantity
  )
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - (select coalesce(sum(e.quantity), 0)::integer from expired e), 0)
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  select x."available", x."reorder_point" into v_before, v_point from "better_supabase"."stock_levels" x
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location;
  if v_before < reserve_stock.quantity and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = reserve_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  insert into "better_supabase"."stock_reservations" ("tenant_id", "variant_id", "location_id", "quantity", "reference_type", "reference_id", "expires_at")
  values (v_tenant, reserve_stock.variant, reserve_stock.location, reserve_stock.quantity, reserve_stock.reference_type, reserve_stock.reference_id, v_expires)
  returning "id" into v_id;
  update "better_supabase"."stock_levels" x set "reserved" = x."reserved" + reserve_stock.quantity, "updated_at" = now()
  where x."variant_id" = reserve_stock.variant and x."location_id" = reserve_stock.location
  returning x."available" into v_after;
  if v_point is not null and v_before > v_point and v_after <= v_point then
    perform "better_supabase".emit_event('stock.reorder_point_reached', jsonb_build_object('organizationId', v_tenant, 'subjectType', 'product_variant', 'subjectId', reserve_stock.variant::text, 'variantId', reserve_stock.variant, 'locationId', reserve_stock.location, 'available', v_after::text, 'reorderPoint', v_point::text), 'stock-levels/' || reserve_stock.variant::text || '/' || reserve_stock.location::text, (v_tenant)::text, null, 'better-supabase/inventory');
  end if;
  perform "better_supabase".emit_event('reservation.created', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'variantId', reserve_stock.variant, 'locationId', reserve_stock.location, 'quantity', reserve_stock.quantity::text), 'stock-reservations/' || v_id::text, (v_tenant)::text, null, 'better-supabase/inventory');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_stock_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'expiresAt', v_expires, 'available', v_after);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_location (
  tenant   uuid,
  location uuid,
  code     text,
  name     text,
  kind     text,
  fields   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_location.location;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_location.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if save_location.code is null or save_location.code !~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$' then
    raise exception 'the code must be 1 to 40 letters, digits, dots, dashes or underscores' using errcode = '22023', hint = 'INVENTORY_LOCATION_CODE_INVALID';
  end if;
  if coalesce(save_location.kind, 'warehouse') not in ('warehouse', 'store', 'virtual') then
    raise exception 'the kind must be warehouse, store or virtual' using errcode = '22023', hint = 'INVENTORY_LOCATION_KIND_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."inventory_locations" ("tenant_id", "code", "name", "kind")
      values (save_location.tenant, save_location.code, save_location.name, coalesce(save_location.kind, 'warehouse'))
      returning "id", "active" into v_id, v_active;
    else
      update "better_supabase"."inventory_locations" x set "code" = save_location.code, "name" = save_location.name,
        "kind" = coalesce(save_location.kind, x."kind"), "updated_at" = now()
      where x."id" = save_location.location and x."tenant_id" = save_location.tenant
      returning x."active" into v_active;
      if not found then
        raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another location has this code' using errcode = '23505', hint = 'INVENTORY_LOCATION_CODE_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'code', save_location.code, 'active', v_active);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_purchase_order (
  tenant         uuid,
  purchase_order uuid,
  location       uuid,
  supplier_type  text,
  supplier_id    text,
  currency       text,
  expected_at    timestamp with time zone,
  lines          jsonb,
  note           text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_purchase_order.purchase_order;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_purchase_order.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = save_purchase_order.location and x."tenant_id" = save_purchase_order.tenant) then
    raise exception 'location not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if (save_purchase_order.supplier_type is null) <> (save_purchase_order.supplier_id is null) then
    raise exception 'supplier_type and supplier_id go together' using errcode = '22023', hint = 'INVENTORY_SUPPLIER_INVALID';
  end if;
  if save_purchase_order.currency is null or "better_supabase"."currency_minor_units"(save_purchase_order.currency) is null then
    raise exception 'the currency must be an ISO 4217 code' using errcode = '22023', hint = 'INVENTORY_CURRENCY_INVALID';
  end if;
  if jsonb_typeof(save_purchase_order.lines) is distinct from 'array' or jsonb_array_length(save_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(save_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'variantId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or coalesce(e ->> 'quantity', '') !~ '^[1-9][0-9]{0,8}$'
        or coalesce(e ->> 'unitCost', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'variantId') from jsonb_array_elements(save_purchase_order.lines) e) <> jsonb_array_length(save_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique variantId and a positive whole quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_purchase_order.lines) e
    where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = save_purchase_order.tenant)
  ) then
    raise exception 'a line names a variant outside this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if v_id is null then
    insert into "better_supabase"."purchase_orders" ("tenant_id", "location_id", "supplier_type", "supplier_id", "currency", "expected_at", "note")
    values (save_purchase_order.tenant, save_purchase_order.location, save_purchase_order.supplier_type, save_purchase_order.supplier_id,
      save_purchase_order.currency, save_purchase_order.expected_at, save_purchase_order.note)
    returning "id" into v_id;
  else
    perform 1 from "better_supabase"."purchase_orders" x where x."id" = v_id and x."tenant_id" = save_purchase_order.tenant for update;
    if not found then
      raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
    end if;
    update "better_supabase"."purchase_orders" x set "location_id" = save_purchase_order.location, "supplier_type" = save_purchase_order.supplier_type,
      "supplier_id" = save_purchase_order.supplier_id, "currency" = save_purchase_order.currency,
      "expected_at" = save_purchase_order.expected_at, "note" = save_purchase_order.note, "updated_at" = now()
    where x."id" = v_id and x."status" = 'draft';
    if not found then
      raise exception 'only a draft purchase order can change' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_LOCKED';
    end if;
    delete from "better_supabase"."purchase_order_lines" x where x."purchase_order_id" = v_id;
  end if;
  insert into "better_supabase"."purchase_order_lines" ("tenant_id", "purchase_order_id", "variant_id", "quantity_ordered", "unit_cost")
  select save_purchase_order.tenant, v_id, (e ->> 'variantId')::uuid, (e ->> 'quantity')::integer, (e ->> 'unitCost')::bigint
  from jsonb_array_elements(save_purchase_order.lines) e;
  return jsonb_build_object('id', v_id, 'status', 'draft');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_location_active (
  location uuid,
  active   boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_location_active.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  update "better_supabase"."inventory_locations" x set "active" = coalesce(set_location_active.active, true), "updated_at" = now()
  where x."id" = set_location_active.location;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_reorder_point (
  variant       uuid,
  location      uuid,
  reorder_point integer
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_reorder_point.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = set_reorder_point.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if set_reorder_point.reorder_point < 0 then
    raise exception 'the reorder point must be zero or more' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "reorder_point")
  values (v_tenant, set_reorder_point.variant, set_reorder_point.location, set_reorder_point.reorder_point)
  on conflict ("variant_id", "location_id") do update
    set "reorder_point" = excluded."reorder_point", "updated_at" = now();
  return true;
end;
$function$;

ALTER TABLE "better_supabase"."purchase_orders"
  ADD CONSTRAINT "purchase_orders_location_id_fkey" FOREIGN KEY (location_id) REFERENCES better_supabase.inventory_locations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."stock_levels"
  ADD CONSTRAINT "stock_levels_location_id_fkey" FOREIGN KEY (location_id) REFERENCES better_supabase.inventory_locations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."stock_reservations"
  ADD CONSTRAINT "stock_reservations_location_id_fkey" FOREIGN KEY (location_id) REFERENCES better_supabase.inventory_locations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."stock_transfers"
  ADD CONSTRAINT "stock_transfers_from_location_id_fkey" FOREIGN KEY (from_location_id) REFERENCES better_supabase.inventory_locations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."stock_transfers"
  ADD CONSTRAINT "stock_transfers_to_location_id_fkey" FOREIGN KEY (to_location_id) REFERENCES better_supabase.inventory_locations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."work_order_parts"
  ADD CONSTRAINT "work_order_parts_location_fkey" FOREIGN KEY (location_id) REFERENCES better_supabase.inventory_locations(id) ON DELETE SET NULL;

CREATE POLICY "inventory_locations_read" ON "better_supabase"."inventory_locations"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with)));

GRANT SELECT ON TABLE "better_supabase"."inventory_locations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."inventory_locations" TO "service_role";
