SET local check_function_bodies = off;

DROP FUNCTION "api"."add_invoice_charge"(uuid, bigint, text, text);

DROP FUNCTION "api"."remove_invoice_charge"(uuid);

DROP FUNCTION "api"."request_approval"(uuid, text, text, text, text, jsonb, text);

DROP FUNCTION "api"."reverse_invoice_payment"(uuid, text);

DROP FUNCTION "api"."void_invoice"(uuid, text);

DROP FUNCTION "api"."write_off_invoice"(uuid, text);

DROP FUNCTION "better_supabase"."add_invoice_charge"(uuid, bigint, text, text);

DROP FUNCTION "better_supabase"."open_approval"(uuid, text, text, text, jsonb, text, jsonb);

DROP FUNCTION "better_supabase"."remove_invoice_charge"(uuid);

DROP FUNCTION "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, text);

DROP FUNCTION "better_supabase"."reverse_invoice_payment"(uuid, text);

DROP FUNCTION "better_supabase"."void_invoice"(uuid, text);

DROP FUNCTION "better_supabase"."write_off_invoice"(uuid, text);

ALTER TABLE "better_supabase"."approval_policies"
  ADD COLUMN "description" text;

CREATE OR REPLACE FUNCTION api.add_invoice_charge (
  invoice     uuid,
  amount      bigint,
  currency    text,
  description text,
  actor       jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."add_invoice_charge"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.remove_invoice_charge (
  charge uuid,
  actor  jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_invoice_charge"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.request_approval (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  action       text,
  reason       text  DEFAULT NULL::text,
  payload      jsonb DEFAULT '{}'::jsonb,
  fingerprint  text  DEFAULT NULL::text,
  policy       jsonb DEFAULT NULL::jsonb,
  requested_by uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."request_approval"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.reverse_invoice_payment (
  payment uuid,
  reason  text  DEFAULT NULL::text,
  actor   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reverse_invoice_payment"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.void_invoice (
  invoice uuid,
  reason  text,
  actor   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."void_invoice"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.write_off_invoice (
  invoice uuid,
  reason  text  DEFAULT NULL::text,
  actor   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."write_off_invoice"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.add_invoice_charge (
  invoice     uuid,
  amount      bigint,
  currency    text,
  description text,
  actor       jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_charge uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = add_invoice_charge.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice takes charges' using errcode = '55000', hint = 'INVOICE_NOT_CHARGEABLE';
  end if;
  if coalesce(add_invoice_charge.amount, 0) <= 0 then
    raise exception 'a charge has a positive amount' using errcode = '22023', hint = 'INVOICE_CHARGE_INVALID';
  end if;
  if upper(add_invoice_charge.currency) is distinct from v_row."currency" then
    raise exception 'a charge must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
  end if;
  if add_invoice_charge.actor is not null then
    if jsonb_typeof(add_invoice_charge.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(add_invoice_charge.actor ->> 'ip', '')::inet, nullif(add_invoice_charge.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(add_invoice_charge.actor::text, ''), true);
  insert into "better_supabase"."invoice_charges" ("tenant_id", "invoice_id", "amount", "currency", "description", "created_by")
  values (v_row."tenant_id", v_row."id", add_invoice_charge.amount, v_row."currency", nullif(trim(add_invoice_charge.description), ''), auth.uid())
  returning "id" into v_charge;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.charged', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', v_charge, 'amount', add_invoice_charge.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.charged',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice charged',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', v_charge, 'amount', add_invoice_charge.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible (
  request_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_step jsonb;
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_eligible.request_id;
  if not found or v_me is null or v_req."status" <> 'pending' then
    return false;
  end if;
  if exists (
    select 1 from "better_supabase"."approval_decisions" x
    where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_me
  ) then
    return false;
  end if;
  if v_me = v_req."requested_by" then
    if v_req."policy" ->> 'mode' = 'confirm' then
      return true;
    end if;
    if not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
      return false;
    end if;
  end if;
  if v_req."subject_type" = 'ai_tool_approval' then
    return "better_supabase"."ai_tool_approval_approvable"(v_req."subject_id");
  end if;
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
    ))
    or (v_approvers ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = v_approvers ->> 'team' and tm."user_id" = v_me))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status"::text <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_req."tenant_id" and mm."user_id" = v_me
    )))) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
    ))
    or (v_approvers ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = v_approvers ->> 'team' and tm."user_id" = v_me))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status"::text <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_req."tenant_id" and mm."user_id" = v_me
    )))) then
      return true;
    end if;
  end if;
  return exists (
      select 1 from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step"
        and x."decision" = 'delegated' and x."delegate_to" = v_me
    );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_notify (
  request_id uuid,
  kind       text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_approvers jsonb;
  v_permission text;
  v_recipients uuid[] := '{}';
  v_claims text;
  v_note jsonb;
  v_hook regprocedure;
  v_extra jsonb;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_notify.request_id;
  if not found then
    return;
  end if;
  if approval_notify.kind in ('approved', 'rejected', 'expired') then
    v_recipients := array[v_req."requested_by"];
    v_permission := null;
  else
    v_approvers := v_req."policy" -> 'steps' -> v_req."step" -> case when approval_notify.kind = 'escalated' then 'escalateTo' else 'approvers' end;
    v_permission := v_approvers ->> 'permission';
    v_recipients := array(
      select x::uuid from jsonb_array_elements_text(coalesce(v_approvers -> 'users', '[]'::jsonb)) x
      union
      select m."user_id" from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
      union
      select tm."user_id" from "better_supabase"."team_members" tm
      where tm."team_id"::text = v_approvers ->> 'team'
      union
      select (select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status"::text <> 'offboarded'
      limit 1) where coalesce((v_approvers ->> 'manager')::boolean, false)
      union
      select x."delegate_to" from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
    );
    if approval_notify.kind = 'delegated' then
      v_recipients := array(
        select x."delegate_to" from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
        order by x."created_at" desc limit 1
      );
      v_permission := null;
    end if;
    -- Approvers who already decided this step aren't asked again.
    v_recipients := array(
      select u from unnest(v_recipients) u
      where not exists (
        select 1 from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = u
      )
    );
  end if;
  if cardinality(v_recipients) = 0 and v_permission is null then
    return;
  end if;
  v_note := jsonb_build_object(
      'type', 'approval.' || approval_notify.kind,
      'tenant', v_req."tenant_id",
      'actor', coalesce(auth.uid(), v_req."requested_by"),
      'subject_type', v_req."subject_type",
      'subject_id', v_req."subject_id",
      'summary', left(v_req."action" || coalesce(': ' || v_req."reason", ''), 140),
      'recipients', to_jsonb(v_recipients),
      'permission', v_permission,
      'exclude', case when coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) or approval_notify.kind in ('approved', 'rejected', 'expired') then '[]'::jsonb else jsonb_build_array(v_req."requested_by") end,
      'include_actor', approval_notify.kind in ('approved', 'rejected', 'expired'),
      'key', 'approval.' || approval_notify.kind || ':' || v_req."id"::text || ':' || v_req."step"::text || ':' || extract(epoch from now())::bigint::text,
      'data', jsonb_build_object('requestId', v_req."id", 'action', v_req."action", 'step', v_req."step")
    );
  v_hook := to_regprocedure('"public"."approval_notification"(uuid, text, jsonb)');
  if v_hook is not null then
    execute format('select %s($1, $2, $3)', v_hook::oid::regproc) into v_extra
      using v_req."id", approval_notify.kind, v_note;
    if v_extra is null then
      return;
    end if;
    v_note := v_note || (v_extra - 'data') || jsonb_build_object('data', coalesce(v_note -> 'data', '{}'::jsonb) || coalesce(v_extra -> 'data', '{}'::jsonb));
  end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(v_note);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_policy (
  subject_type text,
  action       text
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select coalesce(case approval_policy.subject_type || ':' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    when 'customer:discount' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'customer:refund' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'customer:export' then '{"steps":[{"approvers":{"manager":true},"required":1}],"selfApproval":false,"expiresIn":null,"run":null,"mode":"confirm"}'::jsonb
    when 'drive_node:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'eve_tool_call:add_note' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'workflow_run:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    else null::jsonb
  end, case '*:' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    else null::jsonb
  end)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_policy_tighten (
  base jsonb,
  own  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_step jsonb;
  v_who jsonb;
  v_mode text := coalesce(approval_policy_tighten.own ->> 'mode', 'authorize');
  v_steps jsonb := coalesce(approval_policy_tighten.own -> 'steps', '[]'::jsonb);
  v_level integer;
  v_expires interval;
begin
  if jsonb_typeof(approval_policy_tighten.own) is distinct from 'object'
    or jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20
    or v_mode not in ('confirm', 'authorize')
    or (approval_policy_tighten.own ? 'selfApproval' and jsonb_typeof(approval_policy_tighten.own -> 'selfApproval') <> 'boolean')
    or (approval_policy_tighten.own ? 'managerOf' and jsonb_typeof(approval_policy_tighten.own -> 'managerOf') <> 'string')
    or (approval_policy_tighten.own ->> 'expiresIn' is not null and (approval_policy_tighten.own ->> 'expiresIn')::interval <= interval '0') then
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and v_who -> 'manager' <> 'true'::jsonb)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb)
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
  end loop;
  v_expires := (approval_policy_tighten.own ->> 'expiresIn')::interval;
  if approval_policy_tighten.base is null then
    return jsonb_build_object(
      'steps', v_steps,
      'selfApproval', coalesce((approval_policy_tighten.own ->> 'selfApproval')::boolean, false),
      'expiresIn', v_expires::text, 'run', null
    ) || case when v_mode = 'confirm' then '{"mode": "confirm"}'::jsonb else '{}'::jsonb end
      || case when approval_policy_tighten.own ? 'managerOf' then jsonb_build_object('managerOf', approval_policy_tighten.own -> 'managerOf') else '{}'::jsonb end;
  end if;
  v_level := greatest(
    case when coalesce(approval_policy_tighten.base ->> 'mode', 'authorize') = 'authorize' and jsonb_array_length(coalesce(approval_policy_tighten.base -> 'steps', '[]'::jsonb)) > 0 then 2 when coalesce(approval_policy_tighten.base ->> 'mode', 'authorize') = 'confirm' then 1 else 0 end,
    case when v_mode = 'authorize' and jsonb_array_length(v_steps) > 0 then 2 when v_mode = 'confirm' then 1 else 0 end
  );
  return approval_policy_tighten.base || jsonb_build_object(
    'steps', coalesce(approval_policy_tighten.base -> 'steps', '[]'::jsonb) || v_steps,
    'selfApproval', coalesce((approval_policy_tighten.base ->> 'selfApproval')::boolean, false) and coalesce((approval_policy_tighten.own ->> 'selfApproval')::boolean, false),
    'expiresIn', least((approval_policy_tighten.base ->> 'expiresIn')::interval, v_expires)::text,
    'mode', case when v_level = 1 then 'confirm' else 'authorize' end
  ) || case when approval_policy_tighten.own ? 'managerOf' then jsonb_build_object('managerOf', approval_policy_tighten.own -> 'managerOf') else '{}'::jsonb end;
