SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.activate_bom (
  bom_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."boms";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."boms" x where x."id" = activate_bom.bom_id for update;
  if not found then
    raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'MANUFACTURING_BOM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.manage'), false))) then
    raise exception 'not allowed to activate bills of materials' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_row."status" = 'active' then
    return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status", 'quantity', v_row."quantity"::text, 'note', v_row."note", 'activatedAt', v_row."activated_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'variantId', y."variant_id", 'quantity', y."quantity"::text,
      'scrapBps', y."scrap_bps", 'operationId', y."operation_id", 'position', y."position") order by y."position", y."id")
      from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"), '[]'::jsonb),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'sequence', y."sequence", 'workCenterId', y."work_center_id",
      'title', y."title", 'setupMinutes', y."setup_minutes"::text, 'runMinutesPerUnit', y."run_minutes_per_unit"::text,
      'instructionsNodeId', y."instructions_node_id", 'inspectionTemplate', y."inspection_template") order by y."sequence")
      from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id"), '[]'::jsonb)));
  end if;
  if exists (select 1 from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"
    and "better_supabase"."bom_reaches"(y."variant_id", v_row."variant_id")) then
    raise exception 'a component is made from the variant itself' using errcode = '22023', hint = 'MANUFACTURING_BOM_CYCLE';
  end if;
  update "better_supabase"."boms" x set "status" = 'archived', "updated_at" = now()
  where x."variant_id" = v_row."variant_id" and x."status" = 'active';
  update "better_supabase"."boms" x set "status" = 'active', "activated_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('bom.activated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status"), 'boms/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/manufacturing');
  perform better_supabase.audit_event(
    event_type => 'bom.activated',
    category => 'data',
    target_type => 'bom',
    record_id => v_row."id"::text,
    target_label => 'v' || v_row."version"::text,
    summary => 'bill of materials activated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status")
  );
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status", 'quantity', v_row."quantity"::text, 'note', v_row."note", 'activatedAt', v_row."activated_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'variantId', y."variant_id", 'quantity', y."quantity"::text,
      'scrapBps', y."scrap_bps", 'operationId', y."operation_id", 'position', y."position") order by y."position", y."id")
      from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"), '[]'::jsonb),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'sequence', y."sequence", 'workCenterId', y."work_center_id",
      'title', y."title", 'setupMinutes', y."setup_minutes"::text, 'runMinutesPerUnit', y."run_minutes_per_unit"::text,
      'instructionsNodeId', y."instructions_node_id", 'inspectionTemplate', y."inspection_template") order by y."sequence")
      from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id"), '[]'::jsonb)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_eval_items (
  dataset uuid,
  items   jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_count integer;
