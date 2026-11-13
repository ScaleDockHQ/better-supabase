SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.update_deals (
  changes jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_deal uuid;
  v_field text;
  v_row "better_supabase"."deals";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_seen jsonb := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_deals.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { dealId, field, value }' using errcode = '22023', hint = 'DEAL_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_deals.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_deal := (v_change ->> 'dealId')::uuid;
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null for update;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      -- expectedVersion is the updatedAt the caller read; every change of the
      -- batch compares to the row as it was before the batch.
      if not v_seen ? v_deal::text then
        v_seen := v_seen || jsonb_build_object(v_deal::text, v_row."updated_at");
      end if;
      if v_change ? 'expectedVersion' and (v_seen ->> v_deal::text)::timestamptz is distinct from (v_change ->> 'expectedVersion')::timestamptz then
        raise exception 'the deal changed since it was read' using errcode = 'BS409', hint = 'STALE_WRITE';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not (case (v_change -> 'value' ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"((v_change -> 'value' ->> 'type'), (v_change -> 'value' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
      end if;
      if v_field in ('amount', 'existingAmount') and jsonb_typeof(v_change -> 'value') = 'object' then
        if upper(v_change -> 'value' ->> 'currency') is distinct from v_row."currency" then
          raise exception 'an amount must be in the deal''s currency' using errcode = '22023', hint = 'DEAL_CURRENCY_MISMATCH';
        end if;
        v_change := jsonb_set(v_change, '{value}', v_change -> 'value' -> 'amount');
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_deal, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."deals" x set "name" = trim(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'motion' then
        update "better_supabase"."deals" x set "motion" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'priority' then
        update "better_supabase"."deals" x set "priority" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'ownerId' then
        update "better_supabase"."deals" x set "owner_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'product' then
        update "better_supabase"."deals" x set "product" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'seats' then
        update "better_supabase"."deals" x set "seats" = (v_change -> 'value' #>> '{}')::integer where x."id" = v_deal returning * into v_row;
      when 'amount' then
        update "better_supabase"."deals" x set "amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'existingAmount' then
        update "better_supabase"."deals" x set "existing_amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'currency' then
        update "better_supabase"."deals" x set "currency" = upper(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'valuePeriod' then
        update "better_supabase"."deals" x set "value_period" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'amountSource' then
        update "better_supabase"."deals" x set "amount_source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'stageId' then
        update "better_supabase"."deals" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'probability' then
        update "better_supabase"."deals" x set "probability" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_deal returning * into v_row;
      when 'forecast' then
        update "better_supabase"."deals" x set "forecast_category" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'closeOn' then
        update "better_supabase"."deals" x set "expected_close_on" = (v_change -> 'value' #>> '{}')::date where x."id" = v_deal returning * into v_row;
      when 'nextStep' then
        update "better_supabase"."deals" x set "next_step" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'nextAt' then
        update "better_supabase"."deals" x set "next_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_deal returning * into v_row;
      when 'nextKind' then
        update "better_supabase"."deals" x set "next_kind" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'flags' then
        update "better_supabase"."deals" x set "flags" = coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(v_change -> 'value') when 'array' then v_change -> 'value' else '[]' end)), '{}') where x."id" = v_deal returning * into v_row;
      when 'source' then
        update "better_supabase"."deals" x set "source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'note' then
        update "better_supabase"."deals" x set "note" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'lostReason' then
        update "better_supabase"."deals" x set "lost_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'company' then
        update "better_supabase"."deals" x set "company_type" = v_change -> 'value' ->> 'type', "company_id" = v_change -> 'value' ->> 'id' where x."id" = v_deal returning * into v_row;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'DEAL_FIELD_UNKNOWN';
      end case;
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('dealId', v_deal, 'field', v_field));
      v_touched := array_append(v_touched, v_deal);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_deal, v_field;
    end if;
  end;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('dealId', v_change ->> 'dealId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."deals" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('deal.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'dealId')::uuid = v_row."id")), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_maintenance_requests (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."maintenance_requests";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
  v_seen jsonb := '{}';
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_maintenance_requests.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { maintenanceRequestId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_maintenance_requests.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'maintenanceRequestId')::uuid;
      if not exists (select 1 from "better_supabase"."maintenance_requests" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      -- expectedVersion is the updatedAt the caller read. Every change of the
      -- batch compares to the row as it was before the batch, which an earlier
      -- change of the same item has already moved on.
      if not v_seen ? v_item::text then
        select x."updated_at" into v_was from "better_supabase"."maintenance_requests" x where x."id" = v_item for update;
        v_seen := v_seen || jsonb_build_object(v_item::text, v_was);
      end if;
      if v_change ? 'expectedVersion' and (v_seen ->> v_item::text)::timestamptz is distinct from (v_change ->> 'expectedVersion')::timestamptz then
        raise exception 'the work item changed since it was read' using errcode = 'BS409', hint = 'STALE_WRITE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."maintenance_requests" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."maintenance_requests" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."maintenance_requests" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."maintenance_requests" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."maintenance_requests" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."maintenance_requests" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."maintenance_requests" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."maintenance_requests" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."maintenance_requests" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."maintenance_requests" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."maintenance_requests" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."maintenance_requests" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."maintenance_requests" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."maintenance_requests" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."maintenance_requests" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'maintenance_request', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'maintenance_request' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
      when 'unit_id' then
        update "better_supabase"."maintenance_requests" x set "unit_id" = (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('unit_id', v_change -> 'value')))."unit_id" where x."id" = v_item;
      when 'lease_id' then
        update "better_supabase"."maintenance_requests" x set "lease_id" = (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('lease_id', v_change -> 'value')))."lease_id" where x."id" = v_item;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_request_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_maintenance_requests.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('maintenanceRequestId', v_change ->> 'maintenanceRequestId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."maintenance_requests" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('maintenance_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'maintenanceRequestId')::uuid = v_row."id")), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_work_items (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."work_items";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
  v_seen jsonb := '{}';
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
      end if;
      -- expectedVersion is the updatedAt the caller read. Every change of the
      -- batch compares to the row as it was before the batch, which an earlier
      -- change of the same item has already moved on.
      if not v_seen ? v_item::text then
        select x."updated_at" into v_was from "better_supabase"."work_items" x where x."id" = v_item for update;
        v_seen := v_seen || jsonb_build_object(v_item::text, v_was);
      end if;
      if v_change ? 'expectedVersion' and (v_seen ->> v_item::text)::timestamptz is distinct from (v_change ->> 'expectedVersion')::timestamptz then
        raise exception 'the work item changed since it was read' using errcode = 'BS409', hint = 'STALE_WRITE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."work_items" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."work_items" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."work_items" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."work_items" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."work_items" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."work_items" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."work_items" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."work_items" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."work_items" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."work_items" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."work_items" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."work_items" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."work_items" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."work_items" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."work_items" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."work_items" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."tenant_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      if update_work_items.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row."id")), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;