exception
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'policy must be { steps: [{ approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo }], mode, selfApproval, expiresIn, managerOf }' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_approval_policies (
  tenant       uuid,
  subject_type text    DEFAULT NULL::text,
  page_size    integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_approval_policies.tenant, 'approvals.read'), false)) then
    raise exception 'reading approval policies needs approvals.read' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'action', x."action", 'effect', x."effect", 'name', x."name", 'conditions', x."conditions", 'mode', x."mode", 'steps', x."steps", 'selfApproval', x."self_approval", 'expiresIn', x."expires_in"::text, 'enabled', x."enabled", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('description', x."description")) order by x."subject_type", x."action", x."created_at", x."id")
    from (
      select * from "better_supabase"."approval_policies" y
      where (y."tenant_id" = list_approval_policies.tenant or (list_approval_policies.tenant is null and y."tenant_id" is null))
        and (list_approval_policies.subject_type is null or y."subject_type" = list_approval_policies.subject_type)
      order by y."subject_type", y."action", y."created_at", y."id"
      limit least(greatest(coalesce(list_approval_policies.page_size, 100), 1), 500)
    ) x
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_approval (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  action       text,
  policy       jsonb,
  reason       text,
  payload      jsonb,
  requested_by uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_policy jsonb := open_approval.policy;
  v_requester uuid := coalesce(open_approval.requested_by, auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_approval_request"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action;
    end if;
  end;
  if exists (select 1 from jsonb_array_elements(coalesce(v_policy -> 'steps', '[]'::jsonb)) e where e.value -> 'required' = '"all"'::jsonb) then
    v_policy := jsonb_set(v_policy, '{steps}', (
      select jsonb_agg(case when e.value -> 'required' = '"all"'::jsonb
        then e.value || jsonb_build_object('approvers', jsonb_build_object('users', h.users), 'required', jsonb_array_length(h.users), 'permission', e.value -> 'approvers' ->> 'permission')
        else e.value end order by e.ordinality)
      from jsonb_array_elements(v_policy -> 'steps') with ordinality e
      left join lateral (
        select coalesce(jsonb_agg(distinct to_jsonb(u.id::text)), '[]'::jsonb) as users
        from (select m."user_id" from "public"."memberships" m
        where m."organization_id" = open_approval.tenant
          and coalesce(better_supabase.can_user(m."user_id", 'tenant', open_approval.tenant, (e.value -> 'approvers' ->> 'permission')), false)) as u(id)
        where u.id is not null and (u.id is distinct from v_requester or coalesce((v_policy ->> 'selfApproval')::boolean, false))
      ) h on e.value -> 'required' = '"all"'::jsonb
    ));
    if exists (select 1 from jsonb_array_elements(v_policy -> 'steps') e where e.value -> 'required' = '0'::jsonb) then
      raise exception 'nobody holds the permission a step asks every holder of' using errcode = '22023', hint = 'APPROVAL_APPROVERS_EMPTY';
    end if;
  end if;
  insert into "better_supabase"."approval_requests" ("tenant_id", "subject_type", "subject_id", "action", "policy", "requested_by", "reason", "payload", "expires_at")
  values (open_approval.tenant, open_approval.subject_type, open_approval.subject_id, open_approval.action, v_policy, v_requester, open_approval.reason, coalesce(open_approval.payload, '{}'::jsonb),
    case when open_approval.policy ->> 'expiresIn' is not null then now() + (open_approval.policy ->> 'expiresIn')::interval end)
  on conflict ("subject_type", "subject_id", "action") where "status" = 'pending' do nothing
  returning * into v_req;
  if not found then
    raise exception 'this record already has a pending request for that action' using errcode = '23505', hint = 'APPROVAL_PENDING';
  end if;
  perform "better_supabase".emit_event('approval.requested', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.requested',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'requested' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  perform "better_supabase"."approval_notify"(v_req."id", 'requested');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_approval_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_req."id";
    end if;
  end;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_invoice_charge (
  charge uuid,
  actor  jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_amount bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."invoices" x join "better_supabase"."invoice_charges" c on c."invoice_id" = x."id"
  where c."id" = remove_invoice_charge.charge and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false))
  for update of x;
  if v_row."id" is null then
    raise exception 'no such charge on an invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_CHARGE_NOT_FOUND';
  end if;
  if v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice changes its charges' using errcode = '55000', hint = 'INVOICE_NOT_CHARGEABLE';
  end if;
  if remove_invoice_charge.actor is not null then
    if jsonb_typeof(remove_invoice_charge.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(remove_invoice_charge.actor ->> 'ip', '')::inet, nullif(remove_invoice_charge.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(remove_invoice_charge.actor::text, ''), true);
  delete from "better_supabase"."invoice_charges" c where c."id" = remove_invoice_charge.charge
  returning c."amount" into v_amount;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.charge_removed', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', remove_invoice_charge.charge, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.charge_removed',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice charge_removed',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', remove_invoice_charge.charge, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_approval (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  action       text,
  reason       text  DEFAULT NULL::text,
  payload      jsonb DEFAULT '{}'::jsonb,
  fingerprint  text  DEFAULT NULL::text,
  policy       jsonb DEFAULT NULL::jsonb,
  requested_by uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_policy jsonb := "better_supabase"."approval_effective_policy"(request_approval.tenant, request_approval.subject_type, request_approval.action, coalesce(request_approval.payload, '{}'::jsonb));
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_result jsonb;
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if request_approval.policy is not null and not v_service then
    raise exception 'only the service role files a request under its own policy' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if request_approval.requested_by is not null and not v_service and request_approval.requested_by is distinct from auth.uid() then
    raise exception 'only the service role files a request for another user' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if request_approval.policy is not null then
    v_policy := "better_supabase"."approval_policy_tighten"(v_policy, request_approval.policy);
  end if;
  if v_policy is null then
    raise exception 'no approval policy for this subject type and action' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  if not (v_service or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and (case when request_approval.subject_type = 'drive_node' then coalesce(case when request_approval.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((request_approval.subject_id)::uuid, 'editor') end, false) else case request_approval.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    else false
  end end))) then
    raise exception 'not allowed to request approval for this record' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if not (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0) then
    raise exception 'no approval is required for this request' using errcode = '22023', hint = 'APPROVAL_NOT_REQUIRED';
  end if;
  if request_approval.fingerprint is not null and request_approval.fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'fingerprint must be a lowercase hex SHA-256' using errcode = '22023', hint = 'APPROVAL_FINGERPRINT_INVALID';
  end if;
  v_result := "better_supabase"."open_approval"(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload, coalesce(request_approval.requested_by, auth.uid()));
  if request_approval.fingerprint is not null then
    update "better_supabase"."approval_requests" x set "fingerprint" = request_approval.fingerprint
    where x."id" = (v_result ->> 'id')::uuid and x."status" = 'pending';
  end if;
  select * into v_req from "better_supabase"."approval_requests" x where x."id" = (v_result ->> 'id')::uuid;
  if found then
    return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
  end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reverse_invoice_payment (
  payment uuid,
  reason  text  DEFAULT NULL::text,
  actor   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_meta jsonb;
  v_amount bigint;
  v_reversal uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select y."metadata" into v_meta from "better_supabase"."ledger_transactions" y
  where y."id" = reverse_invoice_payment.payment and y."reference_type" = 'invoices';
  select * into v_row from "better_supabase"."invoices" x where x."id" = (v_meta ->> 'invoiceId')::uuid and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.manage'), false)) for update;
  if v_meta is null or v_row."id" is null then
    raise exception 'no such payment on an invoice you can manage' using errcode = 'P0002', hint = 'INVOICE_PAYMENT_NOT_FOUND';
  end if;
  if coalesce(v_meta ->> 'method', '') = any ('{stripe,order}'::text[]) then
    raise exception 'a payment provider''s payment is refunded through the provider, not reversed' using errcode = '55000', hint = 'INVOICE_PAYMENT_PROVIDER';
  end if;
  if (v_meta ->> 'reversal')::boolean is true
    or exists (select 1 from "better_supabase"."ledger_transactions" y where y."reverses" = reverse_invoice_payment.payment) then
    raise exception 'this payment is a reversal or is already reversed' using errcode = '55000', hint = 'INVOICE_PAYMENT_REVERSED';
  end if;
  if reverse_invoice_payment.actor is not null then
    if jsonb_typeof(reverse_invoice_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(reverse_invoice_payment.actor ->> 'ip', '')::inet, nullif(reverse_invoice_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(reverse_invoice_payment.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(reverse_invoice_payment.reason), ''), ''), true);
  v_amount := coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), 0);
  v_reversal := "better_supabase"."ledger_post"(v_row."tenant_id", 'invoice.payment_reversal',
    (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
      from "better_supabase"."ledger_entries" e where e."transaction_id" = reverse_invoice_payment.payment),
    'invoices', v_row."id"::text, null, null, null,
    (select y."metadata" from "better_supabase"."ledger_transactions" y where y."id" = reverse_invoice_payment.payment) || jsonb_strip_nulls(jsonb_build_object('reversal', true, 'reason', nullif(trim(reverse_invoice_payment.reason), ''))),
    reverse_invoice_payment.payment);
  v_amount := v_amount - coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), 0);
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.payment_reversed', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', reverse_invoice_payment.payment, 'reversalId', v_reversal, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(reverse_invoice_payment.reason), '')), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.payment_reversed',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice payment_reversed',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', reverse_invoice_payment.payment, 'reversalId', v_reversal, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(reverse_invoice_payment.reason), ''))
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_approval_policy (
  tenant uuid,
  policy jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."approval_policies"%rowtype;
  v_row "better_supabase"."approval_policies"%rowtype;
  v_type text;
  v_action text;
  v_conditions jsonb;
  v_steps jsonb;
  v_step jsonb;
  v_fields jsonb;
  v_effect text;
  v_who jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_approval_policy.tenant, 'approvals.manage'), false)) then
    raise exception 'managing approval policies needs approvals.manage' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if jsonb_typeof(save_approval_policy.policy) is distinct from 'object' then
    raise exception 'policy must be an object' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if save_approval_policy.policy ? 'id' then
    select * into v_old from "better_supabase"."approval_policies" x
    where x."id" = (save_approval_policy.policy ->> 'id')::uuid and x."tenant_id" is not distinct from save_approval_policy.tenant
    for update;
    if not found then
      raise exception 'approval policy not found' using errcode = 'P0002', hint = 'APPROVAL_POLICY_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(save_approval_policy.policy ->> 'subjectType', v_old."subject_type");
  v_action := coalesce(save_approval_policy.policy ->> 'action', v_old."action");
  v_effect := case when save_approval_policy.policy ? 'effect' then nullif(save_approval_policy.policy ->> 'effect', '') else v_old."effect" end;
  if v_type is null or v_action is null or not (exists (
      select 1 from jsonb_array_elements('[{"subjectType":"*","action":"quote.send","effects":["money-movement"]},{"subjectType":"customer","action":"discount","effects":[]},{"subjectType":"customer","action":"refund","effects":[]},{"subjectType":"customer","action":"export","effects":[]},{"subjectType":"drive_node","action":"approve","effects":[]},{"subjectType":"eve_tool_call","action":"add_note","effects":[]},{"subjectType":"workflow_run","action":"approve","effects":[]}]'::jsonb) f
      where (v_type = '*' or f.value ->> 'subjectType' in (v_type, '*'))
        and (v_action = '*' or f.value ->> 'action' in (v_action, '*'))
        and (v_effect is null or f.value -> 'effects' ? v_effect)
    )) then
    raise exception 'a tenant policy tightens an options.policies entry, and there is none for this subject type, action and effect' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  v_conditions := case when save_approval_policy.policy ? 'conditions' then nullif(save_approval_policy.policy -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'APPROVAL_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  v_steps := coalesce(save_approval_policy.policy -> 'steps', v_old."steps", '[]'::jsonb);
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20 then
    raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and v_who -> 'manager' <> 'true'::jsonb)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb)
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
  end loop;
  if coalesce(save_approval_policy.policy ->> 'mode', v_old."mode"::text, 'authorize') not in ('confirm', 'authorize') then
    raise exception 'mode must be confirm or authorize' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."approval_policies" ("tenant_id", "subject_type", "action", "name", "conditions", "effect", "mode", "steps", "self_approval", "expires_in", "enabled", "created_by", "description")
    values (save_approval_policy.tenant, v_type, v_action, btrim(save_approval_policy.policy ->> 'name'), v_conditions, v_effect,
      coalesce(save_approval_policy.policy ->> 'mode', 'authorize'), v_steps,
      coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, false), (save_approval_policy.policy ->> 'expiresIn')::interval,
      coalesce((save_approval_policy.policy ->> 'enabled')::boolean, true), auth.uid(), (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) -> 'description')))."description")
    returning * into v_row;
  else
    update "better_supabase"."approval_policies" x set
      "subject_type" = v_type,
      "action" = v_action,
      "name" = coalesce(btrim(save_approval_policy.policy ->> 'name'), x."name"),
      "conditions" = v_conditions,
      "effect" = v_effect,
      "mode" = coalesce(save_approval_policy.policy ->> 'mode', x."mode"),
      "steps" = v_steps,
      "self_approval" = coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, x."self_approval"),
      "expires_in" = case when save_approval_policy.policy ? 'expiresIn' then (save_approval_policy.policy ->> 'expiresIn')::interval else x."expires_in" end,
      "enabled" = coalesce((save_approval_policy.policy ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now(), "description" = case when (save_approval_policy.policy -> 'fields') ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', (save_approval_policy.policy -> 'fields') -> 'description')))."description" else x."description" end
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('approval_policy.saved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.saved',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'saved approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'action', v_row."action", 'effect', v_row."effect", 'name', v_row."name", 'conditions', v_row."conditions", 'mode', v_row."mode", 'steps', v_row."steps", 'selfApproval', v_row."self_approval", 'expiresIn', v_row."expires_in"::text, 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('description', v_row."description"));
exception
  when invalid_text_representation or invalid_datetime_format or not_null_violation or check_violation then
    raise exception 'policy has an invalid name, mode, expiry or flag' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.void_invoice (
  invoice uuid,
  reason  text,
  actor   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = void_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.manage'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can manage' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'issued') or v_row."paid_total" <> 0 or v_row."credited_total" <> 0 then
    raise exception 'an invoice with payments or credits is credited, not voided' using errcode = '55000', hint = 'INVOICE_NOT_VOIDABLE';
  end if;
  if void_invoice.actor is not null then
    if jsonb_typeof(void_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(void_invoice.actor ->> 'ip', '')::inet, nullif(void_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(void_invoice.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(void_invoice.reason), ''), ''), true);
  update "better_supabase"."invoices" x set "status" = 'void', "voided_at" = now(),
    "void_reason" = nullif(trim(void_invoice.reason), ''), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.voided', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reason', v_row."void_reason"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.voided',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice voided',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reason', v_row."void_reason")
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.write_off_invoice (
  invoice uuid,
  reason  text  DEFAULT NULL::text,
  actor   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if write_off_invoice.actor is not null then
    if jsonb_typeof(write_off_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(write_off_invoice.actor ->> 'ip', '')::inet, nullif(write_off_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(write_off_invoice.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(write_off_invoice.reason), ''), ''), true);
  update "better_supabase"."invoices" x set "status" = 'uncollectible', "updated_at" = now()
  where x."id" = write_off_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.manage'), false)) and x."status" in ('issued', 'partially_paid')
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'only an open invoice you can manage is written off' using errcode = '55000', hint = 'INVOICE_NOT_OPEN';
  end if;
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.uncollected', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(write_off_invoice.reason), '')), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.uncollected',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice uncollected',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(write_off_invoice.reason), ''))
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

REVOKE ALL ON FUNCTION "api"."add_invoice_charge"(uuid, bigint, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."add_invoice_charge"(uuid, bigint, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_invoice_charge"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_invoice_charge"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reverse_invoice_payment"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reverse_invoice_payment"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."void_invoice"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."void_invoice"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."write_off_invoice"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."write_off_invoice"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_invoice_charge"(uuid, bigint, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_invoice_charge"(uuid, bigint, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approval_policy_tighten"(jsonb, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."open_approval"(uuid, text, text, text, jsonb, text, jsonb, uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."remove_invoice_charge"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_invoice_charge"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."request_approval"(uuid, text, text, text, text, jsonb, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reverse_invoice_payment"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reverse_invoice_payment"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."void_invoice"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."void_invoice"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."write_off_invoice"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."write_off_invoice"(uuid, text, jsonb) TO "authenticated", "service_role";