begin
  if not exists (select 1 from "better_supabase"."eval_datasets" x where x."id" = add_eval_items.dataset) then
    raise exception 'No eval dataset %', add_eval_items.dataset using errcode = 'P0002', hint = 'AI_EVAL_DATASET_NOT_FOUND';
  end if;
  if jsonb_typeof(add_eval_items.items) is distinct from 'array' then
    raise exception 'items must be a JSON array' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(add_eval_items.items) e where jsonb_typeof(e.value) <> 'object' or not (e.value ? 'input')) then
    raise exception 'every item needs an input' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if (select count(*) from "better_supabase"."eval_items" x where x."dataset_id" = add_eval_items.dataset) + jsonb_array_length(add_eval_items.items) > 5000 then
    raise exception 'A dataset holds at most 5000 items' using errcode = '54000', hint = 'AI_EVAL_DATASET_FULL';
  end if;
  insert into "better_supabase"."eval_items" ("dataset_id", "input", "expected", "metadata")
  select add_eval_items.dataset, e.value -> 'input', e.value -> 'expected', coalesce(e.value -> 'metadata', '{}'::jsonb)
  from jsonb_array_elements(add_eval_items.items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_eval_items_from_feedback (
  dataset  uuid,
  rating   integer                  DEFAULT '-1'::integer,
  since    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows integer                  DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_dataset "better_supabase"."eval_datasets"%rowtype;
  v_count integer;
begin
  select x.* into v_dataset from "better_supabase"."eval_datasets" x where x."id" = add_eval_items_from_feedback.dataset;
  if not found then
    raise exception 'No eval dataset %', add_eval_items_from_feedback.dataset using errcode = 'P0002', hint = 'AI_EVAL_DATASET_NOT_FOUND';
  end if;
  if add_eval_items_from_feedback.rating not in (-1, 1) then
    raise exception 'rating must be 1 or -1' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  with picked as materialized (
    select fb."chat_id" as chat_id, fb."message_id"::text as message_id,
      (select string_agg(p.value ->> 'text', '' order by p.ordinality) from jsonb_array_elements(case when jsonb_typeof(q.parts) = 'array' then q.parts else '[]'::jsonb end) with ordinality as p(value, ordinality) where p.value ->> 'type' = 'text') as prompt,
      (select string_agg(p.value ->> 'text', '' order by p.ordinality) from jsonb_array_elements(case when jsonb_typeof(a.parts) = 'array' then a.parts else '[]'::jsonb end) with ordinality as p(value, ordinality) where p.value ->> 'type' = 'text') as reply,
      fb."reason" as reason,
      fb."comment" as comment
    from "better_supabase"."ai_message_feedback" fb
    join "better_supabase"."ai_messages" a on a."chat_id" = fb."chat_id" and a."id" = fb."message_id"
    join "better_supabase"."ai_messages" q on q."chat_id" = a."chat_id" and q."id" = a."parent_id"
    join "better_supabase"."ai_chats" ch on ch."id" = fb."chat_id"
    where fb."rating" = add_eval_items_from_feedback.rating
      and (v_dataset."tenant_id" is null or ch."tenant_id" = v_dataset."tenant_id")
      and (add_eval_items_from_feedback.since is null or fb."updated_at" >= add_eval_items_from_feedback.since)
    order by fb."updated_at" desc
    limit least(greatest(coalesce(add_eval_items_from_feedback.max_rows, 100), 1), 1000)
  ), added as (
    insert into "better_supabase"."eval_items" ("dataset_id", "input", "expected", "metadata", "source_chat_id", "source_message_id")
    select v_dataset."id", jsonb_build_object('prompt', p.prompt),
      case when add_eval_items_from_feedback.rating = 1 then jsonb_build_object('output', p.reply) end,
      jsonb_build_object('source', 'ai-chat-feedback', 'rating', add_eval_items_from_feedback.rating, 'reason', p.reason, 'comment', p.comment, 'reply', p.reply),
      p.chat_id::text, p.message_id
    from picked p
    where p.prompt is not null
    on conflict do nothing
    returning 1
  )
  select count(*) into v_count from added;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_hostname (
  tenant   uuid,
  hostname text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."hostnames";
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', add_hostname.tenant, 'domains.manage'), false)) then
    raise exception 'You may not manage this organization''s hostnames' using errcode = '42501', hint = 'DOMAIN_FORBIDDEN';
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a hostname: %', add_hostname.hostname using errcode = '22023', hint = 'DOMAIN_INVALID';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."tenant_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "better_supabase"."hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'DOMAIN_TAKEN';
  end if;
  insert into "better_supabase"."hostnames" ("tenant_id", "hostname", "kind", "verified_at")
  values (add_hostname.tenant, v_hostname, v_kind, case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  perform "better_supabase".emit_event('hostname.added', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.added',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  if v_row."verified_at" is not null then
    perform "better_supabase".emit_event('hostname.verified', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.verified',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
exception when unique_violation then
  raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'DOMAIN_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.apply_support_approval (
  request_id uuid,
  approver   uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."support_requests";
begin
  select * into v_row from "better_supabase"."support_requests" x where x."id" = request_id for update;
  if not found then
    raise exception 'No support request %', request_id using errcode = 'P0002', hint = 'IMPERSONATION_REQUEST_MISSING';
  end if;
  if approver is null then
    raise exception 'Not allowed to approve a support session' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
  end if;
  if v_row."admin_id" = approver then
    raise exception 'An admin cannot approve their own support session' using errcode = '42501', hint = 'IMPERSONATION_SELF_APPROVAL';
  end if;
  if v_row."approved_by" is not null then
    if v_row."approved_by" = approver then
      return jsonb_build_object(
    'id', v_row."id",
    'admin_id', v_row."admin_id",
    'target_user_id', v_row."target_user_id",
    'reason', v_row."reason",
    'tenant', v_row."tenant_id",
    'read_only', v_row."read_only",
    'metadata', v_row."metadata",
    'requested_at', v_row."requested_at",
    'expires_at', v_row."expires_at",
    'approved_by', v_row."approved_by",
    'approved_at', v_row."approved_at",
    'session_id', v_row."session_id"
  );
    end if;
    raise exception 'Support request % is already approved', request_id using errcode = 'P0001', hint = 'IMPERSONATION_REQUEST_DECIDED';
  end if;
  if v_row."session_id" is not null or v_row."expires_at" <= now() then
    raise exception 'Support request % has expired or was used', request_id using errcode = 'P0001', hint = 'IMPERSONATION_REQUEST_CLOSED';
  end if;
  update "better_supabase"."support_requests" x set "approved_by" = approver, "approved_at" = now()
  where x."id" = request_id
  returning * into v_row;
  perform "better_supabase"."approval_settle"('support_request', request_id::text, 'start', 'approved', approver);
  return jsonb_build_object(
    'id', v_row."id",
    'admin_id', v_row."admin_id",
    'target_user_id', v_row."target_user_id",
    'reason', v_row."reason",
    'tenant', v_row."tenant_id",
    'read_only', v_row."read_only",
    'metadata', v_row."metadata",
    'requested_at', v_row."requested_at",
    'expires_at', v_row."expires_at",
    'approved_by', v_row."approved_by",
    'approved_at', v_row."approved_at",
    'session_id', v_row."session_id"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approve_support_request (
  request_id  uuid,
  approver_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  approver uuid;
  v_row "better_supabase"."support_requests";
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  if service then
    approver := approver_id;
    if approver is null then
      raise exception 'approver_id is required for the service role' using errcode = '22023', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  else
    approver := auth.uid();
    if approver is null or (approver_id is not null and approver_id <> approver) then
      raise exception 'Not allowed to approve a support session' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  end if;
  select * into v_row from "better_supabase"."support_requests" x where x."id" = request_id for update;
  if not found then
    raise exception 'No support request %', request_id using errcode = 'P0002', hint = 'IMPERSONATION_REQUEST_MISSING';
  end if;
  if v_row."admin_id" = approver then
    raise exception 'An admin cannot approve their own support session' using errcode = '42501', hint = 'IMPERSONATION_SELF_APPROVAL';
  end if;
  if not service and not "better_supabase"."is_platform"('impersonation.start') then
    raise exception 'Not allowed to approve this support session' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
  end if;
  return "better_supabase"."apply_support_approval"(request_id, approver);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bom_where_used (
  variant_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (select cv."tenant_id" from "better_supabase"."product_variants" cv where cv."id" = bom_where_used.variant_id);
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'manufacturing.read'), false))) then
    raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'MANUFACTURING_BOM_NOT_FOUND';
  end if;
  return coalesce((with recursive used(bom, variant, version, status, quantity, level, path) as (
    select x."id", x."variant_id", x."version", x."status", y."quantity", 1, array[y."variant_id", x."variant_id"]
    from "better_supabase"."bom_components" y join "better_supabase"."boms" x on x."id" = y."bom_id"
    where y."variant_id" = bom_where_used.variant_id and x."status" <> 'archived'
    union all
    select x."id", x."variant_id", x."version", x."status", y."quantity", used.level + 1, used.path || x."variant_id"
    from used
    join "better_supabase"."bom_components" y on y."variant_id" = used.variant
    join "better_supabase"."boms" x on x."id" = y."bom_id" and x."status" = 'active'
    where used.status = 'active' and used.level < 20 and not (x."variant_id" = any (used.path))
  )
  select jsonb_agg(jsonb_build_object('level', u.level, 'bomId', u.bom, 'variantId', u.variant, 'version', u.version,
    'status', u.status, 'quantity', u.quantity::text) order by u.level, u.variant, u.version desc) from used u), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_prescription (
  prescription_id uuid,
  reason          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
  v_reason text := nullif(trim(cancel_prescription.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = cancel_prescription.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'E_PRESCRIBING_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.manage'), false))) and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) and v_row."prescriber_id" is not distinct from auth.uid()) then
    raise exception 'only the prescriber or a manager cancels a prescription' using errcode = '42501', hint = 'E_PRESCRIBING_FORBIDDEN';
  end if;
  if v_row."status" in ('dispensed', 'cancelled') then
    raise exception 'a dispensed or cancelled prescription cannot be cancelled' using errcode = '55000', hint = 'E_PRESCRIBING_STATUS';
  end if;
  if v_reason is null and v_row."status" <> 'draft' then
    raise exception 'cancelling a signed or sent prescription needs a reason' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  if length(coalesce(v_reason, '')) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'cancelled', "cancelled_at" = now(), "cancel_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('prescription.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.cancelled',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription cancelled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.care_decision_context (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (care_decision_context.tenant is not null and coalesce(better_supabase.can('tenant', care_decision_context.tenant, 'clinical_decision_support.read'), false))) then
    raise exception 'not allowed to read the decision context' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case care_decision_context.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (care_decision_context.subject_id)::uuid and s."id"::text = care_decision_context.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      else false
    end and "better_supabase"."can_subject"(care_decision_context.subject_type, care_decision_context.subject_id, 'read'))) then
    raise exception 'the context needs a record of the organization' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_SUBJECT_INVALID';
  end if;
  return jsonb_build_object(
    'organizationId', care_decision_context.tenant,
    'subjectType', care_decision_context.subject_type,
    'subjectId', care_decision_context.subject_id,
    'medications', coalesce((select jsonb_agg(jsonb_build_object('orderId', o."id", 'medicationId', o."medication_id", 'name', mx."name", 'codeSystem', mx."code_system", 'code', mx."code", 'dose', o."dose", 'doseUnit', o."dose_unit", 'asNeeded', o."as_needed", 'maxPerDay', o."max_per_day", 'schedule', o."schedule", 'startsOn', o."starts_on", 'endsOn', o."ends_on") order by mx."name", o."id")
      from "better_supabase"."medication_orders" o join "better_supabase"."medications" mx on mx."id" = o."medication_id" and mx."tenant_id" = o."tenant_id"
    where o."tenant_id" = care_decision_context.tenant and o."subject_type" = care_decision_context.subject_type and o."subject_id" = care_decision_context.subject_id
      and o."status" = 'active' and o."starts_on" <= (now() at time zone 'UTC')::date and (o."ends_on" is null or o."ends_on" >= (now() at time zone 'UTC')::date)), '[]'::jsonb),
    'observations', coalesce((select jsonb_agg(jsonb_build_object('key', q."key", 'code', q."code", 'codeSystem', q."code_system", 'unit', q."unit", 'valueNumber', q."value_number", 'valueText', q."value_text", 'valueCode', q."value_code", 'flag', q."flag", 'observedAt', q."observed_at") order by q."key")
      from (select distinct on (od."id") od."key", od."code", od."code_system", od."unit", ox."value_number", ox."value_text", ox."value_code", ox."flag", ox."observed_at"
        from "better_supabase"."observations" ox join "better_supabase"."observation_definitions" od on od."id" = ox."definition_id"
        where ox."tenant_id" = care_decision_context.tenant and ox."subject_type" = care_decision_context.subject_type and ox."subject_id" = care_decision_context.subject_id and ox."status" <> 'entered_in_error'
        order by od."id", ox."observed_at" desc) q), '[]'::jsonb),
    'consents', coalesce((select jsonb_agg(jsonb_build_object('purpose', pu."key", 'status', cx."status", 'scope', cx."scope", 'grantedAt', cx."granted_at", 'validUntil', cx."expires_at") order by pu."key")
      from "better_supabase"."consents" cx join "better_supabase"."consent_purposes" pu on pu."id" = cx."purpose_id"
      where cx."tenant_id" = care_decision_context.tenant and cx."subject_type" = care_decision_context.subject_type and cx."subject_id" = care_decision_context.subject_id and cx."status" = 'granted'), '[]'::jsonb),
    'carePlan', (select jsonb_build_object('id', px."id", 'title', px."title", 'version', px."version", 'reviewOn', px."review_on")
      from "better_supabase"."care_plans" px
      where px."tenant_id" = care_decision_context.tenant and px."subject_type" = care_decision_context.subject_type and px."subject_id" = care_decision_context.subject_id and px."status" = 'active'
      order by px."version" desc limit 1));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.compare_eval_runs (
  base       uuid,
  candidate  uuid,
  score_drop numeric DEFAULT NULL::numeric
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_base "better_supabase"."eval_runs"%rowtype;
  v_candidate "better_supabase"."eval_runs"%rowtype;
  v_base_summary jsonb;
  v_candidate_summary jsonb;
begin
  select x.* into v_base from "better_supabase"."eval_runs" x where x."id" = compare_eval_runs.base;
  if not found then
    raise exception 'No eval run %', compare_eval_runs.base using errcode = 'P0002', hint = 'AI_EVAL_RUN_NOT_FOUND';
  end if;
  select x.* into v_candidate from "better_supabase"."eval_runs" x where x."id" = compare_eval_runs.candidate;
  if not found then
    raise exception 'No eval run %', compare_eval_runs.candidate using errcode = 'P0002', hint = 'AI_EVAL_RUN_NOT_FOUND';
  end if;
  if v_base."dataset_id" <> v_candidate."dataset_id" then
    raise exception 'Runs belong to different datasets' using errcode = '22023', hint = 'AI_EVAL_RUN_MISMATCH';
  end if;
  v_base_summary := "better_supabase"."eval_run_summary"(compare_eval_runs.base);
  v_candidate_summary := "better_supabase"."eval_run_summary"(compare_eval_runs.candidate);
  return (
    with joined as materialized (
      select coalesce(b."item_id", c."item_id") as item,
        b."passed" as base_passed, c."passed" as candidate_passed,
        (select avg((e.value ->> 'score')::numeric) from jsonb_each(b."scores") e) as base_score, (select avg((e.value ->> 'score')::numeric) from jsonb_each(c."scores") e) as candidate_score,
        b."output" as base_output, c."output" as candidate_output
      from (select * from "better_supabase"."eval_results" where "run_id" = compare_eval_runs.base) b
      full join (select * from "better_supabase"."eval_results" where "run_id" = compare_eval_runs.candidate) c on c."item_id" = b."item_id"
    ), tagged as (
      select j.*, case
        when j.base_passed is null or j.candidate_passed is null then 'missing'
        when j.base_passed and not j.candidate_passed then 'regression'
        when not j.base_passed and j.candidate_passed then 'improvement'
        when compare_eval_runs.score_drop is not null and j.base_score - j.candidate_score > compare_eval_runs.score_drop then 'regression'
        when compare_eval_runs.score_drop is not null and j.candidate_score - j.base_score > compare_eval_runs.score_drop then 'improvement'
        else 'unchanged' end as kind
      from joined j
    )
    select jsonb_build_object(
      'base', v_base_summary,
      'candidate', v_candidate_summary,
      'pass_rate_delta', round(coalesce((v_candidate_summary ->> 'passRate')::numeric, 0) - coalesce((v_base_summary ->> 'passRate')::numeric, 0), 4),
      'regressions', coalesce(jsonb_agg(jsonb_build_object('item_id', t.item, 'base_score', t.base_score, 'candidate_score', t.candidate_score, 'base_output', t.base_output, 'candidate_output', t.candidate_output) order by t.item) filter (where t.kind = 'regression'), '[]'::jsonb),
      'improvements', coalesce(jsonb_agg(jsonb_build_object('item_id', t.item, 'base_score', t.base_score, 'candidate_score', t.candidate_score) order by t.item) filter (where t.kind = 'improvement'), '[]'::jsonb),
      'unchanged', count(*) filter (where t.kind = 'unchanged'),
      'missing', count(*) filter (where t.kind = 'missing')
    )
    from tagged t
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_webhook_delivery (
  delivery uuid,
  outcome  jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_status text := complete_webhook_delivery.outcome ->> 'status';
  v_attempt integer := (complete_webhook_delivery.outcome ->> 'attempt')::integer;
  v_endpoint uuid;
  v_tenant uuid;
  v_since timestamptz;
  v_result text := 'ok';
begin
  if v_status is null or v_status not in ('succeeded', 'retrying', 'dead', 'canceled') then
    raise exception 'status must be succeeded, retrying, dead or canceled' using errcode = '22023', hint = 'WEBHOOK_STATUS_UNKNOWN';
  end if;
  if v_attempt is null then
    raise exception 'outcome.attempt must be the attempt the claim returned' using errcode = '22023', hint = 'WEBHOOK_ATTEMPT_REQUIRED';
  end if;
  update "better_supabase"."webhook_deliveries" v
  set "status" = v_status,
    "attempt" = case when v_status = 'canceled' then greatest(v."attempt" - 1, 0) else v."attempt" end,
    "available_at" = case when v_status = 'retrying' then coalesce((complete_webhook_delivery.outcome ->> 'retry_at')::timestamptz, now()) else v."available_at" end,
    "lease_expires_at" = null,
    "response_status" = (complete_webhook_delivery.outcome ->> 'response_status')::integer,
    "response_body" = complete_webhook_delivery.outcome ->> 'response_body',
    "duration_ms" = (complete_webhook_delivery.outcome ->> 'duration_ms')::integer,
    "last_error" = complete_webhook_delivery.outcome ->> 'error',
    "processed_at" = case when v_status = 'retrying' then null else now() end,
    "updated_at" = now()
  where v."id" = complete_webhook_delivery.delivery
    and v."attempt" = v_attempt
    and v."status" = 'delivering'
  returning v."endpoint_id" into v_endpoint;
  if not found then
    if exists (select 1 from "better_supabase"."webhook_deliveries" v where v."id" = complete_webhook_delivery.delivery) then
      return 'stale';
    end if;
    raise exception 'Webhook delivery not found' using errcode = 'P0002', hint = 'WEBHOOK_DELIVERY_NOT_FOUND';
  end if;
  if v_status = 'succeeded' then
    update "better_supabase"."webhook_endpoints" d set "first_failed_at" = null
    where d."id" = v_endpoint and d."first_failed_at" is not null;
  elsif v_status in ('retrying', 'dead') then
    update "better_supabase"."webhook_endpoints" d set "first_failed_at" = coalesce(d."first_failed_at", now())
    where d."id" = v_endpoint
    returning d."first_failed_at", d."tenant_id" into v_since, v_tenant;
    if v_since <= now() - '5 days'::interval then
      update "better_supabase"."webhook_endpoints" d set "enabled" = false, "disabled_at" = now(), "disabled_reason" = format('Deliveries failed since %s', v_since), "updated_at" = now()
      where d."id" = v_endpoint and d."enabled";
      if found then
        v_result := 'disabled';
        perform "better_supabase".emit_event('webhook_endpoint.disabled', jsonb_build_object('endpointId', v_endpoint, 'organizationId', v_tenant::text, 'failingSince', v_since), 'webhooks/' || v_endpoint::text, (v_tenant::text)::text, 'webhook_endpoint.disabled:' || v_endpoint::text || ':' || v_since::text, 'better-supabase/webhooks');
  perform better_supabase.audit_event(
    event_type => 'webhook_endpoint.disabled',
    category => 'integration',
    target_type => 'webhook_endpoint',
    record_id => v_endpoint::text,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('endpointId', v_endpoint, 'organizationId', v_tenant::text, 'failingSince', v_since),
    idempotency_key => 'webhook_endpoint.disabled:' || v_endpoint::text || ':' || v_since::text
  );
      end if;
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_webhook_delivery"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using complete_webhook_delivery.delivery, v_status;
    end if;
  end;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_eval_run (
  dataset        uuid,
  prompt_name    text,
  prompt_version integer,
  model          text,
  scorers        jsonb   DEFAULT '[]'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_dataset "better_supabase"."eval_datasets"%rowtype;
  v_row "better_supabase"."eval_runs"%rowtype;
begin
  select x.* into v_dataset from "better_supabase"."eval_datasets" x where x."id" = create_eval_run.dataset;
  if not found then
    raise exception 'No eval dataset %', create_eval_run.dataset using errcode = 'P0002', hint = 'AI_EVAL_DATASET_NOT_FOUND';
  end if;
  insert into "better_supabase"."eval_runs" ("dataset_id", "tenant_id", "prompt_name", "prompt_version", "model", "scorers")
  values (create_eval_run.dataset, v_dataset."tenant_id", create_eval_run.prompt_name, create_eval_run.prompt_version, create_eval_run.model, coalesce(create_eval_run.scorers, '[]'::jsonb))
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'dataset_id', v_row."dataset_id", 'tenant_id', v_row."tenant_id", 'prompt_name', v_row."prompt_name", 'prompt_version', v_row."prompt_version", 'model', v_row."model", 'scorers', v_row."scorers", 'status', v_row."status", 'summary', v_row."summary", 'created_at', v_row."created_at", 'finished_at', v_row."finished_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_incoming_webhook (
  tenant           uuid,
  name             text,
  verify           text  DEFAULT 'none'::text,
  metadata         jsonb DEFAULT '{}'::jsonb,
  signature_header text  DEFAULT NULL::text,
  subject_type     text  DEFAULT NULL::text,
  subject_id       text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid := gen_random_uuid();
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  secret text := case verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  created "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    raise exception 'Not allowed to manage incoming webhooks' using errcode = '42501', hint = 'INCOMING_WEBHOOK_FORBIDDEN';
  end if;
  if verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'INCOMING_WEBHOOK_VERIFY_UNKNOWN';
  end if;
  if (subject_type is null) <> (subject_id is null) then
    raise exception 'Pass subject_type and subject_id together' using errcode = '22023', hint = 'INCOMING_WEBHOOK_SUBJECT_INVALID';
  end if;
  if subject_type is not null and not (true) then
    raise exception 'No such subject in this tenant' using errcode = '22023', hint = 'INCOMING_WEBHOOK_SUBJECT_INVALID';
  end if;
  insert into "better_supabase"."incoming_webhooks" ("id", "tenant", "name", "token_hash", "verify", "secret", "secret_id", "signature_header", "metadata", "subject_type", "subject_id", "created_by")
  values (v_id,
    tenant,
    name,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    verify,
    null,
    case when secret is null then null else vault.create_secret(secret, 'webhook-in:' || v_id::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    case verify
      when 'hmac-sha256' then coalesce(signature_header, null, 'x-signature')
      when 'shared-secret' then coalesce(signature_header, null, 'x-webhook-secret')
    end,
    coalesce(metadata, '{}'),
    subject_type,
    subject_id,
    auth.uid())
  returning * into created;
  perform "better_supabase".emit_event('incoming_webhook.created', jsonb_build_object('organizationId', created."tenant"::text, 'endpointId', created."id", 'name', created."name"), 'organizations/' || created."tenant"::text || '/incoming-webhooks/' || created."id"::text, (created."tenant")::text, null, 'better-supabase/incoming-webhooks');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.created',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => created."id"::text,
    tenant => (created."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', created."tenant"::text, 'endpointId', created."id", 'name', created."name")
  );
  return jsonb_build_object('id', created."id", 'tenant', created."tenant", 'name', created."name",
    'verify', created."verify", 'token', token, 'secret', secret, 'signatureHeader', created."signature_header",
    'subjectType', created."subject_type", 'subjectId', created."subject_id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_prescription (
  tenant   uuid,
  order_id uuid,
  attrs    jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_attrs jsonb := coalesce(create_prescription.attrs, '{}'::jsonb);
  v_order "better_supabase"."medication_orders";
  v_row "better_supabase"."prescriptions";
  v_prescriber uuid := auth.uid();
  v_name text := nullif(trim(v_attrs ->> 'prescriberName'), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_prescription.tenant is not null and coalesce(better_supabase.can('tenant', create_prescription.tenant, 'e_prescribing.write'), false))) then
    raise exception 'not allowed to draft prescriptions' using errcode = '42501', hint = 'E_PRESCRIBING_FORBIDDEN';
  end if;
  begin
    v_prescriber := coalesce(v_prescriber, nullif(v_attrs ->> 'prescriberId', '')::uuid);
  exception when invalid_text_representation then
    raise exception 'prescriberId is a uuid' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end;
  if v_prescriber is null then
    raise exception 'a prescription needs a prescriber' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  if v_name is not null and length(v_name) > 300 then
    raise exception 'a prescriber name is up to 300 characters' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = create_prescription.tenant and x."id" = create_prescription.order_id;
  if not found then
    raise exception 'the order is not one of the organization' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'only an active medication order can be prescribed' using errcode = '55000', hint = 'E_PRESCRIBING_STATUS';
  end if;
  begin
    insert into "better_supabase"."prescriptions" ("tenant_id", "order_id", "subject_type", "subject_id", "prescriber_id", "prescriber_name")
    values (create_prescription.tenant, v_order."id", v_order."subject_type", v_order."subject_id", v_prescriber, v_name)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'this order already has a prescription that is not cancelled' using errcode = '55000', hint = 'E_PRESCRIBING_STATUS';
  end;
  perform "better_supabase".emit_event('prescription.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.created',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription drafted',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_production_order (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_orders";
  v_variant uuid;
  v_quantity numeric;
  v_location uuid;
  v_bom uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_production_order.tenant is not null and coalesce(better_supabase.can('tenant', create_production_order.tenant, 'manufacturing.write'), false))) then
    raise exception 'not allowed to create production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if jsonb_typeof(create_production_order.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  v_variant := nullif(create_production_order.input ->> 'variantId', '')::uuid;
  v_quantity := nullif(create_production_order.input ->> 'quantity', '')::numeric;
  if v_variant is null or not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = v_variant and cv."tenant_id" = create_production_order.tenant) then
    raise exception 'the variant isn''t a variant of this organization' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if v_quantity is null or v_quantity <= 0 then
    raise exception 'the quantity must be more than zero' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  v_location := nullif(create_production_order.input ->> 'locationId', '')::uuid;
  if v_location is null then
    select y."id" into v_location from "better_supabase"."inventory_locations" y
    where y."tenant_id" = create_production_order.tenant and y."active"
    order by y."code"
    limit 1;
  end if;
  if v_location is null or not exists (select 1 from "better_supabase"."inventory_locations" y where y."id" = v_location
    and y."tenant_id" = create_production_order.tenant and y."active") then
    raise exception 'the location isn''t an active location of this organization' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select x."id" into v_bom from "better_supabase"."boms" x
  where x."variant_id" = v_variant and x."status" = 'active'
    and (nullif(create_production_order.input ->> 'bomId', '') is null or x."id" = (create_production_order.input ->> 'bomId')::uuid);
  if v_bom is null then
    raise exception 'the variant has no active bill of materials' using errcode = '55000', hint = 'MANUFACTURING_BOM_NOT_ACTIVE';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'production_order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'production_order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(create_production_order.tenant, 'production_order', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(create_production_order.tenant, 'production_order', now(), '');
  v_number := better_supabase.format_assigned_number('MO-{yyyy}-{n:4}', v_seq, now());
  end if;
  insert into "better_supabase"."production_orders" ("tenant_id", "number", "sequence", "variant_id", "bom_id", "quantity", "location_id", "due_on", "note", "created_by")
  values (create_production_order.tenant, v_number, v_seq, v_variant, v_bom, v_quantity, v_location,
    nullif(create_production_order.input ->> 'dueOn', '')::date, nullif(trim(create_production_order.input ->> 'note'), ''), auth.uid())
  returning * into v_row;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'variantId', v_row."variant_id", 'bomId', v_row."bom_id", 'quantity', v_row."quantity"::text, 'locationId', v_row."location_id", 'dueOn', v_row."due_on", 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id", 'materialCost', v_row."material_cost"::text, 'laborCost', v_row."labor_cost"::text, 'currency', v_row."currency", 'note', v_row."note", 'releasedAt', v_row."released_at", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_row."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_row."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_row."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_row."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_row."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_row."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"), '[]'::jsonb)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_ssf_stream (
  id               uuid,
  receiver         text,
  tenant           text,
  audience         text[],
  delivery_method  text,
  events_requested text[],
  events_delivered text[],
  description      text   DEFAULT NULL::text,
  endpoint_url     text   DEFAULT NULL::text,
  credential_ref   jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
  v_endpoint uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ssf_streams" ("id", "tenant", "receiver", "audience", "delivery_method", "events_requested", "events_delivered", "description")
  values (create_ssf_stream.id, create_ssf_stream.tenant, create_ssf_stream.receiver, create_ssf_stream.audience,
    create_ssf_stream.delivery_method, coalesce(create_ssf_stream.events_requested, '{}'),
    coalesce(create_ssf_stream.events_delivered, '{}'), create_ssf_stream.description)
  returning * into v_row;
  if v_row."delivery_method" = 'urn:ietf:rfc:8935' then
    if coalesce(create_ssf_stream.endpoint_url, '') = '' then
      raise exception 'a push stream needs an endpoint_url' using errcode = '22023', hint = 'SSF_ENDPOINT_REQUIRED';
    end if;
    if v_row."tenant" is null then
      raise exception 'a push stream needs a tenant when webhook endpoints have one' using errcode = '22023', hint = 'SSF_TENANT_REQUIRED';
    end if;
    insert into "better_supabase"."webhook_endpoints" as we ("tenant_id", "name", "url", "format", "credential_ref")
    values (v_row."tenant"::uuid, 'Shared Signals stream ' || v_row."id", create_ssf_stream.endpoint_url, 'set', create_ssf_stream.credential_ref)
    returning we."id" into v_endpoint;
    update "better_supabase"."ssf_streams" s set "endpoint_id" = v_endpoint where s."id" = v_row."id"
    returning s.* into v_row;
  end if;
  perform "better_supabase".emit_event('ssf_stream.created', jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant", 'method', v_row."delivery_method"), 'shared-signals/' || v_row."id", null, null, 'better-supabase/security-events');
  perform better_supabase.audit_event(
    event_type => 'ssf_stream.created',
    category => 'security',
    target_type => 'ssf_stream',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant", 'method', v_row."delivery_method")
  );
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant",
    'receiver', v_row."receiver",
    'audience', to_jsonb(v_row."audience"),
    'description', v_row."description",
    'eventsRequested', to_jsonb(v_row."events_requested"),
    'eventsDelivered', to_jsonb(v_row."events_delivered"),
    'method', v_row."delivery_method",
    'endpointUrl', (select we."url" from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id"),
    'status', v_row."status",
    'reason', v_row."reason",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_care_alert (
  alert_id uuid,
  decision text,
  reason   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_alerts";
  v_reason text := nullif(trim(decide_care_alert.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_alerts" x where x."id" = decide_care_alert.alert_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.read'), false))) then
    raise exception 'no such alert' using errcode = 'P0002', hint = 'DECISION_SUPPORT_ALERT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.write'), false))) then
    raise exception 'not allowed to decide on care alerts' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  if decide_care_alert.decision is null or decide_care_alert.decision not in ('acknowledged', 'overridden') then
    raise exception 'decision is acknowledged or overridden' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_row."status" = 'resolved' or (v_row."status" = 'overridden') or (v_row."status" = 'acknowledged' and decide_care_alert.decision = 'acknowledged') then
    raise exception 'this alert has already been decided or resolved' using errcode = '55000', hint = 'DECISION_SUPPORT_ALERT_STATUS';
  end if;
  if v_reason is null and (decide_care_alert.decision = 'overridden' or v_row."severity" = 'critical') then
    raise exception 'overriding an alert, or deciding on a critical one, needs a reason' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_reason is not null and length(v_reason) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_care_alert_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_row."id", decide_care_alert.decision;
    end if;
  end;
  update "better_supabase"."care_alerts" x set "status" = decide_care_alert.decision, "decided_by" = auth.uid(), "decided_at" = now(),
    "decision_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('care_alert.decided', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status"), 'care-alerts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_alert.decided',
    category => 'data',
    target_type => 'care_alert',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care alert decided',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_care_alert_decide"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'ruleId', v_row."rule_id", 'orderIds', to_jsonb(v_row."order_ids"), 'message', v_row."message", 'details', v_row."details", 'fingerprint', v_row."fingerprint", 'status', v_row."status", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'decisionReason', v_row."decision_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_care_rule (
  rule_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_rules" x where x."id" = delete_care_rule.rule_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.read'), false))) then
    raise exception 'no such rule' using errcode = 'P0002', hint = 'DECISION_SUPPORT_RULE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.manage'), false))) then
    raise exception 'not allowed to change care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  delete from "better_supabase"."care_rules" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('care_rule.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity"), 'care-rules/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_rule.deleted',
    category => 'configuration',
    target_type => 'care_rule',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care rule deleted',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_field_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'CUSTOM_FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  perform "better_supabase".emit_event('field_definition.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_field_definition.definition), 'custom-fields/' || delete_field_definition.definition::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_field_value (
  value_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_subject text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select v."tenant_id", v."subject_type", v."subject_id"
  into v_tenant, v_type, v_subject
  from "better_supabase"."field_values" v where v."id" = delete_field_value.value_id;
  if not found then
    raise exception 'field value not found' using errcode = 'P0002', hint = 'CUSTOM_FIELD_VALUE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to delete this field value' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if not (case v_type
    when 'drive_node' then coalesce("better_supabase"."can_subject"(v_type, v_subject, 'fields'), false)
    else true
  end) then
    raise exception 'not allowed to delete fields on this record' using errcode = '42501', hint = 'FIELD_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_values" where "id" = delete_field_value.value_id;
  perform "better_supabase".emit_event('field_value.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_field_value.value_id, 'subjectType', v_type, 'subjectId', v_subject), 'field-values/' || delete_field_value.value_id::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_incoming_webhook (
  endpoint uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  perform "better_supabase".emit_event('incoming_webhook.deleted', jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint), 'organizations/' || tenant::text || '/incoming-webhooks/' || endpoint::text, (tenant)::text, null, 'better-supabase/incoming-webhooks');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.deleted',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => endpoint::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ssf_stream (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."ssf_streams" s where s."id" = delete_ssf_stream.id returning s.* into v_row;
  if not found then
    return false;
  end if;
  if v_row."endpoint_id" is not null then
    delete from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id";
  end if;
  perform "better_supabase".emit_event('ssf_stream.deleted', jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant"), 'shared-signals/' || v_row."id", null, null, 'better-supabase/security-events');
  perform better_supabase.audit_event(
    event_type => 'ssf_stream.deleted',
    category => 'security',
    target_type => 'ssf_stream',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_save (
  node                   uuid,
  document_type          text,
  owner_id               uuid    DEFAULT NULL::uuid,
  review_interval_months integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_seq bigint;
  v_number text;
  v_entity text;
  v_format text;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_save.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be a controlled document' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to control this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if drive_document_save.document_type is null or not (drive_document_save.document_type = any (array['sop', 'policy', 'form']::text[])) then
    raise exception 'that document type is not in options.control.types' using errcode = '22023', hint = 'DRIVE_DOCUMENT_TYPE_UNKNOWN';
  end if;
  if v_node."document_status" = 'obsolete' then
    raise exception 'an obsolete document can''t change' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_save.owner_id is not null and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_document_save.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'DRIVE_DOCUMENT_OWNER_INVALID';
  end if;
  v_number := v_node."document_number";
  if v_number is null then
    case drive_document_save.document_type
      when 'sop' then
        v_entity := 'drive_document_sop';
        v_format := 'SOP-{n:4}';
      else
        v_entity := 'drive_document';
        v_format := 'DOC-{n:5}';
    end case;
    if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_node."tenant_id", v_entity, v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_node."tenant_id", v_entity, now());
    v_number := better_supabase.format_assigned_number(v_format, v_seq, now());
  end if;
  end if;
  update "better_supabase"."drive_nodes" x set "document_number" = v_number,
    "document_type" = drive_document_save.document_type,
    "document_owner_id" = coalesce(drive_document_save.owner_id, x."document_owner_id", auth.uid()),
    "review_interval_months" = coalesce(drive_document_save.review_interval_months, x."review_interval_months"), "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  if v_node."document_status" is null then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'draft', null);
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  end if;
  perform "better_supabase".emit_event('drive_node.document_updated', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.document_updated',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document saved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_message (
  message uuid,
  body    text,
  attrs   jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
  v_parsed jsonb := "better_supabase"."parse_mentions"(edit_message.body);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = edit_message.message and m."author_id" = auth.uid() and m."archived_at" is null
    and "better_supabase"."can_conversation"(m."conversation_id", 'read');
  if not found then
    raise exception 'no message of yours has this id' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = v_msg."conversation_id"
      and c."access" = 'subject' and c."subject_type" in ('drive_node')
  ) and not "better_supabase"."can_conversation"(v_msg."conversation_id", 'send') then
    raise exception 'not allowed to comment on this record' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if v_msg."sent_at" is not null and not (true) then
    raise exception 'this message can no longer be edited' using errcode = '55000', hint = 'MESSAGING_EDIT_CLOSED';
  end if;
  if nullif(trim(coalesce(edit_message.body, '')), '') is null then
    raise exception 'a message needs a body' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_edit"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using edit_message.message, edit_message.body;
    end if;
  end;
  insert into "better_supabase"."message_edits" ("tenant_id", "message_id", "body", "document", "edited_by")
  values (v_msg."tenant_id", v_msg."id", v_msg."body", v_msg."document", auth.uid());
  begin
    update "better_supabase"."messages" m set
      "body" = edit_message.body,
      "document" = case when edit_message.attrs ? 'document' then edit_message.attrs -> 'document' else m."document" end,
      "mentions" = array(
        select distinct x from (
          select (jsonb_array_elements_text(coalesce(edit_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
          union
          select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
        ) s
      ),
      "edited_at" = now()
    where m."id" = v_msg."id"
    returning * into v_msg;
  exception when check_violation or invalid_text_representation then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  if v_msg."sent_at" is not null then
    perform "better_supabase"."index_record_mentions"(v_msg."id");
    perform "better_supabase".emit_event('message.updated', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_message_edit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_msg."id";
    end if;
  end;
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.encrypt_field_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_key text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "type" into v_tenant, v_type from "better_supabase"."field_definitions" where "id" = encrypt_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'CUSTOM_FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if v_type not in ('text', 'email', 'url', 'bsn', 'iban', 'phone_e164') then
    raise exception 'only text fields can be encrypted' using errcode = '22023', hint = 'FIELD_NOT_ENCRYPTABLE';
  end if;
  v_key := "better_supabase"."field_key"('tenant:' || v_tenant::text, true);
  update "better_supabase"."field_definitions" set "encrypted" = true where "id" = encrypt_field_definition.definition;
  update "better_supabase"."field_values" set "value_text" = "better_supabase"."field_seal"(v_key, "value_text")
  where "definition_id" = encrypt_field_definition.definition
    and "value_text" is not null
    and left("value_text", 5) <> 'bsf1:';
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.evaluate_care_rules (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_alerts jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (evaluate_care_rules.tenant is not null and coalesce(better_supabase.can('tenant', evaluate_care_rules.tenant, 'clinical_decision_support.write'), false))) then
    raise exception 'not allowed to evaluate care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case evaluate_care_rules.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."id"::text = evaluate_care_rules.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      else false
    end and "better_supabase"."can_subject"(evaluate_care_rules.subject_type, evaluate_care_rules.subject_id, 'read'))) then
    raise exception 'evaluating needs a record of the organization' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_SUBJECT_INVALID';
  end if;
  with active as (
    select o."id" as order_id, o."medication_id" as medication_id, o."dose" as dose, o."dose_unit" as unit, mx."name" as name,
      coalesce(
        case when o."schedule" ? 'times' then jsonb_array_length(o."schedule" -> 'times') * o."dose"
          when o."schedule" ? 'everyHours' then 24 / nullif((o."schedule" ->> 'everyHours')::numeric, 0) * o."dose" end,
        case when o."as_needed" then o."max_per_day" end) as per_day
    from "better_supabase"."medication_orders" o join "better_supabase"."medications" mx on mx."id" = o."medication_id" and mx."tenant_id" = o."tenant_id"
    where o."tenant_id" = evaluate_care_rules.tenant and o."subject_type" = evaluate_care_rules.subject_type and o."subject_id" = evaluate_care_rules.subject_id
      and o."status" = 'active' and o."starts_on" <= (now() at time zone 'UTC')::date and (o."ends_on" is null or o."ends_on" >= (now() at time zone 'UTC')::date)
  ), raised(alert) as (
      select jsonb_build_object(
        'kind', 'dose_range', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', jsonb_build_array(d.order_id),
        'fingerprint', 'dose_range:' || r."id"::text || ':' || d.order_id::text || ':min',
        'message', coalesce(r."message", format('%s: a dose of %s %s is below the minimum of %s', d.name, d.dose, d.unit, r."min_dose")),
        'details', jsonb_build_object('medicationId', d.medication_id, 'limit', 'min', 'value', d.dose, 'unit', d.unit, 'bound', r."min_dose"))
      from active d join "better_supabase"."care_rules" r on r."medication_ids"[1] = d.medication_id
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'dose_range' and r."min_dose" is not null and d.dose < r."min_dose"
    union all 
      select jsonb_build_object(
        'kind', 'dose_range', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', jsonb_build_array(d.order_id),
        'fingerprint', 'dose_range:' || r."id"::text || ':' || d.order_id::text || ':max',
        'message', coalesce(r."message", format('%s: a dose of %s %s is above the maximum of %s', d.name, d.dose, d.unit, r."max_dose")),
        'details', jsonb_build_object('medicationId', d.medication_id, 'limit', 'max', 'value', d.dose, 'unit', d.unit, 'bound', r."max_dose"))
      from active d join "better_supabase"."care_rules" r on r."medication_ids"[1] = d.medication_id
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'dose_range' and r."max_dose" is not null and d.dose > r."max_dose"
    union all 
      select jsonb_build_object(
        'kind', 'dose_range', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', jsonb_build_array(d.order_id),
        'fingerprint', 'dose_range:' || r."id"::text || ':' || d.order_id::text || ':day',
        'message', coalesce(r."message", format('%s: %s %s a day is above the maximum of %s', d.name, d.per_day, d.unit, r."max_per_day")),
        'details', jsonb_build_object('medicationId', d.medication_id, 'limit', 'day', 'value', d.per_day, 'unit', d.unit, 'bound', r."max_per_day"))
      from active d join "better_supabase"."care_rules" r on r."medication_ids"[1] = d.medication_id
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'dose_range' and r."max_per_day" is not null and d.per_day > r."max_per_day"
    union all
      select jsonb_build_object(
        'kind', 'duplicate_therapy', 'severity', 'warning',
        'orderIds', to_jsonb(array_agg(d.order_id order by d.order_id)),
        'fingerprint', 'duplicate:' || d.medication_id::text,
        'message', format('%s is ordered more than once', min(d.name)),
        'details', jsonb_build_object('medicationId', d.medication_id))
      from active d group by d.medication_id having count(*) > 1
    union all
      select jsonb_build_object(
        'kind', 'duplicate_therapy', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', to_jsonb(array_agg(d.order_id order by d.order_id)),
        'fingerprint', 'therapy_group:' || r."id"::text,
        'message', coalesce(r."message", format('%s are in the same therapy group', string_agg(distinct d.name, ', '))),
        'details', jsonb_build_object('medicationIds', to_jsonb(array_agg(distinct d.medication_id))))
      from "better_supabase"."care_rules" r join active d on d.medication_id = any(r."medication_ids")
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'duplicate_therapy'
      group by r."id" having count(distinct d.medication_id) > 1
    union all
      select jsonb_build_object(
        'kind', 'interaction', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', (select to_jsonb(array_agg(d.order_id order by d.order_id)) from active d where d.medication_id = any(r."medication_ids")),
        'fingerprint', 'interaction:' || r."id"::text,
        'message', coalesce(r."message", format('%s interact', (select string_agg(distinct d.name, ' and ') from active d where d.medication_id = any(r."medication_ids")))),
        'details', jsonb_build_object('medicationIds', to_jsonb(r."medication_ids")))
      from "better_supabase"."care_rules" r
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'interaction'
        and (select count(distinct d.medication_id) from active d where d.medication_id = any(r."medication_ids")) = 2
  )
  select coalesce(jsonb_agg(raised.alert), '[]'::jsonb) into v_alerts from raised;
  return "better_supabase"."sync_care_alerts"(evaluate_care_rules.tenant, evaluate_care_rules.subject_type, evaluate_care_rules.subject_id, 'built-in', v_alerts);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expire_support_sessions()
  RETURNS SETOF jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  expired_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role expires support sessions' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
  end if;
  for expired_id in
    select s."id" from "better_supabase"."support_sessions" s
    where s."ended_at" is null and s."expires_at" <= now()
    order by s."expires_at"
    for update skip locked
  loop
    if "better_supabase"."end_support_session"(expired_id, 'expired') then
      return next (select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."tenant_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) from "better_supabase"."support_sessions" s where s."id" = expired_id);
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.explode_bom (
  variant_id uuid,
  quantity   numeric
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (select cv."tenant_id" from "better_supabase"."product_variants" cv where cv."id" = explode_bom.variant_id);
  v_lines jsonb;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'manufacturing.read'), false))) then
    raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'MANUFACTURING_BOM_NOT_FOUND';
  end if;
  if explode_bom.quantity is null or explode_bom.quantity <= 0 then
    raise exception 'the quantity must be more than zero' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."boms" x where x."variant_id" = explode_bom.variant_id and x."status" = 'active') then
    raise exception 'the variant has no active bill of materials' using errcode = '55000', hint = 'MANUFACTURING_BOM_NOT_ACTIVE';
  end if;
  with recursive tree(variant, parent, bom, quantity, level, path) as (
    select y."variant_id", x."variant_id", x."id",
      explode_bom.quantity * y."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0), 1,
      array[x."variant_id", y."variant_id"]
    from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
    where x."variant_id" = explode_bom.variant_id and x."status" = 'active'
    union all
    select y."variant_id", x."variant_id", x."id",
      tree.quantity * y."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0), tree.level + 1,
      tree.path || y."variant_id"
    from tree
    join "better_supabase"."boms" x on x."variant_id" = tree.variant and x."status" = 'active'
    join "better_supabase"."bom_components" y on y."bom_id" = x."id"
    where tree.level < 20 and not (y."variant_id" = any (tree.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('level', t.level, 'variantId', t.variant, 'parentVariantId', t.parent, 'bomId', t.bom,
      'quantity', "better_supabase"."production_quantity"(t.variant, t.quantity)::text,
      'made', exists (select 1 from "better_supabase"."boms" z where z."variant_id" = t.variant and z."status" = 'active'))
    order by t.path), '[]'::jsonb)
  into v_lines from tree t;
  return jsonb_build_object('variantId', explode_bom.variant_id, 'quantity', explode_bom.quantity::text, 'lines', v_lines,
    'materials', coalesce((select jsonb_agg(jsonb_build_object('variantId', m.variant, 'quantity', m.quantity::text) order by m.variant)
      from (select (e ->> 'variantId')::uuid as variant, sum((e ->> 'quantity')::numeric) as quantity
        from jsonb_array_elements(v_lines) e where not (e ->> 'made')::boolean group by 1) m), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_eval_run (
  run    uuid,
  status text DEFAULT 'completed'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."eval_runs"%rowtype;
begin
  if finish_eval_run.status not in ('completed', 'failed', 'cancelled') then
    raise exception 'status must be completed, failed or cancelled' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  update "better_supabase"."eval_runs" x set "status" = finish_eval_run.status, "summary" = "better_supabase"."eval_run_summary"(finish_eval_run.run), "finished_at" = now()
  where x."id" = finish_eval_run.run and x."status" = 'running'
  returning * into v_row;
  if not found then
    select x.* into v_row from "better_supabase"."eval_runs" x where x."id" = finish_eval_run.run;
    if not found then
      raise exception 'No eval run %', finish_eval_run.run using errcode = 'P0002', hint = 'AI_EVAL_RUN_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'dataset_id', v_row."dataset_id", 'tenant_id', v_row."tenant_id", 'prompt_name', v_row."prompt_name", 'prompt_version', v_row."prompt_version", 'model', v_row."model", 'scorers', v_row."scorers", 'status', v_row."status", 'summary', v_row."summary", 'created_at', v_row."created_at", 'finished_at', v_row."finished_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.forget_ssf_received (
  issuer text,
  jti    text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."ssf_received" x where x."issuer" = forget_ssf_received.issuer and x."jti" = forget_ssf_received.jti;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_bom (
  bom_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."boms";
begin
  select * into v_row from "better_supabase"."boms" x where x."id" = get_bom.bom_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.read'), false))) then
    raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'MANUFACTURING_BOM_NOT_FOUND';
  end if;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status", 'quantity', v_row."quantity"::text, 'note', v_row."note", 'activatedAt', v_row."activated_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'variantId', y."variant_id", 'quantity', y."quantity"::text,
      'scrapBps', y."scrap_bps", 'operationId', y."operation_id", 'position', y."position") order by y."position", y."id")
      from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"), '[]'::jsonb),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'sequence', y."sequence", 'workCenterId', y."work_center_id",
      'title', y."title", 'setupMinutes', y."setup_minutes"::text, 'runMinutesPerUnit', y."run_minutes_per_unit"::text,
      'instructionsNodeId', y."instructions_node_id", 'inspectionTemplate', y."inspection_template") order by y."sequence")
      from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id"), '[]'::jsonb)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_prescription (
  prescription_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = get_prescription.prescription_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'E_PRESCRIBING_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_field_value (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_field_value.item ->> 'tenant')::uuid;
  v_scope text := coalesce(import_field_value.item ->> 'scope', '');
  v_data jsonb := import_field_value.item -> 'data';
  v_reference jsonb := v_data -> 'subject';
  v_type text := nullif(v_data ->> 'subjectType', '');
  v_subject text := nullif(v_data ->> 'subjectId', '');
  v_field text := v_data ->> 'field';
  v_value text;
  v_definition uuid;
  v_field_type text;
  v_entity uuid;
  v_row uuid;
begin
  if jsonb_typeof(v_data -> 'value') in ('object', 'array', 'null') or (v_data -> 'value') is null then
    raise exception 'a field value needs a value of text, a number or a boolean' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_value := v_data ->> 'value';
  if v_field is null or v_field = '' then
    raise exception 'a field value needs the key of its field' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_entity := nullif(v_data ->> 'legalEntityId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'legalEntityId must be a uuid' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_reference is not null then
    if jsonb_typeof(v_reference) is distinct from 'object' then
      raise exception 'subject is { entity, key }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    select x."subject_type", x."subject_id" into v_type, v_subject
    from "better_supabase"."import_records" x
    join "better_supabase"."import_runs" u on u."id" = import_field_value.run
    where x."tenant_id" = v_tenant and x."source" = u."source"
      and x."scope" = v_scope
      and x."entity" = v_reference ->> 'entity' and x."external_key" = v_reference ->> 'key'
      and x."role" = 'primary';
    if not found then
      raise exception 'the record isn''t in the import record map; import it first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  if v_type is null or v_subject is null then
    raise exception 'a field value needs a subject: { entity, key }, or subjectType and subjectId' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_type is null or v_type <> all (array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'ledger_account', 'invoice', 'product', 'product_variant', 'rfq', 'till', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'warranty_claim', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'case', 'inspection', 'inspection_program', 'inspection_finding', 'form', 'meeting', 'meeting_decision', 'maintenance_plan', 'dam_usage_right', 'lims_sample', 'tax_code', 'production_order', 'work_center', 'bank_account', 'care_plan', 'incident', 'advisory', 'advisory_product', 'vulnerability', 'content_entry', 'document', 'customer', 'drive_node', 'organization', 'application', 'change_request', 'project', 'task']::text[]) then
    raise exception 'the entity is not a registered subject type' using errcode = '22023', hint = 'CUSTOM_FIELD_ENTITY_UNKNOWN';
  end if;
  select d."id", d."type" into v_definition, v_field_type
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = v_tenant and d."entity" = v_type and d."key" = v_field;
  if not found then
    raise exception 'no field definition with this key on the subject type' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not (case v_field_type when 'bsn' then "better_supabase"."bsb_valid_bsn"(v_value) when 'iban' then "better_supabase"."bsb_valid_iban"(v_value) when 'phone_e164' then v_value ~* '^\+[1-9][0-9]{1,14}$' else true end) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  select y."id" into v_row from "better_supabase"."field_values" y
  where y."tenant_id" = v_tenant and y."subject_type" = v_type and y."subject_id" = v_subject and y."definition_id" = v_definition
    and coalesce(y.legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_entity, '00000000-0000-0000-0000-000000000000'::uuid);
  if found then
    update "better_supabase"."field_values" set "value_text" = case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || v_tenant::text, v_value) else v_value end where "id" = v_row;
  else
    insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text", legal_entity_id)
    values (v_tenant, v_definition, v_type, v_subject, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || v_tenant::text, v_value) else v_value end, v_entity)
    returning "id" into v_row;
  end if;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', v_tenant, 'id', v_row, 'subjectType', v_type, 'subjectId', v_subject), 'field-values/' || v_row::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('subjectId', v_row::text, 'subjectType', 'field_value');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.install_field_pack (
  tenant uuid,
  pack   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_key text := install_field_pack.pack ->> 'key';
  v_version integer;
  v_entity text;
  v_fields jsonb;
  v_field jsonb;
  v_field_key text;
  v_label text;
  v_type text;
  v_required boolean;
  v_sensitive boolean;
  v_permission text;
  v_row record;
  v_id uuid;
  v_last text;
  v_rank text;
  v_created integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', install_field_pack.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if jsonb_typeof(install_field_pack.pack) is distinct from 'object' or install_field_pack.pack ->> 'apiVersion' is distinct from '1' then
    raise exception 'a field pack is an object with apiVersion 1' using errcode = '22023', hint = 'CUSTOM_FIELD_PACK_INVALID';
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_.-]{0,62}$' then
    raise exception 'a field pack needs a key in lower case' using errcode = '22023', hint = 'CUSTOM_FIELD_PACK_INVALID';
  end if;
  begin
    v_version := (install_field_pack.pack ->> 'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_version := null;
  end;
  if v_version is null or v_version < 1 then
    raise exception 'a field pack needs a version of 1 or more' using errcode = '22023', hint = 'CUSTOM_FIELD_PACK_INVALID';
  end if;
  if jsonb_typeof(install_field_pack.pack -> 'subjects') is distinct from 'object' then
    raise exception 'a field pack needs subjects: { <type>: fields }' using errcode = '22023', hint = 'CUSTOM_FIELD_PACK_INVALID';
  end if;

  for v_entity, v_fields in select s.key, s.value from jsonb_each(install_field_pack.pack -> 'subjects') s order by s.key loop
    if v_entity is null or v_entity <> all (array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'ledger_account', 'invoice', 'product', 'product_variant', 'rfq', 'till', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'warranty_claim', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'case', 'inspection', 'inspection_program', 'inspection_finding', 'form', 'meeting', 'meeting_decision', 'maintenance_plan', 'dam_usage_right', 'lims_sample', 'tax_code', 'production_order', 'work_center', 'bank_account', 'care_plan', 'incident', 'advisory', 'advisory_product', 'vulnerability', 'content_entry', 'document', 'customer', 'drive_node', 'organization', 'application', 'change_request', 'project', 'task']::text[]) then
    raise exception 'the entity is not a registered subject type' using errcode = '22023', hint = 'CUSTOM_FIELD_ENTITY_UNKNOWN';
  end if;
    if jsonb_typeof(v_fields) is distinct from 'array' then
      raise exception 'the fields of a subject type are a list' using errcode = '22023', hint = 'CUSTOM_FIELD_PACK_INVALID';
    end if;
    for v_field in select f.value from jsonb_array_elements(v_fields) f loop
      if jsonb_typeof(v_field) is distinct from 'object' then
        raise exception 'a field is an object of key, label and type' using errcode = '22023', hint = 'CUSTOM_FIELD_PACK_INVALID';
      end if;
      v_field_key := v_field ->> 'key';
      v_label := v_field ->> 'label';
      v_type := v_field ->> 'type';
      v_permission := nullif(v_field ->> 'permission', '');
      if v_field_key is null or v_field_key !~ '^[a-z][a-z0-9_.-]{0,62}$' or v_label is null or btrim(v_label) = '' then
        raise exception 'a field needs a key in lower case and a label' using errcode = '22023', hint = 'CUSTOM_FIELD_PACK_INVALID';
      end if;
      if v_type is null or v_type not in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164') then
        raise exception 'a field needs one of the custom field types' using errcode = '22023', hint = 'CUSTOM_FIELD_PACK_INVALID';
      end if;
      if (v_field ? 'required' and jsonb_typeof(v_field -> 'required') <> 'boolean') or (v_field ? 'sensitive' and jsonb_typeof(v_field -> 'sensitive') <> 'boolean') then
        raise exception 'required and sensitive are booleans' using errcode = '22023', hint = 'CUSTOM_FIELD_PACK_INVALID';
      end if;
      v_required := coalesce((v_field ->> 'required')::boolean, false);
      v_sensitive := coalesce((v_field ->> 'sensitive')::boolean, false);

      select d."id" as id, d."pack" as pack, d."pack_version" as version, d."label" as label, d."type" as type,
        d."required" as required, d."sensitive" as sensitive, d."permission" as permission
      into v_row
      from "better_supabase"."field_definitions" d
      where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity and d."key" = v_field_key;

      if not found then
        select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
        where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity;
        v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
        insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "required", "sensitive", "permission", "pack", "pack_version", "rank")
        values (install_field_pack.tenant, v_entity, v_field_key, v_label, v_type, v_required, v_sensitive, v_permission, v_key, v_version, v_rank)
        returning "id" into v_id;
        v_created := v_created + 1;
        perform "better_supabase".emit_event('field_definition.created', jsonb_build_object('organizationId', install_field_pack.tenant, 'id', v_id, 'entity', v_entity), 'custom-fields/' || v_id::text, (install_field_pack.tenant)::text, null, 'better-supabase/custom-fields');
      elsif v_row.pack is distinct from v_key then
        raise exception 'the field already exists and doesn''t belong to this pack' using errcode = '23505', hint = 'CUSTOM_FIELD_PACK_CONFLICT';
      elsif v_row.label = v_label and v_row.type = v_type and v_row.required = v_required and v_row.sensitive = v_sensitive
        and v_row.permission is not distinct from v_permission and v_row.version is not distinct from v_version then
        v_unchanged := v_unchanged + 1;
      else
        update "better_supabase"."field_definitions" set "label" = v_label, "type" = v_type, "required" = v_required, "sensitive" = v_sensitive,
          "permission" = v_permission, "pack_version" = v_version
        where "id" = v_row.id;
        v_updated := v_updated + 1;
        perform "better_supabase".emit_event('field_definition.updated', jsonb_build_object('organizationId', install_field_pack.tenant, 'id', v_row.id, 'entity', v_entity), 'custom-fields/' || v_row.id::text, (install_field_pack.tenant)::text, null, 'better-supabase/custom-fields');
      end if;
    end loop;
  end loop;
  return jsonb_build_object('pack', v_key, 'version', v_version, 'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_care_alerts (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_care_alerts.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_care_alerts.tenant is not null and coalesce(better_supabase.can('tenant', list_care_alerts.tenant, 'clinical_decision_support.read'), false))) then
    raise exception 'not allowed to read care alerts' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'kind', q."kind", 'severity', q."severity", 'source', q."source", 'ruleId', q."rule_id", 'orderIds', to_jsonb(q."order_ids"), 'message', q."message", 'details', q."details", 'fingerprint', q."fingerprint", 'status', q."status", 'decidedBy', q."decided_by", 'decidedAt', q."decided_at", 'decisionReason', q."decision_reason", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by case q."severity" when 'critical' then 0 when 'warning' then 1 else 2 end, q."created_at" desc, q."id")
    from (
      select y.* from "better_supabase"."care_alerts" y
      where y."tenant_id" = list_care_alerts.tenant
        and (v_filters ->> 'subjectType' is null or y."subject_type" = v_filters ->> 'subjectType')
        and (v_filters ->> 'subjectId' is null or y."subject_id" = v_filters ->> 'subjectId')
        and (v_filters ->> 'kind' is null or y."kind" = v_filters ->> 'kind')
        and ((v_filters ->> 'status' is null and y."status" <> 'resolved') or y."status" = v_filters ->> 'status')
      order by y."created_at" desc, y."id"
      limit least(greatest(coalesce((v_filters ->> 'limit')::int, 50), 1), 200) offset greatest(coalesce((v_filters ->> 'offset')::int, 0), 0)
    ) q
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_care_rules (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_care_rules.tenant is not null and coalesce(better_supabase.can('tenant', list_care_rules.tenant, 'clinical_decision_support.read'), false))) then
    raise exception 'not allowed to read care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'kind', y."kind", 'medicationIds', to_jsonb(y."medication_ids"), 'minDose', y."min_dose", 'maxDose', y."max_dose", 'maxPerDay', y."max_per_day", 'severity', y."severity", 'message', y."message", 'active', y."active", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."kind", y."created_at", y."id")
    from "better_supabase"."care_rules" y
    where y."tenant_id" = list_care_rules.tenant
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_hostnames (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_hostnames.tenant, 'domains.read'), false)) then
    raise exception 'You may not read this organization''s hostnames' using errcode = '42501', hint = 'DOMAIN_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg((to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end order by x."is_primary" desc, x."hostname"), '[]'::jsonb)
    from "better_supabase"."hostnames" x where x."tenant_id" = list_hostnames.tenant
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_prescriptions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_prescriptions.tenant is not null and coalesce(better_supabase.can('tenant', list_prescriptions.tenant, 'e_prescribing.read'), false))) then
    raise exception 'not allowed to read prescriptions' using errcode = '42501', hint = 'E_PRESCRIBING_FORBIDDEN';
  end if;
  if v_filters ->> 'status' is not null and v_filters ->> 'status' not in ('draft', 'signed', 'sent', 'dispensed', 'cancelled') then
    raise exception 'status is draft, signed, sent, dispensed or cancelled' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'orderId', q."order_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'prescriberId', q."prescriber_id", 'prescriberName', q."prescriber_name", 'status', q."status", 'order', q."snapshot", 'signedBy', q."signed_by", 'signedAt', q."signed_at", 'gateway', q."gateway", 'gatewayReference', q."gateway_reference", 'sentAt', q."sent_at", 'deliveryError', q."delivery_error", 'dispensedAt', q."dispensed_at", 'cancelledAt', q."cancelled_at", 'cancelReason', q."cancel_reason", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id")
    from (
      select y.* from "better_supabase"."prescriptions" y
      where y."tenant_id" = list_prescriptions.tenant
        and (v_filters ->> 'orderId' is null or y."order_id" = (v_filters ->> 'orderId')::uuid)
        and (v_filters ->> 'subjectType' is null or y."subject_type" = v_filters ->> 'subjectType')
        and (v_filters ->> 'subjectId' is null or y."subject_id" = v_filters ->> 'subjectId')
        and (v_filters ->> 'status' is null or y."status" = v_filters ->> 'status')
        and (v_filters ->> 'prescriberId' is null or y."prescriber_id" = (v_filters ->> 'prescriberId')::uuid)
      order by y."created_at" desc, y."id"
      limit least(greatest(coalesce((v_filters ->> 'limit')::int, 50), 1), 200) offset greatest(coalesce((v_filters ->> 'offset')::int, 0), 0)
    ) q
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.note_ssf_verification (
  stream_id    uuid,
  min_interval interval
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_noted boolean;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."ssf_streams" s where s."id" = note_ssf_verification.stream_id) then
    raise exception 'stream not found' using errcode = 'P0002', hint = 'SECURITY_EVENT_STREAM_NOT_FOUND';
  end if;
  update "better_supabase"."ssf_streams" s set "verified_at" = now()
  where s."id" = note_ssf_verification.stream_id
    and (s."verified_at" is null or s."verified_at" + coalesce(note_ssf_verification.min_interval, '0 seconds') <= now())
  returning true into v_noted;
  return coalesce(v_noted, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.emergency' then 'access_requests.emergency'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'access-requests.review' then 'access_requests.review'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.readRestricted' then 'activities.read_restricted'
    when 'activities.write' then 'activities.write'
    when 'advisories.publish' then 'advisories.publish'
    when 'advisories.read' then 'advisories.read'
    when 'advisories.write' then 'advisories.write'
    when 'agent-checkout.manage' then 'agent_checkout.manage'
    when 'agent-checkout.read' then 'agent_checkout.read'
    when 'agent-checkout.write' then 'agent_checkout.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.manage' then 'ai_chat.manage'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.write'
    when 'ai-schedules.manage' then 'ai_schedules.manage'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'appraisals.manage' then 'appraisals.manage'
    when 'appraisals.read' then 'appraisals.read'
    when 'appraisals.review' then 'appraisals.review'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.read' then 'audit.read'
    when 'audit.readAll' then 'audit.read'
    when 'audit.revert' then 'audit.revert'
    when 'automations.manage' then 'automations.manage'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'automations.write' then 'automations.write'
    when 'banking.import' then 'banking.import'
    when 'banking.manage' then 'banking.manage'
    when 'banking.read' then 'banking.read'
    when 'banking.reconcile' then 'banking.reconcile'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'billing.manage' then 'billing.manage'
    when 'billing.read' then 'billing.read'
    when 'billing.readAll' then 'billing.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk-actions.run' then 'bulk_actions.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'care-plans.evaluate' then 'care_plans.evaluate'
    when 'care-plans.manage' then 'care_plans.manage'
    when 'care-plans.publish' then 'care_plans.publish'
    when 'care-plans.read' then 'care_plans.read'
    when 'care-plans.write' then 'care_plans.write'
    when 'cases.close' then 'cases.close'
    when 'cases.create' then 'cases.create'
    when 'cases.manage' then 'cases.manage'
    when 'cases.read' then 'cases.read'
    when 'cases.write' then 'cases.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'clinical-decision-support.manage' then 'clinical_decision_support.manage'
    when 'clinical-decision-support.read' then 'clinical_decision_support.read'
    when 'clinical-decision-support.write' then 'clinical_decision_support.write'
    when 'collections.read' then 'collections.read'
    when 'collections.share' then 'collections.share'
    when 'collections.write' then 'collections.write'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'commissions.manage' then 'commissions.manage'
    when 'commissions.read' then 'commissions.read'
    when 'commissions.write' then 'commissions.write'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
    when 'contacts.approveSupplier' then 'contacts.approve_supplier'
    when 'contacts.manage' then 'contacts.manage'
    when 'contacts.read' then 'contacts.read'
    when 'contacts.write' then 'contacts.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.read_sensitive'
    when 'dam.read' then 'dam.read'
    when 'dam.write' then 'dam.write'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
    when 'deadlines.manage' then 'deadlines.manage'
    when 'deadlines.read' then 'deadlines.read'
    when 'deadlines.write' then 'deadlines.write'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'document-templates.manage' then 'document_templates.manage'
    when 'document-templates.read' then 'document_templates.read'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'domains.manage' then 'domains.manage'
    when 'domains.read' then 'domains.read'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'e-prescribing.manage' then 'e_prescribing.manage'
    when 'e-prescribing.read' then 'e_prescribing.read'
    when 'e-prescribing.sign' then 'e_prescribing.sign'
    when 'e-prescribing.write' then 'e_prescribing.write'
    when 'employees.read' then 'employees.read'
    when 'employees.readSensitive' then 'employees.read_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'funding.approve' then 'funding.approve'
    when 'funding.claim' then 'funding.claim'
    when 'funding.manage' then 'funding.manage'
    when 'funding.read' then 'funding.read'
    when 'funding.register' then 'funding.register'
    when 'funding.write' then 'funding.write'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'impersonation.read' then 'impersonation.read'
    when 'impersonation.revoke' then 'impersonation.revoke'
    when 'impersonation.start' then 'impersonation.start'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'incoming-webhooks.create' then 'webhooks.manage'
    when 'incoming-webhooks.delete' then 'webhooks.manage'
    when 'incoming-webhooks.read' then 'webhooks.read'
    when 'incoming-webhooks.update' then 'webhooks.manage'
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.read' then 'members.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invoices.approve' then 'invoices.approve'
    when 'invoices.collect' then 'invoices.collect'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.overrideMatch' then 'invoices.override_match'
    when 'invoices.purchase' then 'invoices.purchase'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.send' then 'invoices.send'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'leave.approve' then 'leave.approve'
    when 'leave.manage' then 'leave.manage'
    when 'leave.read' then 'leave.read'
    when 'leave.request' then 'leave.request'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'legal-entities.manage' then 'legal_entities.manage'
    when 'legal-entities.read' then 'legal_entities.read'
    when 'lims.manage' then 'lims.manage'
    when 'lims.read' then 'lims.read'
    when 'lims.write' then 'lims.write'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'maintenance.manage' then 'maintenance.manage'
    when 'maintenance.read' then 'maintenance.read'
    when 'maintenance.record' then 'maintenance.record'
    when 'manufacturing.manage' then 'manufacturing.manage'
    when 'manufacturing.produce' then 'manufacturing.produce'
    when 'manufacturing.read' then 'manufacturing.read'
    when 'manufacturing.write' then 'manufacturing.write'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
    when 'meetings.manage' then 'meetings.manage'
    when 'meetings.read' then 'meetings.read'
    when 'meetings.write' then 'meetings.write'
    when 'memory.manage' then 'memory.manage'
    when 'memory.read' then 'memory.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'numbering.assign'
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'option-sets.manage' then 'option_sets.manage'
    when 'option-sets.read' then 'option_sets.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.overrideCredit' then 'orders.override_credit'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'payroll-export.export' then 'payroll_export.export'
    when 'payroll-export.read' then 'payroll_export.read'
    when 'periods.manage' then 'periods.manage'
    when 'periods.read' then 'periods.read'
    when 'periods.write' then 'periods.write'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'referrals.manage' then 'referrals.manage'
    when 'referrals.read' then 'referrals.read'
    when 'referrals.write' then 'referrals.write'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'reviews.manage' then 'reviews.manage'
    when 'rfqs.manage' then 'rfqs.manage'
    when 'rfqs.read' then 'rfqs.read'
    when 'rfqs.write' then 'rfqs.write'
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'saved_views.read'
    when 'saved-views.share' then 'saved_views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.read' then 'segments.read'
    when 'segments.write' then 'segments.write'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_accounts.manage'
    when 'service-accounts.read' then 'service_accounts.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'tasks.manage'
    when 'tasks.read' then 'tasks.read'
    when 'tasks.write' then 'tasks.write'
    when 'tax.manage' then 'tax.manage'
    when 'tax.read' then 'tax.read'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'tills.manage' then 'tills.manage'
    when 'tills.read' then 'tills.read'
    when 'tills.write' then 'tills.write'
    when 'time-entries.approve' then 'time_entries.approve'
    when 'time-entries.manage' then 'time_entries.manage'
    when 'time-entries.read' then 'time_entries.read'
    when 'time-entries.track' then 'time_entries.track'
    when 'timeline.read' then 'timeline.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'waitlist.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'warehouse.manage' then 'warehouse.manage'
    when 'warehouse.pick' then 'warehouse.pick'
    when 'warehouse.read' then 'warehouse.read'
    when 'warranty.decide' then 'warranty.decide'
    when 'warranty.read' then 'warranty.read'
    when 'warranty.write' then 'warranty.write'
    when 'webhooks.manage' then 'webhooks.manage'
    when 'webhooks.read' then 'webhooks.read'
    when 'workflow-editor.manage' then 'workflow_editor.manage'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflow-editor.write' then 'workflow_editor.write'
    when 'workflows.manage' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.poll_ssf_events (
  stream_id  uuid,
  max_events integer,
  ack        text[]  DEFAULT '{}'::text[],
  errors     jsonb   DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
  v_limit integer := least(greatest(coalesce(poll_ssf_events.max_events, 100), 0), 1000);
  v_sets jsonb;
  v_more boolean;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."ssf_streams" s where s."id" = poll_ssf_events.stream_id;
  if not found then
    raise exception 'stream not found' using errcode = 'P0002', hint = 'SECURITY_EVENT_STREAM_NOT_FOUND';
  end if;
  if v_row."delivery_method" <> 'urn:ietf:rfc:8936' then
    raise exception 'the stream is not delivered by polling' using errcode = '22023', hint = 'SECURITY_EVENT_STREAM_NOT_POLL';
  end if;
  delete from "better_supabase"."ssf_events" q
  where q."stream_id" = v_row."id"
    and (q."jti" = any (coalesce(poll_ssf_events.ack, '{}'))
      or coalesce(poll_ssf_events.errors, '{}'::jsonb) ? q."jti");
  if v_row."status" <> 'enabled' or v_limit = 0 then
    return jsonb_build_object('sets', '{}'::jsonb, 'moreAvailable', false);
  end if;
  select count(*) > v_limit into v_more
  from (select 1 from "better_supabase"."ssf_events" q where q."stream_id" = v_row."id" limit v_limit + 1) x;
  select coalesce(jsonb_object_agg(l.jti, l.token), '{}'::jsonb) into v_sets
  from (
    select q."jti" as jti, q."token" as token from "better_supabase"."ssf_events" q
    where q."stream_id" = v_row."id"
    order by q."created_at", q."jti"
    limit v_limit
  ) l;
  return jsonb_build_object('sets', v_sets, 'moreAvailable', v_more);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_shared_signals (
  older_than interval DEFAULT NULL::interval
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_cutoff timestamptz := now() - coalesce(purge_shared_signals.older_than, '7 days'::interval);
  v_received integer;
  v_events integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."ssf_received" x where x."received_at" < v_cutoff;
  get diagnostics v_received = row_count;
  delete from "better_supabase"."ssf_events" q where q."created_at" < v_cutoff;
  get diagnostics v_events = row_count;
  return v_received + v_events;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.queue_ssf_set (
  stream_id uuid,
  jti       text,
  token     text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."ssf_streams" s where s."id" = queue_ssf_set.stream_id for update;
  if not found then
    raise exception 'stream not found' using errcode = 'P0002', hint = 'SECURITY_EVENT_STREAM_NOT_FOUND';
  end if;
  if v_row."status" = 'disabled' then
    return 'dropped';
  end if;
  if v_row."delivery_method" = 'urn:ietf:rfc:8935' and v_row."status" = 'enabled' and exists (select 1 from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id" and we."enabled") then
    perform "better_supabase"."dispatch_webhook"(v_row."endpoint_id", 'ssf.set', jsonb_build_object('set', queue_ssf_set.token), null, queue_ssf_set.jti);
    return 'dispatched';
  end if;
  insert into "better_supabase"."ssf_events" ("stream_id", "jti", "token")
  values (v_row."id", queue_ssf_set.jti, queue_ssf_set.token)
  on conflict do nothing;
  return case when v_row."delivery_method" = 'urn:ietf:rfc:8936' and v_row."status" = 'enabled' then 'queued' else 'held' end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rank_field_definition (
  definition uuid,
  rank       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_field_definition.rank is null or rank_field_definition.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'CUSTOM_FIELD_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = rank_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'CUSTOM_FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  update "better_supabase"."field_definitions" set "rank" = rank_field_definition.rank where "id" = rank_field_definition.definition;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_care_alerts (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  source       text,
  alerts       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (record_care_alerts.tenant is not null and coalesce(better_supabase.can('tenant', record_care_alerts.tenant, 'clinical_decision_support.write'), false))) then
    raise exception 'not allowed to record care alerts' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  if coalesce(trim(record_care_alerts.source), '') = '' or length(record_care_alerts.source) > 100 or record_care_alerts.source = 'built-in' then
    raise exception 'source names the engine, up to 100 characters, and is not the built-in source' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case record_care_alerts.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (record_care_alerts.subject_id)::uuid and s."organization_id"::text = record_care_alerts.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (record_care_alerts.subject_id)::uuid and s."id"::text = record_care_alerts.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (record_care_alerts.subject_id)::uuid and s."organization_id"::text = record_care_alerts.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (record_care_alerts.subject_id)::uuid and s."organization_id"::text = record_care_alerts.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (record_care_alerts.subject_id)::uuid and s."organization_id"::text = record_care_alerts.tenant::text)
      else false
    end and "better_supabase"."can_subject"(record_care_alerts.subject_type, record_care_alerts.subject_id, 'read'))) then
    raise exception 'recording needs a record of the organization' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_SUBJECT_INVALID';
  end if;
  return "better_supabase"."sync_care_alerts"(record_care_alerts.tenant, record_care_alerts.subject_type, record_care_alerts.subject_id, trim(record_care_alerts.source), record_care_alerts.alerts);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_eval_result (
  run        uuid,
  item       uuid,
  output     text    DEFAULT NULL::text,
  scores     jsonb   DEFAULT '{}'::jsonb,
  error      text    DEFAULT NULL::text,
  latency_ms integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run "better_supabase"."eval_runs"%rowtype;
  v_row "better_supabase"."eval_results"%rowtype;
  v_scores jsonb := coalesce(record_eval_result.scores, '{}'::jsonb);
begin
  select x.* into v_run from "better_supabase"."eval_runs" x where x."id" = record_eval_result.run;
  if not found then
    raise exception 'No eval run %', record_eval_result.run using errcode = 'P0002', hint = 'AI_EVAL_RUN_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'Eval run % is closed', record_eval_result.run using errcode = '55000', hint = 'AI_EVAL_RUN_CLOSED';
  end if;
  if not exists (select 1 from "better_supabase"."eval_items" x where x."id" = record_eval_result.item and x."dataset_id" = v_run."dataset_id") then
    raise exception 'No eval item %', record_eval_result.item using errcode = 'P0002', hint = 'AI_EVAL_ITEM_NOT_FOUND';
  end if;
  if jsonb_typeof(v_scores) <> 'object' then
    raise exception 'scores must be a JSON object' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  insert into "better_supabase"."eval_results" ("run_id", "item_id", "output", "scores", "passed", "error", "latency_ms")
  values (record_eval_result.run, record_eval_result.item, record_eval_result.output, v_scores,
    record_eval_result.error is null and not exists (select 1 from jsonb_each(v_scores) e where (e.value ->> 'passed') is distinct from 'true'),
    record_eval_result.error, record_eval_result.latency_ms)
  on conflict ("run_id", "item_id") do update set
    "output" = excluded."output", "scores" = excluded."scores", "passed" = excluded."passed",
    "error" = excluded."error", "latency_ms" = excluded."latency_ms", "created_at" = now()
  returning * into v_row;
  return jsonb_build_object('run_id', v_row."run_id", 'item_id', v_row."item_id", 'output', v_row."output", 'scores', v_row."scores", 'passed', v_row."passed", 'error', v_row."error", 'latency_ms', v_row."latency_ms", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_prescription_delivery (
  prescription_id uuid,
  gateway         text,
  reference       text DEFAULT NULL::text,
  error           text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
  v_gateway text := nullif(trim(record_prescription_delivery.gateway), '');
  v_reference text := nullif(trim(record_prescription_delivery.reference), '');
  v_error text := nullif(trim(record_prescription_delivery.error), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = record_prescription_delivery.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'E_PRESCRIBING_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to send prescriptions' using errcode = '42501', hint = 'E_PRESCRIBING_FORBIDDEN';
  end if;
  if v_gateway is null or length(v_gateway) > 100 then
    raise exception 'gateway is 1 to 100 characters' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  if length(coalesce(v_reference, '')) > 200 or length(coalesce(v_error, '')) > 1000 then
    raise exception 'a reference is up to 200 characters and an error up to 1000' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  if v_row."status" <> 'signed' then
    raise exception 'only a signed prescription can be sent' using errcode = '55000', hint = 'E_PRESCRIBING_STATUS';
  end if;
  if v_error is not null then
    update "better_supabase"."prescriptions" x set "gateway" = v_gateway, "delivery_error" = v_error, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('prescription.delivery_failed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.delivery_failed',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription delivery failed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  else
    update "better_supabase"."prescriptions" x set "status" = 'sent', "gateway" = v_gateway, "gateway_reference" = v_reference,
      "sent_at" = now(), "delivery_error" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('prescription.sent', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.sent',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription sent',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_prescription_dispense (
  prescription_id uuid,
  dispensed_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = record_prescription_dispense.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'E_PRESCRIBING_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to record dispensing' using errcode = '42501', hint = 'E_PRESCRIBING_FORBIDDEN';
  end if;
  if v_row."status" <> 'sent' then
    raise exception 'only a sent prescription can be dispensed' using errcode = '55000', hint = 'E_PRESCRIBING_STATUS';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'dispensed', "dispensed_at" = coalesce(record_prescription_dispense.dispensed_at, now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('prescription.dispensed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.dispensed',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription dispensed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_ssf_received (
  issuer text,
  jti    text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_new boolean;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ssf_received" ("issuer", "jti")
  values (record_ssf_received.issuer, record_ssf_received.jti)
  on conflict do nothing
  returning true into v_new;
  return coalesce(v_new, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reopen_timesheet (
  timesheet_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s where s."id" = reopen_timesheet.timesheet_id for update;
  if not found then
    raise exception 'timesheet not found' using errcode = 'P0002', hint = 'TIME_ENTRIES_TIMESHEET_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_sheet."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to reopen timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_sheet."approved_at" is null then
    raise exception 'only an approved week can be reopened' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_NOT_APPROVED';
  end if;
  update "better_supabase"."timesheets" s set "approved_at" = null, "approval_id" = null, "submitted_at" = null
    where s."id" = v_sheet."id"
    returning * into v_sheet;
  perform "better_supabase".emit_event('timesheet.reopened', jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id"), 'timesheets/' || v_sheet."id"::text, (v_sheet."tenant_id")::text, null, 'better-supabase/time-entries');
  perform better_supabase.audit_event(
    event_type => 'timesheet.reopened',
    category => 'data',
    target_type => 'timesheet',
    record_id => v_sheet."id"::text,
    summary => 'reopened a timesheet' || ' for the week of ' || v_sheet."week"::text,
    tenant => (v_sheet."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id")
  );
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_support_session (
  target      uuid,
  reason      text    DEFAULT NULL::text,
  read_only   boolean DEFAULT true,
  metadata    jsonb   DEFAULT '{}'::jsonb,
  tenant      uuid    DEFAULT NULL::uuid,
  admin_id    uuid    DEFAULT NULL::uuid,
  approved_by uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  admin uuid;
  new_id uuid;
  requested jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin) or approved_by is not null
      or not "better_supabase"."is_platform"('impersonation.start') then
      raise exception 'Not allowed to ask for a support session' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'IMPERSONATION_SELF';
  end if;
  if approved_by = admin then
    raise exception 'An admin cannot approve their own support session' using errcode = '42501', hint = 'IMPERSONATION_SELF_APPROVAL';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'IMPERSONATION_TARGET_MISSING';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'IMPERSONATION_REASON_REQUIRED';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (blocks.impersonation.options.allowWrites)' using errcode = '42501', hint = 'IMPERSONATION_WRITES_DISABLED';
  end if;
  insert into "better_supabase"."support_requests" ("admin_id", "target_user_id", "reason", "tenant_id", "read_only", "metadata", "expires_at", "approved_by", "approved_at")
  values (admin, target, coalesce(btrim(reason), ''), tenant, coalesce(read_only, true), coalesce(metadata, '{}'),
    now() + '1 hour'::interval, approved_by, case when approved_by is null then null else now() end)
  returning "id" into new_id;
  if tenant is not null and approved_by is null then
    perform "better_supabase"."open_approval"(
      tenant, 'support_request', new_id::text, 'start', jsonb_build_object('steps', '[{"approvers": {}, "required": 1}]'::jsonb, 'selfApproval', false, 'expiresIn', '1 hour', 'run', null), coalesce(btrim(reason), ''),
      jsonb_build_object('adminId', admin, 'targetUserId', target, 'readOnly', coalesce(read_only, true))
    );
  end if;
  select jsonb_build_object(
    'id', x."id",
    'admin_id', x."admin_id",
    'target_user_id', x."target_user_id",
    'reason', x."reason",
    'tenant', x."tenant_id",
    'read_only', x."read_only",
    'metadata', x."metadata",
    'requested_at', x."requested_at",
    'expires_at', x."expires_at",
    'approved_by', x."approved_by",
    'approved_at', x."approved_at",
    'session_id', x."session_id"
  ) into requested from "better_supabase"."support_requests" x where x."id" = new_id;
  return requested;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_incoming_webhook (
  endpoint      uuid,
  rotate_secret boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_secret text;
  updated "better_supabase"."incoming_webhooks";
  previous "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'INCOMING_WEBHOOK_NOT_FOUND';
  end if;
  if rotate_secret then
    v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "secret" = case when rotate_secret then null else e."secret" end,
    "secret_id" = case when rotate_secret then case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end else e."secret_id" end,
    "previous_secret" = case when rotate_secret then null else e."previous_secret" end,
    "previous_secret_id" = case when rotate_secret then null else e."previous_secret_id" end,
    "previous_secret_expires_at" = case when rotate_secret then null else e."previous_secret_expires_at" end
  where e."id" = endpoint
  returning * into updated;
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  perform "better_supabase".emit_event('incoming_webhook.token_rotated', jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'secretRotated', rotate_secret), 'organizations/' || updated."tenant"::text || '/incoming-webhooks/' || updated."id"::text, (updated."tenant")::text, null, 'better-supabase/incoming-webhooks');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.token_rotated',
    category => 'security',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'secretRotated', rotate_secret)
  );
  return jsonb_build_object('id', updated."id", 'token', token, 'secret', v_secret);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_incoming_webhook_secret (
  endpoint uuid,
  grace    interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_secret text;
  v_keep boolean := coalesce(grace > interval '0', false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'INCOMING_WEBHOOK_NOT_FOUND';
  end if;
  v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  if v_secret is null then
    raise exception 'This endpoint verifies no secret' using errcode = '22023', hint = 'INCOMING_WEBHOOK_NO_SECRET';
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "secret" = null,
    "secret_id" = case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    "previous_secret" = case when v_keep then e."secret" end,
    "previous_secret_id" = case when v_keep then e."secret_id" end,
    "previous_secret_expires_at" = case when v_keep then now() + grace end
  where e."id" = endpoint
  returning * into updated;
  delete from vault.secrets vs
  where vs.id = previous."previous_secret_id" or (not v_keep and vs.id = previous."secret_id");
  perform "better_supabase".emit_event('incoming_webhook.secret_rotated', jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id"), 'organizations/' || updated."tenant"::text || '/incoming-webhooks/' || updated."id"::text, (updated."tenant")::text, null, 'better-supabase/incoming-webhooks');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.secret_rotated',
    category => 'security',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id")
  );
  return jsonb_build_object('id', updated."id", 'secret', v_secret, 'previousSecretExpiresAt', updated."previous_secret_expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_webhook_secret (
  endpoint uuid,
  overlap  interval DEFAULT '24:00:00'::interval,
  secret   text     DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_enabled boolean;
  v_secret text := coalesce(
    rotate_webhook_secret.secret,
    'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
  );
  v_vault uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select d."tenant_id", d."enabled" into v_tenant, v_enabled
  from "better_supabase"."webhook_endpoints" d where d."id" = rotate_webhook_secret.endpoint;
  if not found then
    raise exception 'Webhook endpoint not found' using errcode = 'P0002', hint = 'WEBHOOK_ENDPOINT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if length(v_secret) < 16 then
    raise exception 'A webhook secret needs at least 16 characters' using errcode = '22023', hint = 'WEBHOOK_SECRET_TOO_SHORT';
  end if;
  delete from vault.secrets vs using "better_supabase"."webhook_endpoint_secrets" s where vs.id = s."vault_secret_id" and s."endpoint_id" = rotate_webhook_secret.endpoint and s."expires_at" <= now();
  delete from "better_supabase"."webhook_endpoint_secrets" s where s."endpoint_id" = rotate_webhook_secret.endpoint and s."expires_at" <= now();
  update "better_supabase"."webhook_endpoint_secrets" s set "expires_at" = now() + coalesce(rotate_webhook_secret.overlap, '24 hours')
  where s."endpoint_id" = rotate_webhook_secret.endpoint and s."expires_at" is null;
  v_vault := vault.create_secret(
    v_secret,
    'webhook:' || rotate_webhook_secret.endpoint::text || ':' || gen_random_uuid()::text,
    'better-supabase outgoing webhook signing secret'
  );
  insert into "better_supabase"."webhook_endpoint_secrets" ("endpoint_id", "vault_secret_id", "tenant_id")
  values (rotate_webhook_secret.endpoint, v_vault, v_tenant);
  perform "better_supabase".emit_event('webhook_endpoint.secret_rotated', jsonb_build_object('endpointId', rotate_webhook_secret.endpoint, 'organizationId', v_tenant::text), 'webhooks/' || rotate_webhook_secret.endpoint::text, (v_tenant)::text, null, 'better-supabase/webhooks');
  perform better_supabase.audit_event(
    event_type => 'webhook_endpoint.secret_rotated',
    category => 'security',
    target_type => 'webhook_endpoint',
    record_id => rotate_webhook_secret.endpoint::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('endpointId', rotate_webhook_secret.endpoint, 'organizationId', v_tenant::text)
  );
  return v_secret;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_bom (
  tenant  uuid,
  variant uuid,
  input   jsonb,
  bom_id  uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."boms";
  v_components jsonb;
  v_operations jsonb;
  v_quantity numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_bom.tenant is not null and coalesce(better_supabase.can('tenant', save_bom.tenant, 'manufacturing.write'), false))) then
    raise exception 'not allowed to change bills of materials' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if jsonb_typeof(save_bom.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = save_bom.variant and cv."tenant_id" = save_bom.tenant) then
    raise exception 'the variant isn''t a variant of this organization' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  v_quantity := coalesce(nullif(save_bom.input ->> 'quantity', '')::numeric, 1);
  if v_quantity <= 0 then
    raise exception 'the quantity must be more than zero' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  v_components := save_bom.input -> 'components';
  v_operations := coalesce(save_bom.input -> 'operations', '[]'::jsonb);
  if jsonb_typeof(v_components) is distinct from 'array' or jsonb_array_length(v_components) = 0 then
    raise exception 'a bill of materials lists at least one component' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if jsonb_typeof(v_operations) <> 'array' then
    raise exception 'operations must be an array' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e
    where jsonb_typeof(e) <> 'object' or nullif(e ->> 'variantId', '') is null
      or coalesce(nullif(e ->> 'quantity', '')::numeric, 0) <= 0
      or coalesce(nullif(e ->> 'scrapBps', '')::integer, 0) not between 0 and 10000) then
    raise exception 'each component names a variant, a quantity above zero and scrapBps from 0 to 10000' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e where (e ->> 'variantId')::uuid = save_bom.variant) then
    raise exception 'a variant can''t be a component of itself' using errcode = '22023', hint = 'MANUFACTURING_BOM_CYCLE';
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e where not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = (e ->> 'variantId')::uuid and cv."tenant_id" = save_bom.tenant)) then
    raise exception 'a component isn''t a variant of this organization' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_operations) e
    where jsonb_typeof(e) <> 'object' or coalesce(nullif(e ->> 'sequence', '')::integer, 0) <= 0
      or length(coalesce(trim(e ->> 'title'), '')) not between 1 and 200
      or coalesce(nullif(e ->> 'setupMinutes', '')::numeric, 0) < 0
      or coalesce(nullif(e ->> 'runMinutesPerUnit', '')::numeric, 0) < 0)
    or (select count(distinct e ->> 'sequence') from jsonb_array_elements(v_operations) e) <> jsonb_array_length(v_operations) then
    raise exception 'each operation has a unique sequence above zero, a title and minutes of zero or more' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_operations) e
    where not exists (select 1 from "better_supabase"."work_centers" x where x."id" = nullif(e ->> 'workCenterId', '')::uuid
      and x."tenant_id" = save_bom.tenant and x."archived_at" is null)) then
    raise exception 'no such work center in this organization' using errcode = 'P0002', hint = 'WORK_CENTER_NOT_FOUND';
  end if;
  if exists (select 1 from jsonb_array_elements(v_components) e where nullif(e ->> 'operation', '') is not null
    and not exists (select 1 from jsonb_array_elements(v_operations) p where (p ->> 'sequence')::integer = (e ->> 'operation')::integer)) then
    raise exception 'a component names an operation sequence the bill of materials doesn''t have' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_operations) e where nullif(e ->> 'instructionsNodeId', '') is not null
      and not exists (select 1 from "better_supabase"."drive_nodes" d where d."id" = (e ->> 'instructionsNodeId')::uuid and d."tenant_id" = save_bom.tenant)) then
    raise exception 'an operation''s instructions aren''t a drive node of this organization' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_operations) e where nullif(e ->> 'inspectionTemplate', '') is not null
      and not (e ->> 'inspectionTemplate') in ('internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection')) then
    raise exception 'an operation''s inspection template isn''t one of the inspection kinds' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;

  if save_bom.bom_id is null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bom:' || save_bom.variant::text, 0));
    insert into "better_supabase"."boms" ("tenant_id", "variant_id", "version", "quantity", "note", "created_by")
    values (save_bom.tenant, save_bom.variant,
      coalesce((select max(x."version") from "better_supabase"."boms" x where x."variant_id" = save_bom.variant), 0) + 1,
      v_quantity, nullif(trim(save_bom.input ->> 'note'), ''), auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."boms" x where x."id" = save_bom.bom_id and x."tenant_id" = save_bom.tenant for update;
    if not found then
      raise exception 'no such bill of materials' using errcode = 'P0002', hint = 'MANUFACTURING_BOM_NOT_FOUND';
    end if;
    if v_row."variant_id" <> save_bom.variant or v_row."status" <> 'draft' then
      raise exception 'only a draft version of the same variant changes; save a new version instead' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
    end if;
    delete from "better_supabase"."bom_components" x where x."bom_id" = v_row."id";
    delete from "better_supabase"."bom_operations" x where x."bom_id" = v_row."id";
    update "better_supabase"."boms" x set "quantity" = v_quantity, "note" = nullif(trim(save_bom.input ->> 'note'), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;

  insert into "better_supabase"."bom_operations" ("tenant_id", "bom_id", "sequence", "work_center_id", "title", "setup_minutes", "run_minutes_per_unit", "instructions_node_id", "inspection_template")
  select save_bom.tenant, v_row."id", (e ->> 'sequence')::integer, (e ->> 'workCenterId')::uuid, trim(e ->> 'title'),
    coalesce(nullif(e ->> 'setupMinutes', '')::numeric, 0), coalesce(nullif(e ->> 'runMinutesPerUnit', '')::numeric, 0),
    nullif(e ->> 'instructionsNodeId', '')::uuid, nullif(e ->> 'inspectionTemplate', '')
  from jsonb_array_elements(v_operations) e;
  insert into "better_supabase"."bom_components" ("tenant_id", "bom_id", "position", "variant_id", "quantity", "scrap_bps", "operation_id")
  select save_bom.tenant, v_row."id", e.n::integer, (e.value ->> 'variantId')::uuid, (e.value ->> 'quantity')::numeric,
    coalesce(nullif(e.value ->> 'scrapBps', '')::integer, 0),
    (select y."id" from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id" and y."sequence" = nullif(e.value ->> 'operation', '')::integer)
  from jsonb_array_elements(v_components) with ordinality e(value, n);
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'variantId', v_row."variant_id", 'version', v_row."version", 'status', v_row."status", 'quantity', v_row."quantity"::text, 'note', v_row."note", 'activatedAt', v_row."activated_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'components', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'variantId', y."variant_id", 'quantity', y."quantity"::text,
      'scrapBps', y."scrap_bps", 'operationId', y."operation_id", 'position', y."position") order by y."position", y."id")
      from "better_supabase"."bom_components" y where y."bom_id" = v_row."id"), '[]'::jsonb),
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'sequence', y."sequence", 'workCenterId', y."work_center_id",
      'title', y."title", 'setupMinutes', y."setup_minutes"::text, 'runMinutesPerUnit', y."run_minutes_per_unit"::text,
      'instructionsNodeId', y."instructions_node_id", 'inspectionTemplate', y."inspection_template") order by y."sequence")
      from "better_supabase"."bom_operations" y where y."bom_id" = v_row."id"), '[]'::jsonb)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_care_rule (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_attrs jsonb := coalesce(save_care_rule.attrs, '{}'::jsonb);
  v_row "better_supabase"."care_rules";
  v_id uuid;
  v_kind text;
  v_ids uuid[];
  v_min numeric;
  v_max numeric;
  v_day numeric;
  v_severity text;
  v_message text;
  v_active boolean;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_care_rule.tenant is not null and coalesce(better_supabase.can('tenant', save_care_rule.tenant, 'clinical_decision_support.manage'), false))) then
    raise exception 'not allowed to change care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  begin
    v_id := nullif(v_attrs ->> 'id', '')::uuid;
    v_ids := coalesce((select array_agg(distinct e.value::uuid) from jsonb_array_elements_text(case when jsonb_typeof(v_attrs -> 'medicationIds') = 'array' then v_attrs -> 'medicationIds' else '[]'::jsonb end) e), '{}');
    v_min := nullif(v_attrs ->> 'minDose', '')::numeric;
    v_max := nullif(v_attrs ->> 'maxDose', '')::numeric;
    v_day := nullif(v_attrs ->> 'maxPerDay', '')::numeric;
    v_active := coalesce((v_attrs ->> 'active')::boolean, true);
  exception when invalid_text_representation or invalid_parameter_value then
    raise exception 'ids are uuids, doses are numbers and active is true or false' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end;
  v_kind := v_attrs ->> 'kind';
  v_severity := coalesce(nullif(v_attrs ->> 'severity', ''), 'warning');
  v_message := nullif(trim(v_attrs ->> 'message'), '');
  if v_kind is null or v_kind not in ('dose_range', 'duplicate_therapy', 'interaction') then
    raise exception 'kind is dose_range, duplicate_therapy or interaction' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_severity not in ('info', 'warning', 'critical') then
    raise exception 'severity is info, warning or critical' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_message is not null and length(v_message) > 1000 then
    raise exception 'a message is up to 1000 characters' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if (select count(*) from "better_supabase"."medications" mx where mx."tenant_id" = save_care_rule.tenant and mx."id" = any(v_ids)) <> cardinality(v_ids) then
    raise exception 'medicationIds names medications that are not in the organization''s catalog' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind = 'dose_range' and (cardinality(v_ids) <> 1 or (v_min is null and v_max is null and v_day is null)) then
    raise exception 'a dose range rule names one medication and at least one bound' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind = 'dose_range' and v_min is not null and v_max is not null and v_min > v_max then
    raise exception 'minDose is at most maxDose' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind <> 'dose_range' and (v_min is not null or v_max is not null or v_day is not null) then
    raise exception 'only a dose range rule has dose bounds' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind = 'interaction' and cardinality(v_ids) <> 2 then
    raise exception 'an interaction rule names two medications' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind = 'duplicate_therapy' and cardinality(v_ids) < 2 then
    raise exception 'a duplicate therapy rule names at least two medications' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."care_rules" ("tenant_id", "kind", "medication_ids", "min_dose", "max_dose", "max_per_day", "severity", "message", "active")
      values (save_care_rule.tenant, v_kind, v_ids, v_min, v_max, v_day, v_severity, v_message, v_active)
      returning * into v_row;
      v_created := true;
    else
      update "better_supabase"."care_rules" x set "kind" = v_kind, "medication_ids" = v_ids, "min_dose" = v_min, "max_dose" = v_max,
        "max_per_day" = v_day, "severity" = v_severity, "message" = v_message, "active" = v_active, "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_care_rule.tenant
      returning * into v_row;
      if not found then
        raise exception 'no such rule' using errcode = 'P0002', hint = 'DECISION_SUPPORT_RULE_NOT_FOUND';
      end if;
    end if;
  exception when check_violation then
    raise exception 'the rule''s medications and bounds do not fit its kind' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end;
  if v_created then
    perform "better_supabase".emit_event('care_rule.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity"), 'care-rules/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_rule.created',
    category => 'configuration',
    target_type => 'care_rule',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care rule created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity")
  );
  else
    perform "better_supabase".emit_event('care_rule.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity"), 'care-rules/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_rule.updated',
    category => 'configuration',
    target_type => 'care_rule',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care rule changed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_field_definition (
  tenant    uuid,
  entity    text,
  key       text,
  label     text,
  type      text,
  sensitive boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_inserted boolean;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if save_field_definition.entity is null or save_field_definition.entity <> all (array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'ledger_account', 'invoice', 'product', 'product_variant', 'rfq', 'till', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'warranty_claim', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'case', 'inspection', 'inspection_program', 'inspection_finding', 'form', 'meeting', 'meeting_decision', 'maintenance_plan', 'dam_usage_right', 'lims_sample', 'tax_code', 'production_order', 'work_center', 'bank_account', 'care_plan', 'incident', 'advisory', 'advisory_product', 'vulnerability', 'content_entry', 'document', 'customer', 'drive_node', 'organization', 'application', 'change_request', 'project', 'task']::text[]) then
    raise exception 'the entity is not a registered subject type' using errcode = '22023', hint = 'CUSTOM_FIELD_ENTITY_UNKNOWN';
  end if;
  select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "sensitive", "rank")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false), v_rank)
  on conflict ("tenant_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id", xmax = 0 into v_id, v_inserted;
  if v_inserted then
    perform "better_supabase".emit_event('field_definition.created', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'better-supabase/custom-fields');
  else
    perform "better_supabase".emit_event('field_definition.updated', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'better-supabase/custom-fields');
  end if;
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_work_center (
  tenant         uuid,
  input          jsonb,
  work_center_id uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."work_centers";
  v_asset uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_work_center.tenant is not null and coalesce(better_supabase.can('tenant', save_work_center.tenant, 'manufacturing.manage'), false))) then
    raise exception 'not allowed to change work centers' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if jsonb_typeof(save_work_center.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if save_work_center.work_center_id is not null then
    select * into v_row from "better_supabase"."work_centers" x
    where x."id" = save_work_center.work_center_id and x."tenant_id" = save_work_center.tenant for update;
    if not found then
      raise exception 'no such work center in this organization' using errcode = 'P0002', hint = 'WORK_CENTER_NOT_FOUND';
    end if;
  end if;
  v_asset := case when save_work_center.input ? 'assetId' then nullif(save_work_center.input ->> 'assetId', '')::uuid else v_row."asset_id" end;
  if v_asset is not null and not exists (select 1 from "better_supabase"."assets" a where a."id" = v_asset and a."tenant_id" = save_work_center.tenant) then
    raise exception 'the asset isn''t an asset of this organization' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if save_work_center.work_center_id is null then
    insert into "better_supabase"."work_centers" ("tenant_id", "name", "asset_id", "hours_per_day", "cost_rate", "currency")
    values (save_work_center.tenant, trim(save_work_center.input ->> 'name'), v_asset,
      coalesce(nullif(save_work_center.input ->> 'hoursPerDay', '')::numeric, 8),
      coalesce(nullif(save_work_center.input ->> 'costRate', '')::bigint, 0),
      upper(nullif(save_work_center.input ->> 'currency', '')))
    returning * into v_row;
  else
    update "better_supabase"."work_centers" x set
      "name" = case when save_work_center.input ? 'name' then trim(save_work_center.input ->> 'name') else x."name" end,
      "asset_id" = v_asset,
      "hours_per_day" = coalesce(nullif(save_work_center.input ->> 'hoursPerDay', '')::numeric, x."hours_per_day"),
      "cost_rate" = coalesce(nullif(save_work_center.input ->> 'costRate', '')::bigint, x."cost_rate"),
      "currency" = case when save_work_center.input ? 'currency' then upper(nullif(save_work_center.input ->> 'currency', '')) else x."currency" end,
      "archived_at" = case when not save_work_center.input ? 'archived' then x."archived_at"
        when (save_work_center.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) else null end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'assetId', v_row."asset_id", 'hoursPerDay', v_row."hours_per_day"::text, 'costRate', v_row."cost_rate"::text, 'currency', v_row."currency", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_field_value (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  definition   uuid,
  value        text,
  legal_entity uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if not (case set_field_value.subject_type
    when 'drive_node' then coalesce("better_supabase"."can_subject"(set_field_value.subject_type, set_field_value.subject_id, 'fields'), false)
    else true
  end) then
    raise exception 'not allowed to set fields on this record' using errcode = '42501', hint = 'FIELD_SUBJECT_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'CUSTOM_FIELD_VALUE_INVALID';
  end if;
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text", legal_entity_id)
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || set_field_value.tenant::text, set_field_value.value) else set_field_value.value end, set_field_value.legal_entity)
  on conflict ("tenant_id", "subject_type", "subject_id", "definition_id", (coalesce(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)))
  do update set "value_text" = excluded."value_text"
  returning "id" into v_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id), 'field-values/' || v_id::text, (set_field_value.tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_incoming_webhook_enabled (
  endpoint uuid,
  enabled  boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  update "better_supabase"."incoming_webhooks" e set "enabled" = set_incoming_webhook_enabled.enabled where e."id" = endpoint;
  perform "better_supabase".emit_event('incoming_webhook.enabled_changed', jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint, 'enabled', set_incoming_webhook_enabled.enabled), 'organizations/' || tenant::text || '/incoming-webhooks/' || endpoint::text, (tenant)::text, null, 'better-supabase/incoming-webhooks');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.enabled_changed',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => endpoint::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint, 'enabled', set_incoming_webhook_enabled.enabled)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_primary_hostname (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'DOMAIN_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'DOMAIN_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "better_supabase"."hostnames" x set "is_primary" = false where x."tenant_id" = v_row."tenant_id" and x."is_primary";
  update "better_supabase"."hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('hostname.primary_changed', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.primary_changed',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_ssf_stream_status (
  id     uuid,
  status text,
  reason text DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
  v_previous text;
  v_held record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  if set_ssf_stream_status.status not in ('enabled', 'paused', 'disabled') then
    raise exception 'status is enabled, paused or disabled' using errcode = '22023', hint = 'SECURITY_EVENT_STATUS_INVALID';
  end if;
  select s."status" into v_previous from "better_supabase"."ssf_streams" s where s."id" = set_ssf_stream_status.id for update;
  if not found then
    raise exception 'stream not found' using errcode = 'P0002', hint = 'SECURITY_EVENT_STREAM_NOT_FOUND';
  end if;
  update "better_supabase"."ssf_streams" s set "status" = set_ssf_stream_status.status, "reason" = set_ssf_stream_status.reason
  where s."id" = set_ssf_stream_status.id
  returning s.* into v_row;
  if v_row."status" = 'disabled' then
    delete from "better_supabase"."ssf_events" q where q."stream_id" = v_row."id";
  elsif v_row."status" = 'enabled' and v_row."delivery_method" = 'urn:ietf:rfc:8935' and exists (select 1 from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id" and we."enabled") then
    for v_held in
      select q."jti" as jti, q."token" as token from "better_supabase"."ssf_events" q
      where q."stream_id" = v_row."id" order by q."created_at"
    loop
      perform "better_supabase"."dispatch_webhook"(v_row."endpoint_id", 'ssf.set', jsonb_build_object('set', v_held.token), null, v_held.jti);
    end loop;
    delete from "better_supabase"."ssf_events" q where q."stream_id" = v_row."id";
  end if;
  if v_previous is distinct from v_row."status" then
    perform "better_supabase".emit_event('ssf_stream.status_changed', jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant", 'status', v_row."status", 'reason', v_row."reason"), 'shared-signals/' || v_row."id", null, null, 'better-supabase/security-events');
  perform better_supabase.audit_event(
    event_type => 'ssf_stream.status_changed',
    category => 'security',
    target_type => 'ssf_stream',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant", 'status', v_row."status", 'reason', v_row."reason")
  );
  end if;
  return v_previous;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sign_prescription (
  prescription_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
  v_order "better_supabase"."medication_orders";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = sign_prescription.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'E_PRESCRIBING_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.sign'), false))) then
    raise exception 'not allowed to sign prescriptions' using errcode = '42501', hint = 'E_PRESCRIBING_FORBIDDEN';
  end if;
  if v_row."prescriber_id" is distinct from auth.uid() or auth.uid() is null then
    raise exception 'only the prescriber signs a prescription' using errcode = '42501', hint = 'E_PRESCRIBING_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft can be signed' using errcode = '55000', hint = 'E_PRESCRIBING_STATUS';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = v_row."tenant_id" and x."id" = v_row."order_id";
  if not found or v_order."status" <> 'active' or (v_order."ends_on" is not null and v_order."ends_on" < (now() at time zone 'UTC')::date) then
    raise exception 'the order is no longer active' using errcode = '55000', hint = 'E_PRESCRIBING_STATUS';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_prescription_sign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."prescriptions" x set "status" = 'signed', "signed_by" = auth.uid(), "signed_at" = now(),
    "snapshot" = "better_supabase"."prescription_order_snapshot"(v_row."tenant_id", v_row."order_id"), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('prescription.signed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.signed',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription signed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_prescription_sign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ssf_stream (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  return (select jsonb_build_object(
    'id', s."id",
    'tenant', s."tenant",
    'receiver', s."receiver",
    'audience', to_jsonb(s."audience"),
    'description', s."description",
    'eventsRequested', to_jsonb(s."events_requested"),
    'eventsDelivered', to_jsonb(s."events_delivered"),
    'method', s."delivery_method",
    'endpointUrl', (select we."url" from "better_supabase"."webhook_endpoints" we where we."id" = s."endpoint_id"),
    'status', s."status",
    'reason', s."reason",
    'createdAt', s."created_at",
    'updatedAt', s."updated_at"
  ) from "better_supabase"."ssf_streams" s where s."id" = ssf_stream.id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ssf_streams (
  receiver text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
    'id', s."id",
    'tenant', s."tenant",
    'receiver', s."receiver",
    'audience', to_jsonb(s."audience"),
    'description', s."description",
    'eventsRequested', to_jsonb(s."events_requested"),
    'eventsDelivered', to_jsonb(s."events_delivered"),
    'method', s."delivery_method",
    'endpointUrl', (select we."url" from "better_supabase"."webhook_endpoints" we where we."id" = s."endpoint_id"),
    'status', s."status",
    'reason', s."reason",
    'createdAt', s."created_at",
    'updatedAt', s."updated_at"
  ) order by s."created_at")
    from "better_supabase"."ssf_streams" s where s."receiver" = ssf_streams.receiver
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ssf_streams_for_event (
  tenant     text,
  event_type text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s."id", 'audience', to_jsonb(s."audience")) order by s."created_at")
    from "better_supabase"."ssf_streams" s
    where s."status" <> 'disabled'
      and ssf_streams_for_event.event_type = any (s."events_delivered")
      and (s."tenant" is null or s."tenant" = ssf_streams_for_event.tenant)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_support_session (
  target    uuid,
  reason    text     DEFAULT NULL::text,
  ttl       interval DEFAULT '00:30:00'::interval,
  read_only boolean  DEFAULT true,
  metadata  jsonb    DEFAULT '{}'::jsonb,
  tenant    uuid     DEFAULT NULL::uuid,
  admin_id  uuid     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  admin uuid;
  session_id uuid;
  started jsonb;
  approval_id uuid;
  approver uuid;
begin
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin)
      or not "better_supabase"."is_platform"('impersonation.start') then
      raise exception 'Not allowed to start a support session' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'IMPERSONATION_SELF';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'IMPERSONATION_TARGET_MISSING';
  end if;
  if ttl <= interval '0' or ttl > '4 hours'::interval then
    raise exception 'ttl must be between 0 and %', '4 hours' using errcode = '22023', hint = 'IMPERSONATION_TTL';
  end if;
  -- Viewing the app as platform staff would hand the admin that staff's reach.
  if (exists (
    select 1 from auth.users u
    where u.id = target and jsonb_typeof(u.raw_app_meta_data -> 'platform_permissions') = 'array'
      and jsonb_array_length(u.raw_app_meta_data -> 'platform_permissions') > 0
  ) or exists (
    select 1 from "better_supabase"."platform_roles" a
    where a."user_id" = target
  )) then
    raise exception 'A support session cannot target platform staff' using errcode = '42501', hint = 'IMPERSONATION_TARGET_PLATFORM';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (blocks.impersonation.options.allowWrites)' using errcode = '42501', hint = 'IMPERSONATION_WRITES_DISABLED';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'IMPERSONATION_REASON_REQUIRED';
  end if;
  -- A second admin approved this start: the approval is consumed below.
  select x."id", x."approved_by" into approval_id, approver
  from "better_supabase"."support_requests" x
  where x."admin_id" = admin
    and x."target_user_id" = target
    and x."tenant_id" is not distinct from tenant
    and (not x."read_only" or coalesce(read_only, true))
    and x."approved_by" is not null
    and x."approved_by" <> admin
    and x."session_id" is null
    and x."expires_at" > now()
  order by x."approved_at" desc
  limit 1
  for update;
  if approval_id is null then
    raise exception 'A second admin must approve this support session (approve_support_request)' using errcode = '42501', hint = 'IMPERSONATION_APPROVAL_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_support_start"(uuid, uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using admin, target, reason, metadata;
    end if;
  end;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = 'admin'
  where s."admin_id" = admin and s."ended_at" is null;
  insert into "better_supabase"."support_sessions" ("admin_id", "target_user_id", "reason", "tenant_id", "read_only", "expires_at", "metadata")
  values (admin, target, coalesce(reason, ''), tenant, read_only, now() + ttl, coalesce(metadata, '{}'))
  returning "id" into session_id;
  update "better_supabase"."support_requests" x set "session_id" = session_id where x."id" = approval_id;
  select jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_user_id",
    'reason', s."reason",
    'tenant', s."tenant_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) into started from "better_supabase"."support_sessions" s where s."id" = session_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_start"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform "better_supabase".emit_event('support_session.started', jsonb_build_object('sessionId', started ->> 'id', 'adminId', started ->> 'admin_id', 'targetUserId', started ->> 'target_user_id', 'reason', started ->> 'reason', 'readOnly', (started ->> 'read_only')::boolean, 'expiresAt', started ->> 'expires_at', 'organizationId', started ->> 'tenant'), 'support-sessions/' || session_id, (tenant)::text, 'support_session.started:' || session_id, 'better-supabase/impersonation');
  perform better_supabase.audit_event(
    event_type => 'support_session.started',
    category => 'security',
    target_type => 'user',
    record_id => target::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only, 'request_id', approval_id, 'approved_by', approver),
    idempotency_key => 'support_session.started:' || session_id,
    actor_id => admin,
    support_session => session_id,
    impersonated_by => admin,
    impersonation_reason => reason
  );
  return started;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_timesheet (
  tenant uuid,
  week   date,
  note   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
  v_seconds bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', submit_timesheet.tenant, 'time_entries.track'), false) then
    raise exception 'not allowed to submit a timesheet here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me and x."ended_at" is null
      and "better_supabase"."time_week"(x."started_at") = v_week
  ) then
    raise exception 'stop the running timer before submitting this week' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_TIMER_RUNNING';
  end if;
  insert into "better_supabase"."timesheets" ("tenant_id", "user_id", "week")
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict ("tenant_id", "user_id", "week") do nothing;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = submit_timesheet.tenant and s."user_id" = v_me and s."week" = v_week
    for update;
  if v_sheet."approved_at" is not null then
    raise exception 'this week is already approved' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_APPROVED';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  if v_approval."status" = 'pending' then
    raise exception 'this week is already waiting for approval' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_SUBMITTED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_timesheet_submit"(uuid, uuid, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date)', v_hook::oid::regproc)
        using v_sheet."id", submit_timesheet.tenant, v_week;
    end if;
  end;
  select coalesce(sum(extract(epoch from x."ended_at" - x."started_at")), 0)::bigint into v_seconds
    from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me
      and "better_supabase"."time_week"(x."started_at") = v_week;
  v_request := "better_supabase"."open_approval"(
    submit_timesheet.tenant, 'timesheet', v_sheet."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"time_entries.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, submit_timesheet.note,
    jsonb_build_object('userId', v_me, 'week', v_week, 'seconds', v_seconds)
  );
  update "better_supabase"."timesheets" s
  set "approval_id" = (v_request ->> 'id')::uuid, "note" = submit_timesheet.note, "submitted_at" = now()
  where s."id" = v_sheet."id"
  returning * into v_sheet;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  perform "better_supabase".emit_event('timesheet.submitted', jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id"), 'timesheets/' || v_sheet."id"::text, (v_sheet."tenant_id")::text, null, 'better-supabase/time-entries');
  perform better_supabase.audit_event(
    event_type => 'timesheet.submitted',
    category => 'data',
    target_type => 'timesheet',
    record_id => v_sheet."id"::text,
    summary => 'submitted a timesheet' || ' for the week of ' || v_sheet."week"::text,
    tenant => (v_sheet."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_timesheet_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_sheet."id";
    end if;
  end;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.support_target_claims (
  target uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  base jsonb;
begin
  select jsonb_build_object(
    'user_id', u.id,
    'authentication_method', 'support',
    'claims', jsonb_strip_nulls(jsonb_build_object(
      'sub', u.id::text,
      'aud', 'authenticated',
      'role', coalesce(nullif(u.role, ''), 'authenticated'),
      'email', u.email,
      'phone', nullif(u.phone, ''),
      'app_metadata', coalesce(u.raw_app_meta_data, '{}'),
      'user_metadata', coalesce(u.raw_user_meta_data, '{}'),
      'is_anonymous', u.is_anonymous,
      'aal', 'aal1',
      'amr', '[]'::jsonb,
      'session_id', gen_random_uuid()
    ))
  ) into base
  from auth.users u where u.id = target;
  if base is null then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'IMPERSONATION_TARGET_MISSING';
  end if;
  return base -> 'claims';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sync_care_alerts (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  source       text,
  alerts       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_item jsonb;
  v_row "better_supabase"."care_alerts";
  v_seen text[] := '{}';
  v_kind text;
  v_severity text;
  v_message text;
  v_fingerprint text;
  v_rule uuid;
  v_orders uuid[];
  v_details jsonb;
begin
  if jsonb_typeof(sync_care_alerts.alerts) is distinct from 'array' then
    raise exception 'alerts is an array' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  for v_item in select e.value from jsonb_array_elements(sync_care_alerts.alerts) e loop
    v_kind := coalesce(nullif(v_item ->> 'kind', ''), 'other');
    v_severity := coalesce(nullif(v_item ->> 'severity', ''), 'warning');
    v_message := nullif(trim(v_item ->> 'message'), '');
    if v_kind not in ('dose_range', 'duplicate_therapy', 'interaction', 'allergy', 'other') then
      raise exception 'kind is dose_range, duplicate_therapy, interaction, allergy or other' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
    end if;
    if v_severity not in ('info', 'warning', 'critical') then
      raise exception 'severity is info, warning or critical' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
    end if;
    if v_message is null or length(v_message) > 1000 then
      raise exception 'an alert needs a message of up to 1000 characters' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
    end if;
    v_fingerprint := coalesce(nullif(trim(v_item ->> 'fingerprint'), ''), md5(v_kind || '|' || v_message));
    if length(v_fingerprint) > 200 then
      raise exception 'a fingerprint is up to 200 characters' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
    end if;
    v_details := case when jsonb_typeof(v_item -> 'details') = 'object' then v_item -> 'details' else null end;
    begin
      v_rule := nullif(v_item ->> 'ruleId', '')::uuid;
      v_orders := coalesce((select array_agg(e.value::uuid) from jsonb_array_elements_text(case when jsonb_typeof(v_item -> 'orderIds') = 'array' then v_item -> 'orderIds' else '[]'::jsonb end) e), '{}');
    exception when invalid_text_representation then
      raise exception 'ruleId and orderIds are uuids' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
    end;
    select * into v_row from "better_supabase"."care_alerts" x
    where x."tenant_id" = sync_care_alerts.tenant and x."subject_type" = sync_care_alerts.subject_type and x."subject_id" = sync_care_alerts.subject_id
      and x."fingerprint" = v_fingerprint and x."status" <> 'resolved'
    for update;
    if found then
      update "better_supabase"."care_alerts" x set "kind" = v_kind, "severity" = v_severity, "message" = v_message, "rule_id" = v_rule,
        "order_ids" = v_orders, "details" = v_details, "updated_at" = now()
      where x."id" = v_row."id";
    else
      insert into "better_supabase"."care_alerts" ("tenant_id", "subject_type", "subject_id", "kind", "severity", "source", "rule_id", "order_ids", "message", "details", "fingerprint")
      values (sync_care_alerts.tenant, sync_care_alerts.subject_type, sync_care_alerts.subject_id, v_kind, v_severity, sync_care_alerts.source, v_rule, v_orders, v_message, v_details, v_fingerprint)
      returning * into v_row;
      perform "better_supabase".emit_event('care_alert.raised', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status"), 'care-alerts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_alert.raised',
    category => 'data',
    target_type => 'care_alert',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care alert raised',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status")
  );
    end if;
    v_seen := array_append(v_seen, v_fingerprint);
  end loop;
  for v_row in
    update "better_supabase"."care_alerts" x set "status" = 'resolved', "updated_at" = now()
    where x."tenant_id" = sync_care_alerts.tenant and x."subject_type" = sync_care_alerts.subject_type and x."subject_id" = sync_care_alerts.subject_id
      and x."source" = sync_care_alerts.source and x."status" <> 'resolved' and not (x."fingerprint" = any(v_seen))
    returning x.*
  loop
    perform "better_supabase".emit_event('care_alert.resolved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status"), 'care-alerts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_alert.resolved',
    category => 'data',
    target_type => 'care_alert',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care alert resolved',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status")
  );
  end loop;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'subjectType', y."subject_type", 'subjectId', y."subject_id", 'kind', y."kind", 'severity', y."severity", 'source', y."source", 'ruleId', y."rule_id", 'orderIds', to_jsonb(y."order_ids"), 'message', y."message", 'details', y."details", 'fingerprint', y."fingerprint", 'status', y."status", 'decidedBy', y."decided_by", 'decidedAt', y."decided_at", 'decisionReason', y."decision_reason", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by case y."severity" when 'critical' then 0 when 'warning' then 1 else 2 end, y."created_at", y."id")
    from "better_supabase"."care_alerts" y
    where y."tenant_id" = sync_care_alerts.tenant and y."subject_type" = sync_care_alerts.subject_type and y."subject_id" = sync_care_alerts.subject_id and y."status" <> 'resolved'
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_field_value (
  value_id uuid,
  value    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_subject text;
  v_definition uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select v."tenant_id", v."subject_type", v."subject_id", v."definition_id"
  into v_tenant, v_type, v_subject, v_definition
  from "better_supabase"."field_values" v where v."id" = update_field_value.value_id;
  if not found then
    raise exception 'field value not found' using errcode = 'P0002', hint = 'CUSTOM_FIELD_VALUE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if not (case v_type
    when 'drive_node' then coalesce("better_supabase"."can_subject"(v_type, v_subject, 'fields'), false)
    else true
  end) then
    raise exception 'not allowed to set fields on this record' using errcode = '42501', hint = 'FIELD_SUBJECT_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(update_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(update_field_value.value) when 'phone_e164' then update_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'CUSTOM_FIELD_VALUE_INVALID';
  end if;
  update "better_supabase"."field_values" set "value_text" = case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || v_tenant::text, update_field_value.value) else update_field_value.value end
  where "id" = update_field_value.value_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', v_tenant, 'id', update_field_value.value_id, 'subjectType', v_type, 'subjectId', v_subject), 'field-values/' || update_field_value.value_id::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', update_field_value.value_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_incoming_webhook (
  endpoint         uuid,
  name             text  DEFAULT NULL::text,
  metadata         jsonb DEFAULT NULL::jsonb,
  verify           text  DEFAULT NULL::text,
  signature_header text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_verify text;
  v_secret text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'INCOMING_WEBHOOK_NOT_FOUND';
  end if;
  if name is not null and btrim(name) = '' then
    raise exception 'An endpoint needs a name' using errcode = '22023', hint = 'INCOMING_WEBHOOK_NAME_REQUIRED';
  end if;
  if metadata is not null and jsonb_typeof(metadata) <> 'object' then
    raise exception 'metadata must be a JSON object' using errcode = '22023', hint = 'INCOMING_WEBHOOK_METADATA_INVALID';
  end if;
  v_verify := coalesce(verify, previous."verify");
  if v_verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'INCOMING_WEBHOOK_VERIFY_UNKNOWN';
  end if;
  if v_verify <> previous."verify" then
    v_secret := case v_verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "name" = coalesce(update_incoming_webhook.name, e."name"),
    "metadata" = coalesce(update_incoming_webhook.metadata, e."metadata"),
    "verify" = v_verify,
    "secret" = case when v_verify = previous."verify" then e."secret" else null end,
    "secret_id" = case when v_verify = previous."verify" then e."secret_id" else case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end end,
    "previous_secret" = case when v_verify = previous."verify" then e."previous_secret" end,
    "previous_secret_id" = case when v_verify = previous."verify" then e."previous_secret_id" end,
    "previous_secret_expires_at" = case when v_verify = previous."verify" then e."previous_secret_expires_at" end,
    "signature_header" = case v_verify
      when 'hmac-sha256' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-signature')
      when 'shared-secret' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-webhook-secret')
    end
  where e."id" = endpoint
  returning * into updated;
  if v_verify <> previous."verify" then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  perform "better_supabase".emit_event('incoming_webhook.updated', jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'name', updated."name", 'verify', updated."verify"), 'organizations/' || updated."tenant"::text || '/incoming-webhooks/' || updated."id"::text, (updated."tenant")::text, null, 'better-supabase/incoming-webhooks');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.updated',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'name', updated."name", 'verify', updated."verify")
  );
  return jsonb_build_object('id', updated."id", 'tenant', updated."tenant", 'name', updated."name",
    'verify', updated."verify", 'secret', v_secret, 'signatureHeader', updated."signature_header",
    'metadata', updated."metadata");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_ssf_stream (
  id    uuid,
  patch jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SECURITY_EVENT_FORBIDDEN';
  end if;
  update "better_supabase"."ssf_streams" s set
    "description" = case when update_ssf_stream.patch ? 'description' then update_ssf_stream.patch ->> 'description' else s."description" end,
    "events_requested" = case when update_ssf_stream.patch ? 'eventsRequested'
      then array(select jsonb_array_elements_text(update_ssf_stream.patch -> 'eventsRequested')) else s."events_requested" end,
    "events_delivered" = case when update_ssf_stream.patch ? 'eventsDelivered'
      then array(select jsonb_array_elements_text(update_ssf_stream.patch -> 'eventsDelivered')) else s."events_delivered" end
  where s."id" = update_ssf_stream.id
  returning s.* into v_row;
  if not found then
    return null;
  end if;
  if update_ssf_stream.patch ? 'endpointUrl' and v_row."endpoint_id" is not null then
    update "better_supabase"."webhook_endpoints" we set "url" = update_ssf_stream.patch ->> 'endpointUrl'
    where we."id" = v_row."endpoint_id";
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant",
    'receiver', v_row."receiver",
    'audience', to_jsonb(v_row."audience"),
    'description', v_row."description",
    'eventsRequested', to_jsonb(v_row."events_requested"),
    'eventsDelivered', to_jsonb(v_row."events_delivered"),
    'method', v_row."delivery_method",
    'endpointUrl', (select we."url" from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id"),
    'status', v_row."status",
    'reason', v_row."reason",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.verify_hostname (
  id    uuid,
  actor uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'DOMAIN_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."tenant_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'DOMAIN_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "better_supabase"."hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'DOMAIN_TAKEN';
  end if;
  update "better_supabase"."hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('hostname.verified', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.verified',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => verify_hostname.actor
  );
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$function$;
