SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.begin_import_session (
  run uuid
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."begin_import_session"($1) $function$;

CREATE OR REPLACE FUNCTION api.import_run()
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_run"() $function$;

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
  select * into v_row from "better_supabase"."invoices" x where x."id" = add_invoice_charge.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
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
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_charge', v_charge::text);
  end if;
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
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
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
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
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
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(v_note);
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approve_expense_report (
  report_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_lines jsonb;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."expense_reports" x
    where x."id" = approve_expense_report.report_id and x."approved_at" is null and x."cancelled_at" is null
    for update;
  if not found then
    return;
  end if;
  select jsonb_agg(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense', 'expenses:category:' || c."key" || ':' || v_row."currency", 'Expenses: ' || c."name", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', q.total) order by c."key")
    into v_lines
  from (
    select l."category_id" as category, sum(l."amount") as total
    from "better_supabase"."expense_lines" l where l."report_id" = v_row."id" group by l."category_id"
  ) q join "better_supabase"."expense_categories" c on c."id" = q.category;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)));
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.approved', v_lines,
    'expenses', v_row."id"::text, left('Expenses: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':approved', null,
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"));
  update "better_supabase"."expense_reports" x set "approved_at" = now(), "approval_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('expense_report', v_row."id"::text);
  end if;
  perform "better_supabase".emit_event('expense_report.approved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.approved',
    category => 'billing',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'approved an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_conversation (
  conversation uuid,
  assignee     uuid,
  team         uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_before uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = assign_conversation.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.assign'), false) or (coalesce(assignee = (select auth.uid()), false) and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false))) then
    raise exception 'not allowed to assign this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if assignee is not null and not coalesce(better_supabase.can_user(assignee, 'tenant', v_conv."tenant_id", 'inbox.read'), false) then
    raise exception 'the assignee cannot read this inbox' using errcode = '22023', hint = 'INBOX_ASSIGNEE_INVALID';
  end if;
  v_before := v_conv."assignee_id";
  update "better_supabase"."inbox_conversations" set
    "assignee_id" = assign_conversation.assignee,
    "team_id" = coalesce(assign_conversation.team, "team_id")
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from assignee then
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'assigned', (select auth.uid()), jsonb_build_object('from', v_before, 'to', assign_conversation.assignee));
    perform "better_supabase".emit_event('inbox_conversation.assigned', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status", 'previousAssigneeId', v_before), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    if assignee is not null then
      insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_conv."id", v_conv."tenant_id", assign_conversation.assignee)
    on conflict do nothing;
    end if;
    if assignee is not null and assignee is distinct from (select auth.uid()) then
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.assigned',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', v_conv."subject",
        'recipients', to_jsonb(array[assignee]),
        'key', 'inbox.assigned:' || v_conv."id"::text || ':' || assignee::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id")
      ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_shift (
  shift_id uuid,
  user_id  uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = assign_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = assign_shift.user_id;
  if found and v_row."status" = 'assigned' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", assign_shift.user_id, v_row."id");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", assign_shift.user_id;
    end if;
  end;
  begin
    insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", assign_shift.user_id, 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  exception when exclusion_violation then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end;
  perform "better_supabase".emit_event('shift_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.created',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
  if v_shift."status" = 'published' then
    if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.created',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'You are on a shift',
      'recipients', jsonb_build_array(v_row."user_id"),
      'key', 'shift_assignment.created:' || v_shift."id"::text || ':' || v_row."user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set blocks.audit.options.restricted to true.';
  end if;
  -- imports.audit 'summary' (ADR 0141): the run audits per entity at its end.
  if current_setting('better_supabase.import_audit', true) = 'summary' and better_supabase.import_run() is not null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    actor_id := auth.uid();
    actor_kind := null;
    actor_label := null;
    ip := null;
    user_agent := null;
    session_id := null;
    request_id := null;
    scope := null;
    if (select auth.jwt()) -> 'act' is not null or impersonated_by is distinct from auth.uid() then
      support_session := null;
      impersonated_by := null;
      impersonation_reason := null;
    end if;
  elsif actor_id is null then
    actor_id := coalesce(auth.uid(), better_supabase.acting_member());
  end if;
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event.idempotency_key
      and l."organization_id" is not distinct from audit_event.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    coalesce(audit_event.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end),
    coalesce(audit_event.impersonation_reason, auth.jwt() -> 'act' ->> 'reason'),
    coalesce(audit_event.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end),
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when better_supabase.import_run() is not null then 'integration'
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event_trusted (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set blocks.audit.options.restricted to true.';
  end if;
  -- imports.audit 'summary' (ADR 0141): the run audits per entity at its end.
  if current_setting('better_supabase.import_audit', true) = 'summary' and better_supabase.import_run() is not null then
    return null;
  end if;
  actor_id := coalesce(actor_id, auth.uid());
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event_trusted.idempotency_key
      and l."organization_id" is not distinct from audit_event_trusted.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    coalesce(audit_event_trusted.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end),
    coalesce(audit_event_trusted.impersonation_reason, auth.jwt() -> 'act' ->> 'reason'),
    coalesce(audit_event_trusted.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end),
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when better_supabase.import_run() is not null then 'integration'
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event_trusted.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_row_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  entry_id "better_supabase"."audit_events"."id"%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
  changed_values jsonb;
  row_tenant uuid;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  path_value text;
  path_step jsonb;
begin
  -- An import run with imports.audit 'summary' audits one entry per entity at
  -- its end instead of one per row (ADR 0141).
  if current_setting('better_supabase.import_audit', true) = 'summary' and better_supabase.import_run() is not null then
    return null;
  end if;
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  row_tenant := case when row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end;
  -- A child row without a tenant column: follow the foreign-key path
  -- registered through tenant_path, then the tenant function.
  if row_tenant is null and entry.tenant_path is not null then
    path_value := row_data ->> (entry.tenant_path ->> 'column');
    for path_step in select * from jsonb_array_elements(entry.tenant_path -> 'steps') loop
      exit when path_value is null;
      execute format('select %I::text from %s where %I::text = $1 limit 1',
        path_step ->> 'read', path_step ->> 'table', path_step ->> 'ref')
        into path_value using path_value;
    end loop;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is null and entry.tenant_function is not null then
    execute format('select %s($1)::text', (entry.tenant_function::regprocedure)::oid::regproc) into path_value using row_data;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  old_row := old_row - entry.ignore;
  new_row := new_row - entry.ignore;
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_columns
    from jsonb_each(new_row) n
    where n.value is distinct from old_row -> n.key;
    if changed_columns is null then
      return null;
    end if;
  end if;
  -- Redacted columns stay in changed, with their values masked.
  old_row := old_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where old_row ? k), '{}');
  new_row := new_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where new_row ? k), '{}');
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    lower(tg_op),
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when better_supabase.import_run() is not null then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    (select o."name"::text from "public"."organizations" o where o."id" = row_tenant),
    row_data ->> entry.label_column,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
  )
  returning "id" into entry_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.begin_import_session (
  run uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_status text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can begin an import session' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  select r."status"::text into v_status from "better_supabase"."import_runs" r where r."id" = begin_import_session.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_status <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  perform set_config('better_supabase.import_run', begin_import_session.run::text, true);
  perform set_config('better_supabase.correlation_id', 'import:' || begin_import_session.run::text, true);
  perform set_config('better_supabase.import_events', '{"customer.imported":"tag","customer.synced":"emit"}', true);
  perform set_config('better_supabase.import_audit', 'summary', true);
  return begin_import_session.run;
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
    if better_supabase.import_run() is null then
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
      if better_supabase.import_run() is null then
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

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_case()
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
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'case', new."kind_id"::text);
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
    and p."subject_type" = 'case'
    and p."scope_id" is not distinct from new."kind_id"::text;
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
        using 'case', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'case' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'case', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'case', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'case',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'case', new."id"::text, new."stage_id";
    end if;
  end;
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
      if better_supabase.import_run() is null then
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

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_maintenance_request()
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
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'maintenance_request', new."team_id"::text);
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
    and p."subject_type" = 'maintenance_request'
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
        using 'maintenance_request', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'maintenance_request' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'maintenance_request', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'maintenance_request',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'maintenance_request', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
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
      if better_supabase.import_run() is null then
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

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_drive_node()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."document_status" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'drive_node', new."id"::text, null::text, new."document_status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."document_status" is not distinct from old."document_status" then
    return new;
  end if;
  if new."document_status" is null or not (old."document_status" is null and new."document_status"::text = 'draft') and not (case old."document_status"::text when 'draft' then new."document_status"::text = any ('{in_review}'::text[]) when 'in_review' then new."document_status"::text = any ('{draft,effective}'::text[]) when 'effective' then new."document_status"::text = any ('{obsolete}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  -- The approvals module sets better_supabase.approval to the request it
  -- just approved before it makes the transition.
  if (case old."document_status"::text when 'in_review' then new."document_status"::text = any ('{effective}'::text[]) else false end)
    and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    and not exists (
      select 1 from "better_supabase"."approval_requests" a
      where a."id"::text = nullif(current_setting('better_supabase.approval', true), '')
        and a."status" = 'approved'
        and a."subject_type" = 'drive_node'
        and a."subject_id" = new."id"::text
    ) then
    raise exception 'that status change needs an approved request' using errcode = '42501', hint = 'STATE_APPROVAL_REQUIRED';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'drive_node', new."id"::text, old."document_status"::text, new."document_status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', new."id"::text, 'from', old."document_status"::text, 'to', new."document_status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/drive_node/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
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
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."state" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'work_item', new."id"::text, null::text, new."state"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."state" is not distinct from old."state" then
    return new;
  end if;
  if not (case old."state"::text when 'triage' then new."state"::text = any ('{backlog,unstarted,started,completed,canceled}'::text[]) when 'backlog' then new."state"::text = any ('{triage,unstarted,started,completed,canceled}'::text[]) when 'unstarted' then new."state"::text = any ('{triage,backlog,started,completed,canceled}'::text[]) when 'started' then new."state"::text = any ('{triage,backlog,unstarted,completed,canceled}'::text[]) when 'completed' then new."state"::text = any ('{triage,backlog,unstarted,started,canceled}'::text[]) when 'canceled' then new."state"::text = any ('{triage,backlog,unstarted,started,completed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'work_item', new."id"::text, old."state"::text, new."state"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'from', old."state"::text, 'to', new."state"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/work_item/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_shift (
  shift_id uuid,
  reason   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_assignment "better_supabase"."shift_assignments"%rowtype;
  v_users jsonb := '[]'::jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shifts" x where x."id" = cancel_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to cancel shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'canceled' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    v_users := coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb);
    update "better_supabase"."shifts" x set "status" = 'canceled', "canceled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    for v_assignment in
      update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
      where x."shift_id" = v_row."id" and x."status" <> 'released'
      returning x.*
    loop
      perform "better_supabase".emit_event('shift_assignment.released', jsonb_build_object('organizationId', v_assignment."tenant_id", 'shiftId', v_assignment."shift_id", 'assignmentId', v_assignment."id", 'userId', v_assignment."user_id", 'startsAt', v_assignment."starts_at", 'endsAt', v_assignment."ends_at", 'reason', 'shift_canceled'), 'shifts/' || v_assignment."shift_id"::text, (v_assignment."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.released',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_assignment."id"::text,
    summary => 'Shift assignment released',
    tenant => (v_assignment."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_assignment."tenant_id", 'shiftId', v_assignment."shift_id", 'assignmentId', v_assignment."id", 'userId', v_assignment."user_id", 'startsAt', v_assignment."starts_at", 'endsAt', v_assignment."ends_at", 'reason', 'shift_canceled')
  );
    end loop;
    perform "better_supabase".emit_event('shift.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', nullif(trim(cancel_shift.reason), '')), 'shifts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift.cancelled',
    category => 'data',
    target_type => 'shift',
    record_id => v_row."id"::text,
    summary => 'Shift canceled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', nullif(trim(cancel_shift.reason), ''))
  );
    if jsonb_array_length(v_users) > 0 then
      if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift.cancelled',
      'tenant', v_row."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_row."id"::text,
      'summary', 'Your shift is canceled',
      'recipients', v_users,
      'key', 'shift.cancelled:' || v_row."id"::text,
      'data', jsonb_build_object('startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_sla_clocks()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_clock "better_supabase"."sla_clocks";
  v_count integer := 0;
  v_claims text;
begin
  for v_clock in
    update "better_supabase"."sla_clocks" x set "breached_at" = now()
    where x."met_at" is null and x."paused_at" is null and x."breached_at" is null and x."due_at" < now()
    returning *
  loop
    perform "better_supabase".emit_event('sla.breached', jsonb_build_object('organizationId', v_clock."tenant_id", 'clockId', v_clock."id", 'subjectType', v_clock."subject_type", 'subjectId', v_clock."subject_id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at"), 'sla-clocks/' || v_clock."id"::text, (v_clock."tenant_id"::text)::text, null, 'better-supabase/sla');
    if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'sla.breached',
      'tenant', v_clock."tenant_id",
      'subject_type', v_clock."subject_type",
      'subject_id', v_clock."subject_id",
      'summary', v_clock."metric" || ' ' || 'breached',
      'priority', 'high',
      'key', 'sla.breached:' || v_clock."id"::text,
      'data', jsonb_build_object('clockId', v_clock."id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at")
    ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    v_count := v_count + 1;
  end loop;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "warned_at" = now()
    from "better_supabase"."sla_policies" y
    where y."id" = x."policy_id" and x."met_at" is null and x."paused_at" is null and x."warned_at" is null
      and x."breached_at" is null
      and now() >= x."started_at" + (x."due_at" - x."started_at") * y."warn_at_percent" / 100.0
    returning x.*
  loop
    perform "better_supabase".emit_event('sla.warned', jsonb_build_object('organizationId', v_clock."tenant_id", 'clockId', v_clock."id", 'subjectType', v_clock."subject_type", 'subjectId', v_clock."subject_id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at"), 'sla-clocks/' || v_clock."id"::text, (v_clock."tenant_id"::text)::text, null, 'better-supabase/sla');
    if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'sla.warned',
      'tenant', v_clock."tenant_id",
      'subject_type', v_clock."subject_type",
      'subject_id', v_clock."subject_id",
      'summary', v_clock."metric" || ' ' || 'warned',
      'priority', 'high',
      'key', 'sla.warned:' || v_clock."id"::text,
      'data', jsonb_build_object('clockId', v_clock."id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at")
    ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_sent (
  message uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg record;
  v_conv record;
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" x
  where x."id" = comment_sent.message and x."author_id" = auth.uid()
    and x."sent_at" is not null and x."deleted_at" is null;
  if not found then
    return;
  end if;
  select * into v_conv from "better_supabase"."conversations" c
  where c."id" = v_msg."conversation_id" and c."kind" = 'subject';
  if not found then
    return;
  end if;
  foreach v_user in array array(select distinct x from unnest(array[v_msg."author_id"] || v_msg."mentions") x where x = v_msg."author_id" or coalesce(better_supabase.can_user(x, 'tenant', v_msg."tenant_id", 'messages.read'), false)) loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_conv."tenant_id", v_user, v_conv."subject_type", v_conv."subject_id", 'participating')
    on conflict do nothing;
  end loop;
  if (exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."subject_type" = v_conv."subject_type" and s."subject_id" = v_conv."subject_id" and s."organization_id" = v_conv."tenant_id"
        and s."level" in ('all', 'participating')
        and not s."user_id" = any (array[v_msg."author_id"] || v_msg."mentions")
    ) or to_regprocedure('"public"."notification_audience"(jsonb)') is not null) then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'comment.posted',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', v_conv."subject_type",
      'subject_id', v_conv."subject_id",
      'subject_label', "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id"),
      'summary', left(v_msg."body", 140),
      'recipients', '[]'::jsonb,
      'exclude', to_jsonb(v_msg."mentions"),
      'key', 'comment.posted:' || v_msg."id"::text,
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_production_order (
  order_id uuid,
  produced numeric,
  scrap    numeric DEFAULT 0,
  lot      jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_orders";
  v_bom "better_supabase"."boms";
  v_component record;
  v_tracking text;
  v_item_currency text;
  v_currency text;
  v_lot uuid;
  v_material bigint;
  v_labor bigint;
  v_scrap numeric := coalesce(complete_production_order.scrap, 0);
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."production_orders" x where x."id" = complete_production_order.order_id for update;
  if not found then
    raise exception 'no such production order' using errcode = 'P0002', hint = 'PRODUCTION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.produce'), false))) then
    raise exception 'not allowed to complete production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_row."status" not in ('released', 'in_progress') then
    raise exception 'the production order can''t move from % to %', v_row."status", 'done' using errcode = '55000', hint = 'PRODUCTION_ORDER_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'done')::text;
  end if;
  if complete_production_order.produced is null or complete_production_order.produced <= 0 or v_scrap < 0 then
    raise exception 'produced must be more than zero and scrap zero or more' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if complete_production_order.lot is not null and jsonb_typeof(complete_production_order.lot) <> 'object' then
    raise exception 'lot must be an object' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_production_order_complete"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select * into v_bom from "better_supabase"."boms" x where x."id" = v_row."bom_id";
  for v_component in
    select y."variant_id" as variant,
      "better_supabase"."production_quantity"(y."variant_id", y."quantity" * (complete_production_order.produced + v_scrap) / v_bom."quantity" * (1 + y."scrap_bps" / 10000.0)) as quantity
    from "better_supabase"."bom_components" y where y."bom_id" = v_bom."id"
      and not exists (select 1 from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id" and z."variant_id" = y."variant_id")
    order by y."position", y."id"
  loop
    perform "better_supabase"."production_consume"(v_row."id", v_component.variant, v_component.quantity, null);
  end loop;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."release_allocations"(v_row."tenant_id", 'production_order', v_row."id"::text);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  update "better_supabase"."production_order_operations" x set "status" = 'done', "started_at" = coalesce(x."started_at", now()),
    "finished_at" = now(), "minutes" = coalesce(x."minutes", x."planned_minutes")
  where x."order_id" = v_row."id" and x."status" <> 'done';

  select x."tracking", x."currency" into v_tracking, v_item_currency
  from "better_supabase"."stock_items" x where x."variant_id" = v_row."variant_id";
  v_currency := coalesce(v_item_currency,
    (select min(z."currency") from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"),
    (select min(y."currency") from "better_supabase"."production_order_operations" x join "better_supabase"."work_centers" y on y."id" = x."work_center_id"
      where x."order_id" = v_row."id"));
  select coalesce(sum(z."cost"), 0) into v_material from "better_supabase"."production_consumptions" z
  where z."order_id" = v_row."id" and z."currency" is not distinct from v_currency;
  select coalesce(sum(round(x."minutes" * y."cost_rate" / 60.0)), 0)::bigint into v_labor
  from "better_supabase"."production_order_operations" x join "better_supabase"."work_centers" y on y."id" = x."work_center_id"
  where x."order_id" = v_row."id" and y."currency" = v_currency;

  v_lot := nullif(complete_production_order.lot ->> 'lotId', '')::uuid;
  if v_lot is null and (nullif(complete_production_order.lot ->> 'code', '') is not null or v_tracking = 'lot') then
    v_lot := "better_supabase"."stock_lot_for"(v_row."tenant_id", v_row."variant_id",
      coalesce(nullif(complete_production_order.lot ->> 'code', ''), v_row."number"),
      nullif(complete_production_order.lot ->> 'expiresOn', '')::date);
  end if;
  perform "better_supabase"."move_stock"(v_row."tenant_id", v_row."variant_id", v_row."location_id", complete_production_order.produced, 'production', 'production_order', v_row."id"::text, null, jsonb_strip_nulls(jsonb_build_object('lotId', v_lot, 'serials', complete_production_order.lot -> 'serials',
      'unitCost', round((v_material + v_labor)::numeric / complete_production_order.produced, 6)::text, 'currency', v_item_currency)));
  if v_lot is not null then
    insert into "better_supabase"."stock_lot_links" ("tenant_id", "parent_lot_id", "child_lot_id", "order_id", "quantity")
    select v_row."tenant_id", v_lot, z."lot_id", v_row."id", sum(z."quantity")
    from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id" and z."lot_id" is not null and z."lot_id" <> v_lot
    group by z."lot_id";
  end if;
  update "better_supabase"."production_orders" x set "status" = 'done', "produced_quantity" = complete_production_order.produced, "scrap_quantity" = v_scrap,
    "output_lot_id" = v_lot, "material_cost" = v_material, "labor_cost" = v_labor, "currency" = v_currency,
    "started_at" = coalesce(x."started_at", now()), "completed_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_labor > 0 then
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('production_order', v_row."id"::text);
  end if;
  end if;
  perform "better_supabase".emit_event('production_order.completed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'variantId', v_row."variant_id", 'quantity', v_row."quantity"::text, 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id"), 'production-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/manufacturing');
  perform better_supabase.audit_event(
    event_type => 'production_order.completed',
    category => 'data',
    target_type => 'production_order',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'production order completed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'variantId', v_row."variant_id", 'quantity', v_row."quantity"::text, 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_production_order_complete"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
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

CREATE OR REPLACE FUNCTION better_supabase.decide_quote (
  quote    uuid,
  decision text,
  note     text,
  by       text,
  selected jsonb DEFAULT NULL::jsonb,
  actor    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decided_user_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_user_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_user_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_shift_request (
  assignment_id uuid,
  approve       boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = decide_shift_request.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to decide shift requests' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'requested' then
    raise exception 'the assignment isn''t a pending request' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if coalesce(decide_shift_request.approve, false) then
    if v_shift."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
    v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", v_row."user_id", v_row."id");
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", v_row."user_id";
    end if;
  end;
    begin
      update "better_supabase"."shift_assignments" x set "status" = 'assigned', "starts_at" = v_shift."starts_at", "ends_at" = v_shift."ends_at", "assigned_by" = (select auth.uid()), "updated_at" = now()
      where x."id" = v_row."id"
      returning x.* into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    perform "better_supabase".emit_event('shift_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.created',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
    if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.created',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'Your shift request is approved',
      'recipients', jsonb_build_array(v_row."user_id"),
      'key', 'shift_assignment.created:' || v_shift."id"::text || ':' || v_row."user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('shift_assignment.released', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'request_rejected'), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.released',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift request rejected',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'request_rejected')
  );
    if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.released',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'Your shift request is turned down',
      'recipients', jsonb_build_array(v_row."user_id"),
      'key', 'shift_assignment.released:' || v_shift."id"::text || ':' || v_row."user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_shift_swap (
  swap_id     uuid,
  approve     boolean,
  approval_id uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_status text;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_swap from "better_supabase"."shift_swaps" x where x."id" = decide_shift_swap.swap_id for update;
  if not found then
    raise exception 'shift swap not found' using errcode = 'P0002', hint = 'SHIFT_SWAP_NOT_FOUND';
  end if;
  if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_swap."tenant_id", 'shifts.manage'), false)) then
    v_status := case when coalesce(decide_shift_swap.approve, false) then 'approved' else 'rejected' end;
  elsif v_swap."from_user_id" = (select auth.uid()) and not coalesce(decide_shift_swap.approve, false) then
    v_status := 'canceled';
  else
    raise exception 'not allowed to decide shift swaps' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_swap."status" <> 'pending' then
    raise exception 'the swap is already decided' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if decide_shift_swap.approval_id is not null and not exists (
    select 1 from "better_supabase"."approval_requests" o where o."id" = decide_shift_swap.approval_id and o."tenant_id" = v_swap."tenant_id"
  ) then
    raise exception 'the approval isn''t in this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = v_swap."assignment_id";
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if v_status = 'approved' then
    if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' then
      raise exception 'the shift is no longer assigned to the member who asked' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
    end if;
    perform "better_supabase"."shift_assignment_check"(v_shift."id", v_swap."to_user_id", null);
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('shift_assignment.released', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'swapped'), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.released',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment released',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'swapped')
  );
    begin
      insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_swap."to_user_id", 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    perform "better_supabase".emit_event('shift_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.created',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
  end if;
  update "better_supabase"."shift_swaps" x set "status" = v_status, "decided_at" = now(), "decided_by" = (select auth.uid()), "approval_id" = coalesce(decide_shift_swap.approval_id, x."approval_id")
  where x."id" = v_swap."id"
  returning x.* into v_swap;
  perform "better_supabase".emit_event('shift_swap.decided', jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status"), 'shifts/' || v_shift."id"::text, (v_swap."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_swap.decided',
    category => 'data',
    target_type => 'shift_swap',
    record_id => v_swap."id"::text,
    summary => 'Shift swap decided',
    tenant => (v_swap."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status")
  );
  if v_status <> 'canceled' then
    if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_swap.decided',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'Your shift swap is decided',
      'recipients', jsonb_build_array(v_swap."from_user_id"),
      'key', 'shift_swap.decided:' || v_shift."id"::text || ':' || v_swap."from_user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  if v_status = 'approved' then
    if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.created',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'You took over a shift',
      'recipients', jsonb_build_array(v_swap."to_user_id"),
      'key', 'shift_assignment.created:' || v_shift."id"::text || ':' || v_swap."to_user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.donation_settle (
  gift_id    uuid,
  status     text,
  provider   text DEFAULT NULL::text,
  payment_id text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_fund "better_supabase"."donation_funds"%rowtype;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = donation_settle.gift_id for update;
  if not found then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if donation_settle.status not in ('pending', 'succeeded', 'failed', 'refunded') then
    raise exception 'status is pending, succeeded, failed or refunded' using errcode = '22023', hint = 'DONATION_STATUS_INVALID';
  end if;
  if donation_settle.payment_id is not null and v_row."payment_reference" is null then
    update "better_supabase"."donations" x set "provider" = coalesce(donation_settle.provider, x."provider"),
        "payment_reference" = donation_settle.payment_id, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  end if;
  select * into v_fund from "better_supabase"."donation_funds" y where y."id" = v_row."fund_id";
  if donation_settle.status = 'succeeded' and v_row."status" in ('pending', 'failed') then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.gift',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount")),
      'donations', v_row."id"::text, 'Gift', 'donation:' || v_row."id"::text || ':posted', v_row."received_on"::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('donationId', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id")));
    update "better_supabase"."donations" x set "status" = 'posted', "transaction_id" = v_tx, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('gift', v_row."id"::text);
  end if;
    perform "better_supabase".emit_event('donation.received', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'donations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation.received',
    category => 'billing',
    target_type => 'donation',
    record_id => v_row."id"::text,
    summary => 'received a gift',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  elsif donation_settle.status = 'failed' and v_row."status" = 'pending' then
    update "better_supabase"."donations" x set "status" = 'failed', "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('donation.failed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'donations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation.failed',
    category => 'billing',
    target_type => 'donation',
    record_id => v_row."id"::text,
    summary => 'a gift payment failed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  elsif donation_settle.status = 'refunded' and v_row."status" = 'posted' then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.refund',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount")),
      'donations', v_row."id"::text, 'Gift refunded', 'donation:' || v_row."id"::text || ':refunded', null,
      jsonb_build_object('donationId', v_row."id"));
    update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = 'the gift was refunded'
      where x."id" = v_row."receipt_id" and x."kind" = 'gift' and x."voided_at" is null;
    update "better_supabase"."donations" x set "status" = 'refunded', "refund_transaction_id" = v_tx, "receipt_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'gift', v_row."id"::text);
    perform "better_supabase".emit_event('donation.refunded', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'donations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation.refunded',
    category => 'billing',
    target_type => 'donation',
    record_id => v_row."id"::text,
    summary => 'refunded a gift',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.due_care_plan_reviews()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_plan "better_supabase"."care_plans"%rowtype;
  v_row "better_supabase"."care_plan_actions"%rowtype;
  v_due timestamptz;
  v_claims text;
  v_count integer := 0;
begin
  for v_plan in
    select * from "better_supabase"."care_plans" x
    where x."status" = 'active' and x."review_on" <= current_date
      and x."review_notified_for" is distinct from x."review_on"
    for update skip locked
  loop
    perform "better_supabase".emit_event('care_plan.review_date_reached', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id", 'title', v_plan."title", 'status', v_plan."status", 'version', v_plan."version", 'ownerId', v_plan."owner_id", 'reviewOn', v_plan."review_on"), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan.review_date_reached',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan review due',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id", 'title', v_plan."title", 'status', v_plan."status", 'version', v_plan."version", 'ownerId', v_plan."owner_id", 'reviewOn', v_plan."review_on")
  );
    if v_plan."owner_id" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'care_plan.review_date_reached',
        'tenant', v_plan."tenant_id",
        'actor', null,
        'subject_type', 'care_plan',
        'subject_id', v_plan."id"::text,
        'summary', v_plan."title",
        'recipients', to_jsonb(array[v_plan."owner_id"]),
        'key', 'care_plan.review_date_reached:' || v_plan."id"::text || ':' || v_plan."review_on"::text,
        'data', jsonb_build_object('planId', v_plan."id", 'reviewOn', v_plan."review_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."care_plans" x set "review_notified_for" = v_plan."review_on" where x."id" = v_plan."id";
    v_count := v_count + 1;
  end loop;
  for v_row in
    select w.* from "better_supabase"."care_plan_actions" w
    join "better_supabase"."care_plans" x on x."id" = w."plan_id" and x."status" = 'active'
    where w."status" = 'active' and w."review_every" is not null
      and coalesce(w."reviewed_at", w."started_at") + w."review_every" <= now()
      and w."review_notified_at" is distinct from coalesce(w."reviewed_at", w."started_at") + w."review_every"
    for update of w skip locked
  loop
    v_due := coalesce(v_row."reviewed_at", v_row."started_at") + v_row."review_every";
    select * into v_plan from "better_supabase"."care_plans" x where x."id" = v_row."plan_id";
    perform "better_supabase".emit_event('care_plan_action.review_date_reached', jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'ownerId', v_plan."owner_id", 'dueAt', v_due), 'care-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/care-plans');
  perform better_supabase.audit_event(
    event_type => 'care_plan_action.review_date_reached',
    category => 'data',
    target_type => 'care_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'care plan action review due',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'planId', v_plan."id", 'subjectType', v_plan."subject_type", 'subjectId', v_plan."subject_id") || jsonb_build_object('actionId', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'ownerId', v_plan."owner_id", 'dueAt', v_due)
  );
    if v_plan."owner_id" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'care_plan_action.review_date_reached',
        'tenant', v_plan."tenant_id",
        'actor', null,
        'subject_type', 'care_plan',
        'subject_id', v_plan."id"::text,
        'summary', v_plan."title",
        'recipients', to_jsonb(array[v_plan."owner_id"]),
        'key', 'care_plan_action.review_date_reached:' || v_row."id"::text || ':' || v_due::text,
        'data', jsonb_build_object('planId', v_plan."id", 'actionId', v_row."id", 'dueAt', v_due)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."care_plan_actions" w set "review_notified_at" = v_due where w."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.emit_event (
  event_type text,
  payload    jsonb DEFAULT '{}'::jsonb,
  subject    text  DEFAULT NULL::text,
  tenant     text  DEFAULT NULL::text,
  key        text  DEFAULT NULL::text,
  source     text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  found_id text;
  v_run uuid := better_supabase.import_run();
  v_mode text;
begin
  if event_type is null or btrim(event_type) = '' then
    raise exception 'An event needs a type' using errcode = '22023', hint = 'OUTBOX_TYPE_REQUIRED';
  end if;
  -- In import mode (ADR 0141) the run's imports.events policy decides: the
  -- event type's own entry, then the default, then skip.
  if v_run is not null then
    v_mode := coalesce(
      nullif(current_setting('better_supabase.import_events', true), '')::jsonb ->> event_type,
      nullif(current_setting('better_supabase.import_events', true), '')::jsonb ->> 'default',
      'skip'
    );
    if v_mode = 'skip' then
      return null;
    elsif v_mode = 'tag' then
      payload := coalesce(payload, '{}'::jsonb) || jsonb_build_object('importRunId', v_run);
    end if;
  end if;
  if key is not null then
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
    if found_id is not null then
      return found_id;
    end if;
  end if;
  insert into "better_supabase"."outbox_events" ("type", "payload", "source", "subject", "organization_id", "key", "actor_id")
  values (event_type, coalesce(payload, '{}'), source, coalesce(subject, payload ->> 'subject'), tenant::uuid, key, auth.uid())
  on conflict do nothing
  returning "id"::text into found_id;
  if found_id is null then
    -- Another transaction emitted the same key first.
    select e."id"::text into found_id from "better_supabase"."outbox_events" e
    where e."key" = key and e."organization_id" is not distinct from tenant::uuid;
  end if;
  return found_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_import_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "missing_since" = coalesce(x."missing_since", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      perform "better_supabase".emit_event('import.entity_completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
      if coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0) > 0 then
        perform better_supabase.audit_event(
    event_type => 'import.entity_completed',
    category => 'integration',
    target_type => 'import',
    record_id => v_run_id::text,
    target_label => v_entity,
    summary => 'imported ' || v_entity,
    tenant => (v_run."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity),
    idempotency_key => 'import:' || v_run_id::text || ':' || v_entity,
    actor_kind => 'integration',
    correlation_id => 'import:' || v_run_id::text
  );
      end if;
    end loop;
    perform "better_supabase".emit_event('import.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'count', v_total), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
  end if;
  return v_counts;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_run()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_upsert_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_add_message (
  conversation uuid,
  input        jsonb,
  author_type  text,
  author       uuid,
  direction    text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_id uuid;
  v_at timestamptz := clock_timestamp();
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_body text := coalesce(input ->> 'body', '');
  v_mentions uuid[];
  v_uploads uuid[];
  v_file jsonb;
  v_moved integer;
  v_reopened boolean := false;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = inbox_add_message.conversation for update;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = v_conv."inbox_id";
  if input ? 'external_id' then
    select d."message_id" into v_id from "better_supabase"."inbox_message_details" d
    where d."conversation_id" = v_conv."id" and d."external_id" = input ->> 'external_id';
    if found then
      return v_id;
    end if;
  end if;
  if v_kind not in ('message', 'note') then
    raise exception 'kind is message or note' using errcode = '22023', hint = 'INBOX_KIND_INVALID';
  end if;
  v_uploads := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(input -> 'attachments', '[]'::jsonb)) x);
  if length(btrim(v_body)) = 0 and cardinality(v_uploads) = 0 and coalesce(jsonb_array_length(input -> 'files'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  if length(v_body) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_mentions
  from jsonb_array_elements_text(coalesce(input -> 'mentions', '[]'::jsonb)) e(raw)
  cross join lateral (select e.raw::uuid as x) u
  where coalesce(better_supabase.can_user(u.x, 'tenant', v_conv."tenant_id", 'inbox.read'), false);
  insert into "better_supabase"."messages" ("tenant_id", "conversation_id", "author_id", "kind", "body", "mentions", "sent_at", "created_at")
  values (v_conv."tenant_id", v_conv."id", inbox_add_message.author, v_kind, v_body, v_mentions, v_at, v_at)
  returning "id" into v_id;
  perform "better_supabase"."index_record_mentions"(v_id);
  insert into "better_supabase"."inbox_message_details" ("message_id", "tenant_id", "conversation_id", "direction", "author_type", "format", "external_id", "reply_to", "metadata")
  values (
    v_id, v_conv."tenant_id", v_conv."id", inbox_add_message.direction, inbox_add_message.author_type,
    coalesce(input ->> 'format', 'text'), input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  );
  if cardinality(v_uploads) > 0 then
    update "better_supabase"."attachments" x set "subject_type" = 'message', "subject_id" = v_id::text
    where x."id" = any (v_uploads)
      and x."organization_id" = v_conv."tenant_id"
      and x."subject_type" = 'conversation' and x."subject_id" = v_conv."id"::text
      and x."status" <> 'infected'
      and (inbox_add_message.author is null or x."uploaded_by" = inbox_add_message.author);
    get diagnostics v_moved = row_count;
    if v_moved <> cardinality(v_uploads) then
      raise exception 'attachments must be your uploads to this conversation' using errcode = '22023', hint = 'INBOX_ATTACHMENT_INVALID';
    end if;
  end if;
  for v_file in select f from jsonb_array_elements(coalesce(input -> 'files', '[]'::jsonb)) f loop
    insert into "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id", "name", "mime_type", "size", "uploaded_by", "scan_detail")
    values (
      v_conv."tenant_id", 'message', v_id::text,
      left(coalesce(nullif(v_file ->> 'name', ''), 'file'), 255),
      lower(coalesce(nullif(v_file ->> 'content_type', ''), 'application/octet-stream')),
      coalesce((v_file ->> 'size')::bigint, 0),
      null,
      jsonb_build_object('source', v_file)::text
    );
  end loop;
  if inbox_add_message.author is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_conv."id", v_conv."tenant_id", inbox_add_message.author)
    on conflict do nothing;
  end if;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv."status" in ('resolved', 'snoozed');
    update "better_supabase"."inbox_conversations" set
      "last_message_at" = v_at,
      "last_message_preview" = left(v_body, 140),
      "first_response_at" = case
        when "first_response_at" is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_at
        else "first_response_at" end,
      "status" = case when v_reopened then 'open' else "status" end,
      "snoozed_until" = case when v_reopened then null else "snoozed_until" end,
      "resolved_at" = case when v_reopened then null else "resolved_at" end
    where "id" = v_conv."id"
    returning * into v_conv;
    if v_reopened then
      insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'reopened', (select auth.uid()), jsonb_build_object('by', 'contact'));
      perform "better_supabase".emit_event('inbox_conversation.reopened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    end if;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    perform "better_supabase".emit_event('inbox_message.received', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'messageId', v_id, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, 'inbox_message.received:' || v_id::text, 'better-supabase/inbox');
    if v_conv."bot_mode" = 'bot' then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_bot', payload => jsonb_build_object('conversation_id', v_conv."id", 'message_id', v_id, 'thread_id', v_conv."thread_id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox:' || v_conv."id"::text, dedupe_running => false);
    end if;
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_body, 140),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.message:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox."channel" <> 'in_app' then
    insert into "better_supabase"."inbox_message_deliveries" ("tenant_id", "message_id", "channel")
    values (v_conv."tenant_id", v_id, v_inbox."channel")
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_outbound', payload => jsonb_build_object('message_id', v_id, 'conversation_id', v_conv."id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox-out:' || v_id::text, dedupe_running => false);
    end if;
  end if;
  if cardinality(v_mentions) > 0 then
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.mention',
      'tenant', v_conv."tenant_id",
      'actor', inbox_add_message.author,
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_body, 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inspection_assignment_notice()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_claims text;
begin
  if new."user_id" is not distinct from auth.uid() then
    return new;
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = new."inspection_id";
  if not found or v_row."status" not in ('planned', 'in_progress') then
    return new;
  end if;
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inspection.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'inspection',
      'subject_id', v_row."id"::text,
      'summary', v_row."number" || ' ' || v_row."title",
      'recipients', to_jsonb(array[new."user_id"]),
      'key', 'inspection.assigned:' || v_row."id"::text || ':' || new."user_id"::text,
      'data', jsonb_build_object('inspectionId', v_row."id", 'role', new."role")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_invoice (
  invoice   uuid,
  issued_on date,
  due_on    date  DEFAULT NULL::date,
  actor     jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_original "better_supabase"."invoices";
  v_seq bigint;
  v_identifier text;
  v_issued_on date := coalesce(issue_invoice.issued_on, current_date);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'the invoice was already issued' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  if not exists (select 1 from "better_supabase"."invoice_lines" x where x."parent_id" = v_row."id") then
    raise exception 'an invoice needs a line before it is issued' using errcode = '23514', hint = 'INVOICE_EMPTY';
  end if;
  if issue_invoice.due_on < v_issued_on then
    raise exception 'an invoice falls due on or after its issue date' using errcode = '22023', hint = 'INVOICE_DUE_INVALID';
  end if;
  if issue_invoice.actor is not null then
    if jsonb_typeof(issue_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(issue_invoice.actor ->> 'ip', '')::inet, nullif(issue_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(issue_invoice.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  if v_row."kind" = 'credit_note' then
    select * into v_original from "better_supabase"."invoices" x where x."id" = v_row."original_id" for update;
    if v_row."total" > v_original."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_original."id"), 0) - v_original."credited_total" then
      raise exception 'a credit note can''t exceed the invoice''s total less its earlier credits' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
    end if;
    if v_row."direction" = 'purchase' then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_credit_note', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'BCN-' || v_seq::text;
    else
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':credit_note', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'CN-' || v_seq::text;
    end if;
  else
    if v_row."direction" = 'purchase' then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_bill', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'BILL-' || v_seq::text;
    else
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':invoice', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'INV-' || v_seq::text;
    end if;
  end if;
  if v_row."kind" = 'invoice' and not v_row."direction" = 'purchase' and coalesce(v_row."company_id"::text, v_row."contact_id"::text) is not null then
    declare
      v_limit bigint;
    begin
      select s.credit_limit into v_limit from (select p."credit_limit", p."credit_currency" from "better_supabase"."companies" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null union all select p."credit_limit", p."credit_currency" from "better_supabase"."people" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null) s(credit_limit, credit_currency)
      where s.credit_limit is not null and coalesce(s.credit_currency, v_row."currency") = v_row."currency"
      order by s.credit_limit limit 1;
      if v_limit is not null and (select coalesce(sum((o."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = o."id"), 0) - o."credited_total" - o."paid_total")), 0) from "better_supabase"."invoices" o
        where o."tenant_id" = v_row."tenant_id" and o."id" <> v_row."id" and o."currency" = v_row."currency"
          and coalesce(o."company_id"::text, o."contact_id"::text) = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and not o."direction" = 'purchase'
          and o."kind" = 'invoice' and o."status" in ('issued', 'partially_paid')) + v_row."total" > v_limit and not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'orders.override_credit'), false)) then
        raise exception 'this invoice takes the customer over their credit limit' using errcode = '55000', hint = 'INVOICE_CREDIT_LIMIT_EXCEEDED';
      end if;
    end;
  end if;
  update "better_supabase"."invoices" x set "status" = 'issued', "number" = v_seq, "identifier" = v_identifier,
    "issued_on" = v_issued_on,
    "due_on" = coalesce(issue_invoice.due_on, v_issued_on + x."terms_days"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.issued', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'dueOn', v_row."due_on"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."kind" = 'credit_note' then
    update "better_supabase"."invoices" x set "credited_total" = x."credited_total" + v_row."total", "updated_at" = now()
    where x."id" = v_original."id"
    returning * into v_original;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_original."id"
  returning * into v_original;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_original."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_original;
    perform "better_supabase".emit_event('invoice.credited', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'creditNoteId', v_row."id", 'amount', v_row."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    if v_original."status" = 'paid' then
      perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'total', v_original."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    end if;
  end if;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice', v_row."id"::text);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
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

CREATE OR REPLACE FUNCTION better_supabase.log_activity (
  tenant   uuid,
  attrs    jsonb,
  subjects jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_tenant uuid := log_activity.tenant;
  v_type text := log_activity.attrs ->> 'type';
  v_title text := nullif(trim(log_activity.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_activity.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'activities.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ACTIVITY_TITLE_REQUIRED';
  end if;
  if nullif(log_activity.attrs ->> 'audience', '') is not null and not (log_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if log_activity.attrs ? 'restrictedRoles' and jsonb_typeof(log_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(log_activity.attrs ->> 'category', '') is not null and not (log_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_activity.attrs ->> 'body', log_activity.attrs ->> 'outcome', v_owner, (log_activity.attrs ->> 'dueAt')::timestamptz, (log_activity.attrs ->> 'doneAt')::timestamptz, (log_activity.attrs ->> 'durationSeconds')::integer, log_activity.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_activity.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_activity.attrs -> 'restrictedRoles') = 'array' then log_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_activity.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_activity.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_missed_medication_administrations()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_administrations"%rowtype;
  v_order "better_supabase"."medication_orders"%rowtype;
  v_count integer := 0;
  v_claims text;
  v_case_kind uuid;
begin
  for v_row in
    update "better_supabase"."medication_administrations" x set "status" = 'missed'
    where x."status" = 'planned' and x."scheduled_at" < now() - interval '60 minutes'
    returning x.*
  loop
    select * into v_order from "better_supabase"."medication_orders" x where x."id" = v_row."order_id";
    perform "better_supabase".emit_event('medication_administration.missed', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at"), 'medication-orders/' || v_row."order_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_administration.missed',
    category => 'data',
    target_type => 'medication_administration',
    record_id => v_row."id"::text,
    summary => 'Medication dose missed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at")
  );
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'medication_administration.missed',
      'tenant', v_row."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', v_order."subject_type",
      'subject_id', v_order."subject_id"::text,
      'summary', 'A medication dose was missed',
      'permission', 'medications.manage',
      'watchers', false,
      'key', 'medication_administration.missed:' || v_row."id"::text,
      'data', jsonb_build_object('medicationOrderId', v_order."id", 'scheduledAt', v_row."scheduled_at")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    select y."id" into v_case_kind from "better_supabase"."case_kinds" y
    where y."tenant_id"::text = v_row."tenant_id"::text and y."key" = 'incident' and y."archived_at" is null;
    if v_case_kind is null then
      perform "better_supabase"."ensure_case_kinds"(v_row."tenant_id");
      select y."id" into v_case_kind from "better_supabase"."case_kinds" y
    where y."tenant_id"::text = v_row."tenant_id"::text and y."key" = 'incident' and y."archived_at" is null;
    end if;
    if v_case_kind is not null then
      perform "better_supabase"."open_case_as"(v_case_kind, jsonb_build_object(
        'title', left('Missed dose: ' || coalesce((select z."name" from "better_supabase"."medications" z where z."id" = v_order."medication_id"), 'medication')
          || ' at ' || to_char(v_row."scheduled_at" at time zone 'UTC', 'YYYY-MM-DD HH24:MI'), 200),
        'source', 'internal',
        'occurredAt', v_row."scheduled_at",
        'originType', v_order."subject_type",
        'originId', v_order."subject_id"
      ), null);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_message_sent (
  message uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
  v_conv "better_supabase"."conversations";
  v_mentioned uuid[];
  v_direct uuid[];
  v_claims text;
begin
  select * into v_msg from "better_supabase"."messages" m where m."id" = messaging_message_sent.message;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id";
  perform "better_supabase"."index_record_mentions"(v_msg."id");
  perform "better_supabase".emit_event('message.sent', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text, 'mentionIds', to_jsonb(v_msg."mentions"), 'recordMentions', (select coalesce(jsonb_agg(jsonb_build_object('type', x."subject_type", 'id', x."subject_id") order by x."subject_type", x."subject_id"), '[]'::jsonb) from "better_supabase"."message_record_mentions" x where x."message_id" = v_msg."id"))
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  -- Mentioned users who can read the conversation.
  v_mentioned := array(
    select distinct x from unnest(v_msg."mentions") x
    where x is distinct from v_msg."author_id"
      and coalesce(better_supabase.can_user(x, 'tenant', v_msg."tenant_id", 'messages.read'), false)
        and (v_conv."access" <> 'members' or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = x))
        and (v_conv."access" <> 'subject' or case v_conv."subject_type" when 'message' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'conversation' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'channel' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'company' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'person' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'deal' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'course' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'post' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'activity' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'quote' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'work_item' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'employee' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'invoice' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'ledger_account' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'product' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'product_variant' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'order' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'calendar_event' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'booking' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'asset' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'asset_location' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'lease' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'expense_report' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'expense_line' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'donation_fund' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'work_order' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'shipment' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'contract' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'control' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'compliance_policy' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'qualification_type' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'risk' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'case' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'inspection' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'inspection_program' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'inspection_finding' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'form' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'production_order' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'work_center' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'care_plan' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'incident' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'content_entry' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'document' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'customer' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'drive_node' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'application' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) else true end)
  );
  if v_msg."mention_scope" is not null then
    v_mentioned := v_mentioned || array(
      select k."user_id" from "better_supabase"."conversation_members" k
      where k."conversation_id" = v_conv."id" and k."notify" <> 'none'
        and k."user_id" is distinct from v_msg."author_id"
    );
  end if;
  v_mentioned := array(
    select distinct x from unnest(v_mentioned) x
    where not exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = x and k."notify" = 'none')
  );
  if cardinality(v_mentioned) > 0 then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'message.mentioned',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', 'message',
      'subject_id', coalesce(v_msg."thread_id", v_msg."id")::text,
      'subject_label', coalesce(case when v_conv."kind" = 'subject' then "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id") end, v_conv."title"),
      'summary', left(v_msg."body", 140),
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id"),
      'recipients', to_jsonb(v_mentioned),
      'watchers', false,
      'key', 'message.mentioned:' || v_msg."id"::text
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if v_conv."kind" in ('dm', 'group_dm') and v_msg."thread_id" is null then
    v_direct := array(
      select k."user_id" from "better_supabase"."conversation_members" k
      where k."conversation_id" = v_conv."id" and k."notify" = 'all'
        and k."user_id" is distinct from v_msg."author_id"
        and not k."user_id" = any (v_mentioned)
    );
    if cardinality(v_direct) > 0 then
      if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'message.direct',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', 'message',
      'subject_id', coalesce(v_msg."thread_id", v_msg."id")::text,
      'subject_label', coalesce(case when v_conv."kind" = 'subject' then "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id") end, v_conv."title"),
      'summary', left(v_msg."body", 140),
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id"),
      'recipients', to_jsonb(v_direct),
      'watchers', false,
      'key', 'message.direct:' || v_msg."id"::text
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    end if;
  end if;
  if v_msg."thread_id" is not null then
    -- The replier and the root's author follow the thread.
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_msg."tenant_id", v_msg."author_id", 'message', v_msg."thread_id"::text, 'participating')
    on conflict do nothing;
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_msg."tenant_id", (select r."author_id" from "better_supabase"."messages" r where r."id" = v_msg."thread_id"), 'message', v_msg."thread_id"::text, 'participating')
    on conflict do nothing;
  end if;
  -- The thread's followers hear of a reply, less the members already told
  -- above; nothing is sent when no one follows it.
  if v_msg."thread_id" is not null and (exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."subject_type" = 'message' and s."subject_id" = v_msg."thread_id"::text and s."organization_id" = v_msg."tenant_id"
        and s."level" in ('all', 'participating')
        and not s."user_id" = any (array[v_msg."author_id"] || v_mentioned)
    ) or to_regprocedure('"public"."notification_audience"(jsonb)') is not null) then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'message.replied',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', 'message',
      'subject_id', coalesce(v_msg."thread_id", v_msg."id")::text,
      'subject_label', coalesce(case when v_conv."kind" = 'subject' then "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id") end, v_conv."title"),
      'summary', left(v_msg."body", 140),
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id"),
      'recipients', '[]'::jsonb,
      'exclude', to_jsonb(v_mentioned),
      'key', 'message.replied:' || v_msg."id"::text
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_message_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_msg."id";
    end if;
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_stock (
  tenant         uuid,
  variant        uuid,
  location       uuid,
  quantity       numeric,
  reason         text,
  reference_type text    DEFAULT NULL::text,
  reference_id   text    DEFAULT NULL::text,
  note           text    DEFAULT NULL::text,
  detail         jsonb   DEFAULT NULL::jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_unit text;
  v_scale smallint;
  v_tracking text;
  v_expiry boolean;
  v_costing text;
  v_currency text;
  v_average numeric;
  v_factor numeric;
  v_bin uuid;
  v_lot uuid;
  v_serials text[];
  v_parts jsonb := '[]'::jsonb;
  v_part record;
  v_rest numeric;
  v_take numeric;
  v_lines jsonb := '[]'::jsonb;
  v_held numeric := 0;
  v_bucket numeric;
  v_strict boolean;
  v_id uuid;
  v_on_hand numeric;
  v_after numeric;
  v_point numeric;
  v_unbinned numeric;
  v_total numeric;
  v_value bigint := 0;
  v_balance bigint;
  v_value_account uuid;
  v_suffix text;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'expired', 'scrap', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in', 'consumption', 'production') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  if move_stock.detail is not null and jsonb_typeof(move_stock.detail) <> 'object' then
    raise exception 'detail must be an object' using errcode = '22023', hint = 'INVENTORY_DETAIL_INVALID';
  end if;
  select x."unit", x."scale", x."tracking", x."tracks_expiry", x."costing", x."currency", x."average_cost"
  into v_unit, v_scale, v_tracking, v_expiry, v_costing, v_currency, v_average
  from "better_supabase"."stock_items" x where x."variant_id" = move_stock.variant for update;
  v_unit := coalesce(v_unit, 'item');
  v_scale := coalesce(v_scale, 0);
  v_tracking := coalesce(v_tracking, 'none');
  v_costing := coalesce(v_costing, 'none');
  v_factor := power(10::numeric, v_scale);
  if move_stock.quantity * v_factor <> trunc(move_stock.quantity * v_factor) then
    raise exception 'the quantity has more decimals than the variant''s scale' using errcode = '22023', hint = 'INVENTORY_QUANTITY_PRECISION';
  end if;
  v_strict := exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder");
  v_bin := nullif(move_stock.detail ->> 'binId', '')::uuid;
  v_lot := nullif(move_stock.detail ->> 'lotId', '')::uuid;
  if v_lot is null and jsonb_typeof(move_stock.detail -> 'lot') = 'object' then
    v_lot := "better_supabase"."stock_lot_for"(move_stock.tenant, move_stock.variant, move_stock.detail -> 'lot' ->> 'code',
      nullif(move_stock.detail -> 'lot' ->> 'expiresOn', '')::date);
  end if;
  if v_lot is not null and not exists (select 1 from "better_supabase"."stock_lots" x where x."id" = v_lot and x."variant_id" = move_stock.variant) then
    raise exception 'the lot isn''t a lot of this variant' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  if v_bin is not null and not exists (select 1 from "better_supabase"."stock_bins" x where x."id" = v_bin and x."location_id" = move_stock.location) then
    raise exception 'the bin isn''t at this location' using errcode = 'P0002', hint = 'INVENTORY_BIN_NOT_FOUND';
  end if;
  if jsonb_typeof(move_stock.detail -> 'serials') = 'array' then
    v_serials := array(select jsonb_array_elements_text(move_stock.detail -> 'serials'));
  end if;
  if v_tracking = 'serial' then
    if v_serials is null or cardinality(v_serials) <> abs(move_stock.quantity)
      or (select count(distinct e) from unnest(v_serials) e where length(e) between 1 and 100) <> cardinality(v_serials) then
      raise exception 'a serial-tracked variant needs one distinct serial number per unit' using errcode = '22023', hint = 'INVENTORY_SERIALS_REQUIRED';
    end if;
  elsif coalesce(cardinality(v_serials), 0) > 0 then
    raise exception 'the variant doesn''t track serial numbers' using errcode = '22023', hint = 'INVENTORY_SERIALS_UNTRACKED';
  end if;

  if move_stock.quantity > 0 then
    if v_tracking = 'lot' and v_lot is null and move_stock.reason in ('receipt', 'production') then
      raise exception 'a lot-tracked variant receives stock into a lot' using errcode = '22023', hint = 'INVENTORY_LOT_REQUIRED';
    end if;
    if v_expiry and v_lot is not null and move_stock.reason in ('receipt', 'production')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) is null then
      raise exception 'the variant tracks expiry, so its lots need an expiry date' using errcode = '22023', hint = 'INVENTORY_EXPIRY_REQUIRED';
    end if;
    if v_tracking = 'serial' then
      if exists (select 1 from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) and x."status" = 'in_stock') then
        raise exception 'a serial number is already in stock' using errcode = '23505', hint = 'INVENTORY_SERIAL_IN_STOCK';
      end if;
      insert into "better_supabase"."stock_serials" as x ("tenant_id", "variant_id", "serial", "lot_id", "location_id", "bin_id", "status")
      select move_stock.tenant, move_stock.variant, e, v_lot, move_stock.location, v_bin, 'in_stock' from unnest(v_serials) e
      on conflict ("variant_id", "serial") do update
        set "lot_id" = coalesce(excluded."lot_id", x."lot_id"), "location_id" = excluded."location_id",
          "bin_id" = excluded."bin_id", "status" = 'in_stock', "updated_at" = now();
      select jsonb_agg(jsonb_build_object('bin', v_bin, 'lot', g.lot, 'quantity', g.n)) into v_parts
      from (select x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
        where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."lot_id") g;
    else
      v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
    end if;
  elsif v_tracking = 'serial' then
    if (select count(*) from "better_supabase"."stock_serials" x where x."variant_id" = move_stock.variant and x."serial" = any (v_serials)
        and x."status" = 'in_stock' and x."location_id" = move_stock.location and (v_bin is null or x."bin_id" = v_bin)) <> cardinality(v_serials) then
      raise exception 'a serial number isn''t in stock at this location' using errcode = 'P0002', hint = 'INVENTORY_SERIAL_NOT_IN_STOCK';
    end if;
    select jsonb_agg(jsonb_build_object('bin', g.bin, 'lot', g.lot, 'quantity', -g.n)) into v_parts
    from (select x."bin_id" as bin, x."lot_id" as lot, count(*) as n from "better_supabase"."stock_serials" x
      where x."variant_id" = move_stock.variant and x."serial" = any (v_serials) group by x."bin_id", x."lot_id") g;
    update "better_supabase"."stock_serials" x set "status" = case when move_stock.reason = 'scrap' then 'scrapped' else 'out' end,
      "location_id" = null, "bin_id" = null, "updated_at" = now()
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  elsif v_bin is not null or v_lot is not null then
    if v_lot is not null and move_stock.reason in ('sale', 'transfer_out', 'consumption')
      and (select x."expires_on" from "better_supabase"."stock_lots" x where x."id" = v_lot) < current_date then
      raise exception 'the lot has expired' using errcode = '55000', hint = 'INVENTORY_LOT_EXPIRED';
    end if;
    v_parts := jsonb_build_array(jsonb_build_object('bin', v_bin, 'lot', v_lot, 'quantity', move_stock.quantity));
  else
    v_rest := -move_stock.quantity;
    for v_part in
      select y."bin_id" as bin, y."lot_id" as lot, y."on_hand" as on_hand
      from "better_supabase"."stock_buckets" y
      left join "better_supabase"."stock_bins" bn on bn."id" = y."bin_id"
      left join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id"
      where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location and y."on_hand" > 0
        and (move_stock.reason not in ('sale', 'transfer_out', 'consumption')
          or (not coalesce(bn."hold", false) and (lo."expires_on" is null or lo."expires_on" >= current_date)))
      order by coalesce(bn."hold", false), lo."expires_on" nulls last, lo."code" nulls last, bn."code"
      for update of y
    loop
      exit when v_rest <= 0;
      v_take := least(v_rest, v_part.on_hand);
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', v_part.bin, 'lot', v_part.lot, 'quantity', -v_take));
      v_rest := v_rest - v_take;
    end loop;
    if v_rest > 0 then
      v_parts := v_parts || jsonb_build_array(jsonb_build_object('bin', null, 'lot', null, 'quantity', -v_rest));
    end if;
  end if;

  for v_part in
    select nullif(p ->> 'bin', '')::uuid as bin, nullif(p ->> 'lot', '')::uuid as lot, (p ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(v_parts) p
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock',
      'stock:' || move_stock.variant::text || ':' || move_stock.location::text
        || case when v_part.bin is null and v_part.lot is null then '' else ':' || coalesce(v_part.bin::text, '-') || ':' || coalesce(v_part.lot::text, '-') end,
      'Stock', v_unit, v_scale, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'binId', v_part.bin, 'lotId', v_part.lot))),
      'amount', (v_part.quantity * v_factor)::bigint));
    if v_part.bin is not null or v_part.lot is not null then
      insert into "better_supabase"."stock_buckets" as x ("tenant_id", "variant_id", "location_id", "bin_id", "lot_id", "on_hand")
      values (move_stock.tenant, move_stock.variant, move_stock.location, v_part.bin, v_part.lot, v_part.quantity)
      on conflict ("variant_id", "location_id", "bin_id", "lot_id") do update
        set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
      returning x."on_hand" into v_bucket;
      if v_bucket < 0 and v_strict then
        raise exception 'not enough stock in this bin or lot' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
      end if;
      if v_part.bin is not null and (select x."hold" from "better_supabase"."stock_bins" x where x."id" = v_part.bin) then
        v_held := v_held + v_part.quantity;
      end if;
    end if;
  end loop;

  v_suffix := case when v_unit = 'item' and v_scale = 0 then '' else ':' || v_unit || ':' || v_scale::text end;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter',
    case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'expired' then 'stock:adjustments' when 'scrap' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' when 'consumption' then 'stock:production' when 'production' then 'stock:production' end || v_suffix, case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'expired' then 'Adjustments' when 'scrap' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' when 'consumption' then 'Production' when 'production' then 'Production' end, v_unit, v_scale,
    null, null, null, true, 'inventory.read', 'inventory', null), 'amount', -(move_stock.quantity * v_factor)::bigint));

  if v_costing = 'average' and move_stock.reason not in ('transfer_in', 'transfer_out') then
    if move_stock.detail ? 'currency' and upper(move_stock.detail ->> 'currency') is distinct from v_currency then
      raise exception 'the unit cost is in another currency than the variant''s costing' using errcode = '22023', hint = 'INVENTORY_COST_CURRENCY_MISMATCH';
    end if;
    select coalesce(sum(x."on_hand"), 0) into v_total from "better_supabase"."stock_levels" x where x."variant_id" = move_stock.variant;
    v_value_account := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value', 'stock_value:' || move_stock.variant::text, 'Stock value',
      v_currency, 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
      jsonb_build_object('variantId', move_stock.variant));
    v_balance := coalesce((select y."balance" from "better_supabase"."ledger_balances" y where y."account_id" = v_value_account), 0);
    if move_stock.quantity > 0 then
      v_value := round(move_stock.quantity * coalesce(nullif(move_stock.detail ->> 'unitCost', '')::numeric, v_average, 0));
    elsif v_total + move_stock.quantity <= 0 then
      v_value := -v_balance;
    else
      v_value := -round(-move_stock.quantity * coalesce(v_average, 0));
    end if;
    if v_value <> 0 then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('account', v_value_account, 'amount', v_value),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_value_counter', case move_stock.reason when 'receipt' then 'stock_value:suppliers' when 'sale' then 'stock_value:cogs' when 'return' then 'stock_value:cogs' when 'consumption' then 'stock_value:production' when 'production' then 'stock_value:production' else 'stock_value:adjustments' end || ':' || v_currency,
          case move_stock.reason when 'receipt' then 'Stock purchases' when 'sale' then 'Cost of goods sold' when 'return' then 'Cost of goods sold' when 'consumption' then 'Work in progress' when 'production' then 'Work in progress' else 'Stock adjustments' end || ' ' || v_currency, v_currency, 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null),
          'amount', -v_value));
    end if;
    update "better_supabase"."stock_items" x set "average_cost" = case when v_total + move_stock.quantity > 0
        then round((v_balance + v_value)::numeric / (v_total + move_stock.quantity), 6) else x."average_cost" end,
      "updated_at" = now()
    where x."variant_id" = move_stock.variant;
  end if;

  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason, v_lines,
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_strip_nulls(jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason,
      'quantity', move_stock.quantity::text, 'unit', nullif(v_unit, 'item'))));
  if v_value <> 0 then
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('stock_movement', v_id::text);
  end if;
  end if;
  if v_serials is not null then
    update "better_supabase"."stock_serials" x set "movement_id" = v_id
    where x."variant_id" = move_stock.variant and x."serial" = any (v_serials);
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand", "held")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity, greatest(v_held, 0))
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "held" = greatest(x."held" + v_held, 0), "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0 and v_strict then
    select v_on_hand - coalesce(sum(y."on_hand"), 0) into v_unbinned from "better_supabase"."stock_buckets" y
    where y."variant_id" = move_stock.variant and y."location_id" = move_stock.location;
    if v_on_hand < 0 or v_unbinned < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out', 'consumption')) then
      raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
    end if;
  end if;
  if v_point is not null and (v_after - move_stock.quantity + v_held) > v_point and v_after <= v_point then
    perform "better_supabase".emit_event('stock.reorder_point_reached', jsonb_build_object('organizationId', move_stock.tenant, 'subjectType', 'product_variant', 'subjectId', move_stock.variant::text, 'variantId', move_stock.variant, 'locationId', move_stock.location, 'available', v_after::text, 'reorderPoint', v_point::text), 'stock-levels/' || move_stock.variant::text || '/' || move_stock.location::text, (move_stock.tenant)::text, null, 'better-supabase/inventory');
  end if;
  if move_stock.quantity > 0 then
    perform "better_supabase"."fill_backorders"(move_stock.tenant, move_stock.variant, move_stock.location);
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_due_acknowledgements()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item record;
  v_claims text;
  v_count integer := 0;
begin
  for v_item in
    select y.tenant, y.subject_type, y.subject_id, y.version_id, y.user_id,
      (vv."created_at")::date + y.due_in_days as due_on
    from (
      select q.*, "better_supabase"."current_acknowledgement_version"(q.tenant, q.subject_type, q.subject_id) as version_id
      from (
        select x."tenant_id" as tenant, x."subject_type" as subject_type, x."subject_id" as subject_id,
          m."user_id" as user_id, min(x."due_in_days") as due_in_days
        from "better_supabase"."acknowledgement_assignments" x
        join "public"."memberships" m on m."organization_id" = x."tenant_id"
        where x."due_in_days" is not null and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" in ('*', (select r."key" from "better_supabase"."roles" r where r."id" = m."role")))
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
        group by x."tenant_id", x."subject_type", x."subject_id", m."user_id"
      ) q
    ) y
    join "better_supabase"."versions" vv on vv."id" = y.version_id
    where (vv."created_at")::date + y.due_in_days < current_date
      and not exists (
        select 1 from "better_supabase"."acknowledgements" k
        where k."subject_type" = y.subject_type and k."subject_id" = y.subject_id
          and k."version_id" = y.version_id and k."user_id" = y.user_id
      )
      and not exists (
        select 1 from "better_supabase"."acknowledgement_notices" nt
        where nt."subject_type" = y.subject_type and nt."subject_id" = y.subject_id
          and nt."version_id" = y.version_id and nt."user_id" = y.user_id
      )
  loop
    insert into "better_supabase"."acknowledgement_notices" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id")
    values (v_item.tenant, v_item.subject_type, v_item.subject_id, v_item.version_id, v_item.user_id)
    on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing;
    if found then
      perform "better_supabase".emit_event('acknowledgement.reminded', jsonb_build_object('organizationId', v_item.tenant, 'subjectType', v_item.subject_type, 'subjectId', v_item.subject_id, 'versionId', v_item.version_id, 'userId', v_item.user_id, 'dueOn', v_item.due_on), 'acknowledgements/' || v_item.subject_type || '/' || v_item.subject_id, (v_item.tenant)::text, null, 'better-supabase/acknowledgements');
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'acknowledgement.reminded',
      'tenant', v_item.tenant,
      'actor', null,
      'subject_type', v_item.subject_type,
      'subject_id', v_item.subject_id,
      'summary', coalesce("better_supabase"."subject_title"(v_item.subject_type, v_item.subject_id), v_item.subject_type),
      'recipients', to_jsonb(array[v_item.user_id]),
      'key', 'acknowledgement.reminded:' || v_item.subject_type || ':' || v_item.subject_id || ':' || v_item.version_id::text || ':' || v_item.user_id::text,
      'data', jsonb_build_object('versionId', v_item.version_id, 'dueOn', v_item.due_on)
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_due_case_effectiveness()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."cases"%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  perform "better_supabase"."schedule_case_effectiveness"(x."id") from "better_supabase"."cases" x
  where x."status" = 'open' and x."archived_at" is null and x."effective" is null
    and x."effectiveness_due_on" is null
    and exists (select 1 from "better_supabase"."case_actions" y where y."case_id" = x."id" and y."required");
  for v_row in
    select * from "better_supabase"."cases" x
    where x."status" = 'open' and x."archived_at" is null and x."effective" is null
      and x."effectiveness_due_on" <= current_date
      and x."effectiveness_notified_for" is distinct from x."effectiveness_due_on"
    for update skip locked
  loop
    perform "better_supabase".emit_event('case.effectiveness_date_reached', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'ownerId', v_row."owner_id", 'effectivenessDueOn', v_row."effectiveness_due_on"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.effectiveness_date_reached',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case effectiveness check due',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', (select y."key" from "better_supabase"."case_kinds" y where y."id" = v_row."kind_id"), 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'ownerId', v_row."owner_id", 'effectivenessDueOn', v_row."effectiveness_due_on")
  );
    if v_row."owner_id" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'case.effectiveness_date_reached',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', 'case',
        'subject_id', v_row."id"::text,
        'summary', v_row."number" || ' ' || v_row."title",
        'recipients', to_jsonb(array[v_row."owner_id"]),
        'key', 'case.effectiveness_date_reached:' || v_row."id"::text || ':' || v_row."effectiveness_due_on"::text,
        'data', jsonb_build_object('caseId', v_row."id", 'effectivenessDueOn', v_row."effectiveness_due_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."cases" x set "effectiveness_notified_for" = v_row."effectiveness_due_on" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_due_drive_reviews()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_count integer := 0;
  v_claims text;
begin
  for v_node in
    select * from "better_supabase"."drive_nodes" x
    where x."document_status" = 'effective' and x."next_review_on" <= current_date
      and x."review_notified_for" is distinct from x."next_review_on" and x."deleted_at" is null
    for update skip locked
  loop
    perform "better_supabase".emit_event('drive_node.review_requested', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'ownerId', v_node."document_owner_id", 'nextReviewOn', v_node."next_review_on"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
    if v_node."document_owner_id" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'drive.document_review_due',
        'tenant', v_node."tenant_id",
        'actor', null,
        'subject_type', 'drive_node',
        'subject_id', v_node."id"::text,
        'summary', v_node."document_number" || ' ' || v_node."name",
        'recipients', to_jsonb(array[v_node."document_owner_id"]),
        'key', 'drive.document_review_due:' || v_node."id"::text || ':' || v_node."next_review_on"::text,
        'data', jsonb_build_object('nodeId', v_node."id", 'documentNumber', v_node."document_number", 'nextReviewOn', v_node."next_review_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."drive_nodes" x set "review_notified_for" = v_node."next_review_on" where x."id" = v_node."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_due_risk_reviews()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."risks" x
    where x."status" <> 'closed' and x."archived_at" is null
      and x."next_review_on" <= current_date
      and x."review_notified_for" is distinct from x."next_review_on"
    for update skip locked
  loop
    perform "better_supabase".emit_event('risk.review_date_reached', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'ownerId', v_row."owner_id", 'nextReviewOn', v_row."next_review_on"), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.review_date_reached',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'risk review due',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'ownerId', v_row."owner_id", 'nextReviewOn', v_row."next_review_on")
  );
    if v_row."owner_id" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'risk.review_date_reached',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', 'risk',
        'subject_id', v_row."id"::text,
        'summary', v_row."number" || ' ' || v_row."title",
        'recipients', to_jsonb(array[v_row."owner_id"]),
        'key', 'risk.review_date_reached:' || v_row."id"::text || ':' || v_row."next_review_on"::text,
        'data', jsonb_build_object('riskId', v_row."id", 'nextReviewOn', v_row."next_review_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."risks" x set "review_notified_for" = v_row."next_review_on" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_expiring_qualifications()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."qualifications"%rowtype;
  v_type "better_supabase"."qualification_types"%rowtype;
  v_status text;
  v_count integer := 0;
  v_claims text;
begin
  for v_row in
    select x.* from "better_supabase"."qualifications" x
    where x."revoked_at" is null and x."expires_on" is not null
      and x."expires_on" <= current_date + 30
      and x."notified_status" is distinct from (case when x."expires_on" < current_date then 'expired' else 'expiring' end)
      and not exists (
        select 1 from "better_supabase"."qualifications" n
        where n."type_id" = x."type_id" and n."holder_type" = x."holder_type" and n."holder_id" = x."holder_id"
          and n."id" <> x."id" and n."revoked_at" is null
          and (n."expires_on" is null or n."expires_on" > x."expires_on")
      )
    order by x."expires_on"
    for update of x skip locked
  loop
    v_status := case when v_row."expires_on" < current_date then 'expired' else 'expiring' end;
    select * into v_type from "better_supabase"."qualification_types" y where y."id" = v_row."type_id";
    if v_status = 'expired' then
      perform "better_supabase".emit_event('qualification.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'qualificationId', v_row."id", 'qualificationTypeId', v_row."type_id", 'typeKey', v_type."key", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'expiresOn', v_row."expires_on"), 'qualifications/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/qualifications');
    else
      perform "better_supabase".emit_event('qualification.expiry_warned', jsonb_build_object('organizationId', v_row."tenant_id", 'qualificationId', v_row."id", 'qualificationTypeId', v_row."type_id", 'typeKey', v_type."key", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'expiresOn', v_row."expires_on"), 'qualifications/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/qualifications');
    end if;
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'qualification.' || v_status,
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', 'qualification_type',
        'subject_id', v_type."id"::text,
        'summary', v_type."name",
        'recipients', case when v_row."holder_type" = 'member' then jsonb_build_array(v_row."holder_id") else (select coalesce(jsonb_agg(mn."user_id"), '[]'::jsonb) from "public"."memberships" mn where mn."organization_id" = v_row."tenant_id" and coalesce(better_supabase.can_user(mn."user_id", 'tenant', v_row."tenant_id", 'qualifications.manage'), false)) end,
        'key', 'qualification.' || v_status || ':' || v_row."id"::text,
        'data', jsonb_build_object('qualificationId', v_row."id", 'typeKey', v_type."key", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'expiresOn', v_row."expires_on")
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    update "better_supabase"."qualifications" x set "notified_status" = v_status where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_overdue_evidence_tasks()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "better_supabase"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "better_supabase"."controls" y where y."id" = v_task."control_id";
    perform "better_supabase".emit_event('evidence_task.missed', jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on"), 'evidence-tasks/' || v_task."id"::text, (v_task."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'evidence_task.missed',
    category => 'data',
    target_type => 'evidence_task',
    record_id => v_task."id"::text,
    summary => 'evidence task overdue: ' || v_task."title",
    tenant => (v_task."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on")
  );
    if coalesce(v_task."assignee_id", v_owner) is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'evidence_task.missed',
        'tenant', v_task."tenant_id",
        'actor', null,
        'subject_type', 'control',
        'subject_id', v_task."control_id"::text,
        'summary', v_task."title",
        'recipients', to_jsonb(array[coalesce(v_task."assignee_id", v_owner)]),
        'key', 'evidence_task.missed:' || v_task."id"::text || ':' || v_task."due_on"::text,
        'data', jsonb_build_object('evidenceTaskId', v_task."id", 'dueOn', v_task."due_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_overdue_inspections()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_claims text;
  v_to uuid[];
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."inspections" x
    where x."status" in ('planned', 'in_progress')
      and x."planned_end" < current_date
      and x."overdue_notified_for" is distinct from x."planned_end"
    for update skip locked
  loop
    select coalesce(array_agg(y."user_id"), '{}'::uuid[]) into v_to from "better_supabase"."inspection_members" y
    where y."inspection_id" = v_row."id" and y."role" = 'lead';
    if cardinality(v_to) = 0 then
      select coalesce(array_agg(y."user_id"), '{}'::uuid[]) into v_to from "better_supabase"."inspection_members" y
      where y."inspection_id" = v_row."id" and y."role" = 'auditor';
    end if;
    if cardinality(v_to) > 0 then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inspection.overdue',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', 'inspection',
        'subject_id', v_row."id"::text,
        'summary', v_row."number" || ' ' || v_row."title",
        'recipients', to_jsonb(v_to),
        'key', 'inspection.overdue:' || v_row."id"::text || ':' || v_row."planned_end"::text,
        'data', jsonb_build_object('inspectionId', v_row."id", 'plannedEnd', v_row."planned_end")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."inspections" x set "overdue_notified_for" = v_row."planned_end" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.observation_insert (
  p_tenant       uuid,
  p_definition   uuid,
  p_subject_type text,
  p_subject_id   text,
  p_value        jsonb,
  p_observed_at  timestamp with time zone,
  p_details      jsonb,
  p_source       text,
  p_external_id  text,
  p_submission   uuid,
  p_performer    uuid,
  p_replaces     uuid,
  p_fields       jsonb
)
  RETURNS better_supabase.observations
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_row "better_supabase"."observations"%rowtype;
  v_at timestamptz := coalesce(p_observed_at, now());
  v_number numeric;
  v_text text;
  v_code text;
  v_components jsonb;
  v_flag text := 'normal';
  v_component jsonb;
  v_key text;
  v_part numeric;
  v_part_flag text;
  v_recipients jsonb;
  v_claims text;
begin
  select * into v_def from "better_supabase"."observation_definitions" d where d."id" = p_definition;
  if not found then
    raise exception 'observation definition not found' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
  end if;
  if v_def."archived_at" is not null then
    raise exception 'the observation definition is archived' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_ARCHIVED';
  end if;
  if v_at > now() + interval '5 minutes' then
    raise exception 'observed_at is in the future' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if p_details is not null and jsonb_typeof(p_details) <> 'object' then
    raise exception 'details is an object of method, device and note' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    raise exception 'an observation needs a value' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
  end if;
  case v_def."value_type"
    when 'number', 'integer' then
      if jsonb_typeof(p_value) <> 'number' then
        raise exception '%s takes a number', v_def."key" using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_number := (p_value #>> '{}')::numeric;
      if v_def."value_type" = 'integer' and v_number <> trunc(v_number) then
        raise exception 'the value is a whole number' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      if v_def."decimals" is not null then
        v_number := round(v_number, v_def."decimals");
      end if;
      if v_number < v_def."valid_low" or v_number > v_def."valid_high" then
        raise exception 'the value is outside the definition''s valid range' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_flag := "better_supabase"."observation_flag"(v_number, v_def."reference_low", v_def."reference_high", v_def."critical_low", v_def."critical_high");
    when 'boolean' then
      if jsonb_typeof(p_value) <> 'boolean' then
        raise exception 'the value is true or false' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_code := p_value #>> '{}';
    when 'code' then
      v_code := nullif(trim(p_value #>> '{}'), '');
      if jsonb_typeof(p_value) <> 'string' or v_code is null or length(v_code) > 200 then
        raise exception 'the value is a code of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
    when 'text' then
      v_text := nullif(trim(p_value #>> '{}'), '');
      if jsonb_typeof(p_value) <> 'string' or v_text is null or length(v_text) > 4000 then
        raise exception 'the value is a text of at most 4000 characters' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
    else
      if jsonb_typeof(p_value) <> 'object' then
        raise exception 'the value is an object of components' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      if exists (
        select 1 from jsonb_object_keys(p_value) k
        where not exists (select 1 from jsonb_array_elements(coalesce(v_def."components", '[]'::jsonb)) c where c ->> 'key' = k)
      ) then
        raise exception 'the value names a component the definition doesn''t have' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_components := '{}'::jsonb;
      for v_component in select c from jsonb_array_elements(coalesce(v_def."components", '[]'::jsonb)) c loop
        v_key := v_component ->> 'key';
        if not (p_value ? v_key) or jsonb_typeof(p_value -> v_key) = 'null' then
          if coalesce((v_component ->> 'optional')::boolean, false) then
            continue;
          end if;
          raise exception 'the value needs the %s component', v_key using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
        end if;
        if jsonb_typeof(p_value -> v_key) <> 'number' then
          raise exception 'each component is a number' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
        end if;
        v_part := (p_value ->> v_key)::numeric;
        if v_component ? 'decimals' then
          v_part := round(v_part, (v_component ->> 'decimals')::integer);
        elsif v_def."decimals" is not null then
          v_part := round(v_part, v_def."decimals");
        end if;
        if v_part < (v_component ->> 'validLow')::numeric or v_part > (v_component ->> 'validHigh')::numeric then
          raise exception 'a component is outside its valid range' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
        end if;
        v_part_flag := "better_supabase"."observation_flag"(v_part, (v_component ->> 'referenceLow')::numeric, (v_component ->> 'referenceHigh')::numeric, (v_component ->> 'criticalLow')::numeric, (v_component ->> 'criticalHigh')::numeric);
        if (case v_part_flag when 'critical_low' then 2 when 'critical_high' then 2 when 'low' then 1 when 'high' then 1 else 0 end) > (case v_flag when 'critical_low' then 2 when 'critical_high' then 2 when 'low' then 1 when 'high' then 1 else 0 end) then
          v_flag := v_part_flag;
        end if;
        v_components := v_components || jsonb_build_object(v_key, v_part);
      end loop;
      if v_components = '{}'::jsonb then
        raise exception 'the value needs at least one component' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
  end case;
  if p_replaces is null then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_observation_record"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using p_tenant, p_subject_type, p_subject_id, v_def."key";
    end if;
  end;
  end if;
  insert into "better_supabase"."observations" ("tenant_id", "definition_id", "subject_type", "subject_id", "observed_at", "value_number", "value_text", "value_code", "components", "flag", "replaces_id", "method", "device", "source", "external_id", "submission_id", "performer_id", "note")
  values (p_tenant, v_def."id", p_subject_type, p_subject_id, v_at, v_number, v_text, v_code, v_components, v_flag, p_replaces, left(nullif(trim(p_details ->> 'method'), ''), 200), left(nullif(trim(p_details ->> 'device'), ''), 200), p_source, p_external_id, p_submission, p_performer, left(nullif(trim(p_details ->> 'note'), ''), 4000))
  returning * into v_row;
  if p_replaces is null then
    perform "better_supabase".emit_event('observation.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'flag', v_row."flag", 'source', v_row."source"), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation.recorded',
    category => 'data',
    target_type => 'observation',
    record_id => v_row."id"::text,
    target_label => v_def."title",
    summary => 'Observation recorded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'flag', v_row."flag", 'source', v_row."source")
  );
  end if;
  if v_row."flag" in ('critical_low', 'critical_high') then
    perform "better_supabase".emit_event('observation.critical_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'flag', v_row."flag"), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
    select coalesce(jsonb_agg(distinct m."user_id"), '[]'::jsonb) into v_recipients
    from "better_supabase"."subject_members" m
    where m."subject_type" = v_row."subject_type"
      and m."subject_id" = v_row."subject_id"
      and m."tenant_id"::text = v_row."tenant_id"::text
      and m."role" = 'lead'
      and m."user_id" is not null
      and (m."starts_on" is null or m."starts_on" <= current_date)
      and (m."ends_on" is null or m."ends_on" >= current_date);
    if jsonb_array_length(v_recipients) > 0 then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'observation.critical_recorded',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', v_row."subject_type",
        'subject_id', v_row."subject_id",
        'summary', v_def."title" || ' is ' || replace(v_row."flag", '_', ' '),
        'recipients', v_recipients,
        'key', 'observation.critical_recorded:' || v_row."id"::text,
        'data', jsonb_build_object('observationId', v_row."id", 'definitionKey', v_def."key", 'flag', v_row."flag")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
  end if;
  if p_replaces is null then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_observation_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_emergency_access (
  subject_type text,
  subject_id   text,
  reason       text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_row "better_supabase"."access_requests"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to open emergency access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  if length(btrim(coalesce(open_emergency_access.reason, ''))) < 10 then
    raise exception 'say why you need emergency access, in at least 10 characters' using errcode = '22023', hint = 'ACCESS_REQUEST_REASON_REQUIRED';
  end if;
  if not (open_emergency_access.subject_type = any (array['customer', 'drive_node']::text[])) or (case open_emergency_access.subject_type
      when 'customer' then not ('read' = any (array['read', 'write']::text[]))
      when 'drive_node' then not ('read' = any (array['read']::text[]))
      else true end) then
    raise exception 'this record or action can''t be requested' using errcode = '22023', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  v_tenant := "better_supabase"."record_team_tenant"(open_emergency_access.subject_type, open_emergency_access.subject_id);
  if v_tenant is null then
    raise exception 'record not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid()) or not coalesce(better_supabase.can('tenant', v_tenant, 'access_requests.emergency'), false) then
    raise exception 'not allowed to open emergency access here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "target", "subject_type", "subject_id", "action", "emergency", "reason", "duration")
  values (v_tenant, v_me, 'record', open_emergency_access.subject_type, open_emergency_access.subject_id, 'read', true, btrim(open_emergency_access.reason), interval '8 hours')
  returning * into v_row;
  perform "better_supabase"."grant_access_request"(v_row."id");
  select * into v_row from "better_supabase"."access_requests" r where r."id" = v_row."id";
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'access_request.emergency_opened',
      'tenant', v_tenant,
      'actor', v_me,
      'subject_type', open_emergency_access.subject_type,
      'subject_id', open_emergency_access.subject_id,
      'summary', btrim(open_emergency_access.reason),
      'recipients', to_jsonb("better_supabase"."record_team_leads"(open_emergency_access.subject_type, open_emergency_access.subject_id)),
      'permission', 'access_requests.review',
      'watchers', false,
      'key', 'access_request.emergency_opened:' || v_row."id"::text,
      'data', jsonb_build_object('accessRequestId', v_row."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  perform "better_supabase".emit_event('access_request.emergency_opened', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', v_row."reason"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.emergency_opened',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', v_row."reason")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'granted', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_incident (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_incident.tenant, 'incidents.write'), false)) then
    raise exception 'not allowed to open incidents' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if jsonb_typeof(open_incident.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if nullif(trim(open_incident.attrs ->> 'title'), '') is null then
    raise exception 'an incident needs a title' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if coalesce(open_incident.attrs ->> 'severity', 'sev3') not in ('sev1', 'sev2', 'sev3', 'sev4') then
    raise exception 'severity must be sev1, sev2, sev3 or sev4' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if open_incident.attrs ? 'commanderId' and open_incident.attrs ->> 'commanderId' is not null
    and not exists (select 1 from "public"."memberships" mm where mm."organization_id" = open_incident.tenant and mm."user_id" = (open_incident.attrs ->> 'commanderId')::uuid) then
    raise exception 'the commander must be a member of the organization' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  insert into "better_supabase"."incidents" ("tenant_id", "title", "description", "severity", "public", "commander_id", "created_by")
  values (open_incident.tenant, trim(open_incident.attrs ->> 'title'), open_incident.attrs ->> 'description',
    coalesce(open_incident.attrs ->> 'severity', 'sev3'), coalesce((open_incident.attrs ->> 'public')::boolean, false),
    (open_incident.attrs ->> 'commanderId')::uuid, auth.uid())
  returning * into v_row;
  if nullif(trim(open_incident.attrs ->> 'message'), '') is not null then
    insert into "better_supabase"."incident_updates" ("tenant_id", "incident_id", "status", "body", "public", "author_id")
    values (v_row."tenant_id", v_row."id", v_row."status", trim(open_incident.attrs ->> 'message'), v_row."public", auth.uid());
  end if;
  perform "better_supabase"."incident_apply_impacts"(v_row."id", open_incident.attrs -> 'impacts');
  perform "better_supabase".emit_event('incident.opened', jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."id", 'title', v_row."title", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public"), 'incidents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'incident.opened',
    category => 'data',
    target_type => 'incident',
    record_id => v_row."id"::text,
    summary => 'opened incident ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'incidentId', v_row."id", 'title', v_row."title", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public")
  );
  if v_row."commander_id" is not null and v_row."commander_id" is distinct from auth.uid() then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'incident.opened',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'incident',
      'subject_id', v_row."id"::text,
      'summary', v_row."title",
      'recipients', to_jsonb(array[v_row."commander_id"]),
      'key', 'incident.opened:' || v_row."id"::text,
      'data', jsonb_build_object('incidentId', v_row."id", 'severity', v_row."severity")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public", 'commanderId', v_row."commander_id", 'startedAt', v_row."started_at", 'resolvedAt', v_row."resolved_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."incident_status_components" ic on ic."id" = im."component_id" where im."incident_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_due_rent (
  tenant   uuid    DEFAULT NULL::uuid,
  through  date    DEFAULT NULL::date,
  max_rows integer DEFAULT 500
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_through date := coalesce(post_due_rent.through, current_date);
  v_max integer := least(greatest(coalesce(post_due_rent.max_rows, 500), 1), 5000);
  v_count integer := 0;
  v_row "better_supabase"."leases"%rowtype;
  v_charge "better_supabase"."lease_charges"%rowtype;
  v_n integer;
  v_start date;
  v_end date;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if post_due_rent.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'posting rent for every organization needs the service role' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_due_rent.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  <<periods>>
  for v_row in
    select * from "better_supabase"."leases" x
    where x."status" = 'active' and x."starts_on" <= v_through
      and (post_due_rent.tenant is null or x."tenant_id" = post_due_rent.tenant)
    order by x."id"
    for update skip locked
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" = v_start) then
        exit periods when v_count >= v_max;
        v_end := least((v_row."starts_on" + (v_n + 1) * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date, coalesce(v_row."ends_on", 'infinity'::date));
        v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.rent',
          jsonb_build_array(
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', v_row."rent"),
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."rent")),
          'leases', v_row."id"::text, 'Rent from ' || v_start::text,
          'leases.rent:' || v_row."id"::text || ':' || v_start::text, v_start::timestamptz,
          jsonb_build_object('leaseId', v_row."id", 'periodStart', v_start, 'periodEnd', v_end));
        insert into "better_supabase"."lease_charges" ("tenant_id", "lease_id", "period_start", "period_end", "amount", "currency", "transaction_id")
        values (v_row."tenant_id", v_row."id", v_start, v_end, v_row."rent", v_row."currency", v_tx)
        returning * into v_charge;
        if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('lease_rent', v_charge."id"::text);
  end if;
        perform "better_supabase".emit_event('lease.charged', jsonb_build_object('organizationId', v_charge."tenant_id", 'id', v_charge."id", 'leaseId', v_charge."lease_id", 'periodStart', v_charge."period_start", 'periodEnd', v_charge."period_end", 'amount', v_charge."amount"::text, 'currency', v_charge."currency", 'transactionId', v_charge."transaction_id"), 'lease-charges/' || v_charge."id"::text, (v_charge."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.charged',
    category => 'billing',
    target_type => 'lease_charge',
    record_id => v_charge."id"::text,
    summary => 'posted rent from ' || v_charge."period_start"::text,
    tenant => (v_charge."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_charge."tenant_id", 'id', v_charge."id", 'leaseId', v_charge."lease_id", 'periodStart', v_charge."period_start", 'periodEnd', v_charge."period_end", 'amount', v_charge."amount"::text, 'currency', v_charge."currency", 'transactionId', v_charge."transaction_id")
  );
        v_count := v_count + 1;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_shifts (
  tenant     uuid,
  from_date  date,
  until_date date,
  team_id    uuid DEFAULT NULL::uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_count integer := 0;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', publish_shifts.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to publish shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if publish_shifts.from_date is null or publish_shifts.until_date is null or publish_shifts.until_date < publish_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_row in
    update "better_supabase"."shifts" x set "status" = 'published', "published_at" = now(), "updated_at" = now()
    where x."tenant_id" = publish_shifts.tenant
      and x."status" = 'draft'
      and x."starts_at" >= publish_shifts.from_date::timestamp at time zone 'UTC'
      and x."starts_at" < (publish_shifts.until_date + 1)::timestamp at time zone 'UTC'
      and (publish_shifts.team_id is null or x."team_id" = publish_shifts.team_id)
    returning x.*
  loop
    v_count := v_count + 1;
    perform "better_supabase".emit_event('shift.published', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'shifts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift.published',
    category => 'data',
    target_type => 'shift',
    record_id => v_row."id"::text,
    summary => 'Shift published',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
    if jsonb_array_length(coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb)) > 0 then
      if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift.published',
      'tenant', v_row."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_row."id"::text,
      'summary', 'Your shift is published',
      'recipients', coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb),
      'key', 'shift.published:' || v_row."id"::text,
      'data', jsonb_build_object('startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
    end if;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_invoice_payment (
  invoice   uuid,
  amount    bigint,
  currency  text,
  paid_at   timestamp with time zone,
  method    text,
  reference text,
  note      text                     DEFAULT NULL::text,
  actor     jsonb                    DEFAULT NULL::jsonb,
  reason    text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_payment uuid;
  v_reference text;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = record_invoice_payment.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice takes payments' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
  end if;
  if coalesce(record_invoice_payment.amount, 0) = 0 then
    raise exception 'a payment has an amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
  end if;
  if upper(record_invoice_payment.currency) is distinct from v_row."currency" then
    raise exception 'a payment must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
  end if;
  if v_row."direction" = 'purchase' and v_row."purchase_order_id" is not null and record_invoice_payment.amount > 0
    and "better_supabase"."invoice_match_result"(v_row."id") ->> 'status' <> 'matched'
    and not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.override_match'), false)) then
    raise exception 'the bill doesn''t match its purchase order and receipts; someone with invoices.override_match can pay it' using errcode = '55000', hint = 'INVOICE_MATCH_FAILED';
  end if;
  if record_invoice_payment.actor is not null then
    if jsonb_typeof(record_invoice_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(record_invoice_payment.actor ->> 'ip', '')::inet, nullif(record_invoice_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(record_invoice_payment.actor::text, ''), true);
  -- A recorded reference is a replay that adds nothing, so it skips the check.
  v_reference := nullif(trim(record_invoice_payment.reference), '');
  if v_reference is not null and exists (
    select 1 from "better_supabase"."ledger_transactions" y
    where y."tenant_id" = v_row."tenant_id" and y."idempotency_key" = 'invoice-payment:' || v_reference
  ) then
    return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
  end if;
  if record_invoice_payment.amount < 0 and v_row."paid_total" + record_invoice_payment.amount < 0 then
    raise exception 'a refund can''t exceed what was paid' using errcode = '23514', hint = 'INVOICE_REFUND_TOO_LARGE';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_payment"(uuid, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::bigint)', v_hook::oid::regproc)
        using v_row."id", record_invoice_payment.amount;
    end if;
  end;
  v_was := v_row."status";
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(record_invoice_payment.reason), ''), ''), true);
  v_payment := "better_supabase"."ledger_post"(v_row."tenant_id", case when record_invoice_payment.amount < 0 then 'invoice.refund' else 'invoice.payment' end,
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -record_invoice_payment.amount),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'cash',
      case when v_row."direction" = 'purchase' then 'invoices:paid:' || v_row."currency" else 'invoices:cash:' || v_row."currency" end, 'Invoice payments ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', record_invoice_payment.amount)),
    'invoices', v_row."id"::text, null,
    case when v_reference is not null then 'invoice-payment:' || v_reference end, coalesce(record_invoice_payment.paid_at, now()),
    jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row."id", 'method', record_invoice_payment.method, 'reference', v_reference, 'note', nullif(trim(record_invoice_payment.note), ''))));
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
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_payment', v_payment::text);
  end if;
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.payment_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', v_payment, 'amount', record_invoice_payment.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."status" = 'paid' and v_was <> 'paid' then
    perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_payment"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_row."id", v_payment;
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
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

CREATE OR REPLACE FUNCTION better_supabase.record_payment (
  order_id  uuid,
  provider  text,
  reference text,
  status    text,
  currency  text,
  amount    bigint,
  captured  bigint DEFAULT 0,
  refunded  bigint DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_order record;
  v_line record;
  v_id uuid := record_payment.order_id;
  v_paid bigint;
  v_newly boolean := false;
  v_seq bigint;
  v_number text;
  v_invoice jsonb;
  v_claims text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_id is null then
    select x."order_id" into v_id from "better_supabase"."order_payments" x
    where x."provider" = record_payment.provider and x."reference" = record_payment.reference;
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if record_payment.status is null or record_payment.status not in ('requires_action', 'processing', 'authorized', 'succeeded', 'failed', 'canceled') then
    raise exception 'unknown payment status' using errcode = '22023', hint = 'ORDERS_PAYMENT_STATUS_INVALID';
  end if;
  if record_payment.currency is distinct from v_order.currency then
    raise exception 'the payment is in another currency than the order' using errcode = '22023', hint = 'ORDERS_CURRENCY_MISMATCH';
  end if;
  if coalesce(record_payment.amount, -1) < 0 or coalesce(record_payment.captured, 0) < 0 or coalesce(record_payment.refunded, 0) < 0 then
    raise exception 'payment amounts are zero or more' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
  end if;
  insert into "better_supabase"."order_payments" as x ("tenant_id", "order_id", "provider", "reference", "status", "currency",
    "amount", "captured", "refunded")
  values (v_order.tenant, v_order.id, record_payment.provider, record_payment.reference, record_payment.status, record_payment.currency,
    record_payment.amount, coalesce(record_payment.captured, 0), coalesce(record_payment.refunded, 0))
  on conflict ("provider", "reference") do update set
    "status" = case when x."status" in ('succeeded', 'failed', 'canceled') and excluded."status" not in ('succeeded', 'failed', 'canceled') then x."status" else excluded."status" end,
    "amount" = excluded."amount",
    "captured" = greatest(x."captured", excluded."captured"),
    "refunded" = greatest(x."refunded", excluded."refunded"),
    "updated_at" = now()
  where x."order_id" = excluded."order_id";
  if not found then
    raise exception 'this payment reference belongs to another order' using errcode = '23505', hint = 'ORDERS_PAYMENT_CONFLICT';
  end if;
  select coalesce(sum(x."captured"), 0) into v_paid from "better_supabase"."order_payments" x
  where x."order_id" = v_order.id and x."status" = 'succeeded';
  update "better_supabase"."orders" x set "paid_total" = v_paid, "updated_at" = now() where x."id" = v_order.id;
  if v_order.status::text in ('pending_payment', 'confirmed') and v_paid >= v_order.total then
    perform "better_supabase"."order_transition"(v_order.id, 'paid');
    if not better_supabase.import_run() is not null then
    for v_line in
      select x."id" as id, x."variant_id" as variant, x."quantity" as quantity,
        x."location_id" as location, x."reservation_id" as reservation
      from "better_supabase"."order_lines" x
      where x."order_id" = v_order.id and x."reservation_id" is not null
      order by x."position"
    loop
      begin
        v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."commit_reservation"(v_line.reservation);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      exception when sqlstate '55000' then
        begin
          v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."release_reservation"(v_line.reservation);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
          perform "better_supabase"."move_stock"(v_order.tenant, v_line.variant, v_line.location, -v_line.quantity, 'sale', 'order', v_order.id::text, null, null);
        exception when sqlstate '23514' then
          update "better_supabase"."order_lines" x set "backordered" = true where x."id" = v_line.id;
        end;
      end;
    end loop;
    end if;
    v_invoice := "better_supabase"."create_invoice"(v_order.tenant,
      jsonb_build_object('title', 'Order ' || v_order.number, 'currency', v_order.currency, 'termsDays', 0,
        'origin', jsonb_build_object('type', 'order', 'id', v_order.id::text)),
      (select coalesce(jsonb_agg(jsonb_build_object(
      'description', case when l."quantity" = 1 then l."title" else l."title" || ' x ' || l."quantity"::text end,
      'quantity', 1, 'unitAmount', (l."total" - l."tax")::text, 'currency', v_order.currency,
      'taxRateBps', case when (l."total" - l."tax") > 0 then round(l."tax" * 10000.0 / (l."total" - l."tax"))::integer else 0 end,
      'product', case when l."variant_id" is null then null else jsonb_build_object('type', 'product_variant', 'id', l."variant_id"::text) end)
      order by l."position"), '[]'::jsonb)
    from "better_supabase"."order_lines" l where l."order_id" = v_order.id)
    || (select case when x."shipping_total" > 0 then jsonb_build_array(jsonb_build_object('description', 'Shipping', 'quantity', 1, 'unitAmount', x."shipping_total"::text, 'currency', v_order.currency)) else '[]'::jsonb end
    from "better_supabase"."orders" x where x."id" = v_order.id));
    v_invoice := "better_supabase"."issue_invoice"((v_invoice ->> 'id')::uuid, current_date);
    v_invoice := "better_supabase"."record_invoice_payment"((v_invoice ->> 'id')::uuid, (v_invoice ->> 'total')::bigint,
      v_order.currency, now(), 'order', 'order:' || v_order.id::text);
    v_number := v_invoice ->> 'identifier';
    update "better_supabase"."orders" x set "invoice_number" = v_number, "invoice_sequence" = v_seq, "invoiced_at" = now()
    where x."id" = v_order.id;
    perform "better_supabase".emit_event('order.paid', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer, 'currency', v_order.currency, 'total', v_order.total::text, 'units', (select coalesce(sum(l."quantity"), 0)::text from "better_supabase"."order_lines" l where l."order_id" = v_order.id), 'invoiceNumber', v_number), 'orders/' || v_order.id::text, (v_order.tenant)::text, 'order.paid:' || v_order.id::text, 'better-supabase/orders');
    v_newly := true;
  end if;
  return jsonb_build_object('orderId', v_order.id, 'status', (select x."status" from "better_supabase"."orders" x where x."id" = v_order.id),
    'paidTotal', v_paid::text, 'newlyPaid', v_newly,
    'invoiceNumber', coalesce(v_number, v_order.invoice_number), 'invoiceId', v_invoice ->> 'id');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_rent_payment (
  lease_id  uuid,
  amount    bigint,
  paid_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  reference text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = record_rent_payment.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft lease takes no payments' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if record_rent_payment.amount is null or record_rent_payment.amount <= 0 then
    raise exception 'a payment is more than zero minor units' using errcode = '22023', hint = 'LEASE_PAYMENT_INVALID';
  end if;
  v_key := case when nullif(trim(record_rent_payment.reference), '') is not null
    then 'leases.payment:' || v_row."id"::text || ':' || trim(record_rent_payment.reference) end;
  select x."id" into v_tx from "better_supabase"."ledger_transactions" x
    where x."tenant_id" = v_row."tenant_id" and x."idempotency_key" = v_key;
  if v_tx is null then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -record_rent_payment.amount),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', record_rent_payment.amount)),
      'leases', v_row."id"::text, 'Rent payment', v_key, record_rent_payment.paid_at,
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row."id", 'reference', nullif(trim(record_rent_payment.reference), ''))));
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('lease_payment', v_tx::text);
  end if;
    perform "better_supabase".emit_event('lease.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'transactionId', v_tx, 'amount', record_rent_payment.amount::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.paid',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'recorded a rent payment',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'transactionId', v_tx, 'amount', record_rent_payment.amount::text, 'currency', v_row."currency")
  );
  end if;
  return jsonb_build_object('transactionId', v_tx, 'leaseId', v_row."id", 'amount', record_rent_payment.amount::text,
    'currency', v_row."currency", 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reimburse_expense_report (
  report_id uuid,
  paid_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  reference text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = reimburse_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'not allowed to reimburse expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) <> 'approved' then
    raise exception 'only an approved report can be reimbursed' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_cash', 'expenses:cash:' || v_row."currency", 'Expenses paid ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0))),
    'expenses', v_row."id"::text, left('Reimbursed: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))));
  update "better_supabase"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('expense_reimbursement', v_row."id"::text);
  end if;
  perform "better_supabase".emit_event('expense_report.reimbursed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.reimbursed',
    category => 'billing',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'reimbursed an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx)
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_shift_swap (
  assignment_id uuid,
  to_user_id    uuid,
  note          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = request_shift_swap.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (v_row."user_id" = (select auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false))) then
    raise exception 'not allowed to swap this shift' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' or v_shift."starts_at" <= now() then
    raise exception 'only an assigned shift that hasn''t started can be swapped' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.to_user_id is null or request_shift_swap.to_user_id = v_row."user_id" or not exists (select 1 from "public"."memberships" mm where mm."organization_id" = v_row."tenant_id" and mm."user_id" = request_shift_swap.to_user_id) then
    raise exception 'the swap goes to another member of this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.note is not null and length(request_shift_swap.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."shift_swaps" x where x."assignment_id" = v_row."id" and x."status" = 'pending') then
    raise exception 'the shift already has a pending swap' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  insert into "better_supabase"."shift_swaps" ("tenant_id", "assignment_id", "from_user_id", "to_user_id", "note")
  values (v_row."tenant_id", v_row."id", v_row."user_id", request_shift_swap.to_user_id, nullif(trim(request_shift_swap.note), ''))
  returning * into v_swap;
  perform "better_supabase".emit_event('shift_swap.requested', jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id"), 'shifts/' || v_shift."id"::text, (v_swap."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_swap.requested',
    category => 'data',
    target_type => 'shift_swap',
    record_id => v_swap."id"::text,
    summary => 'Shift swap requested',
    tenant => (v_swap."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id")
  );
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_swap.requested',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'A shift swap is offered to you',
      'recipients', jsonb_build_array(v_swap."to_user_id"),
      'key', 'shift_swap.requested:' || v_shift."id"::text || ':' || v_swap."to_user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.respond_to_portal_quote (
  quote    uuid,
  decision text,
  name     text,
  note     text,
  selected jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = respond_to_portal_quote.quote and (x."status" <> 'draft' and (((x."tenant_id")::text, ('quote')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or ((x."tenant_id")::text, (x."company_type")::text, (x."company_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g) or ((x."tenant_id")::text, (x."contact_type")::text, (x."contact_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) for update;
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if respond_to_portal_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_portal_quote.selected is not null then
      if jsonb_typeof(respond_to_portal_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_portal_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_portal_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_portal_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''),
    "decision_note" = nullif(trim(respond_to_portal_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_portal_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_user_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_user_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.respond_to_quote (
  token    text,
  decision text,
  name     text,
  note     text,
  selected jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(respond_to_quote.token, 'sha256'), 'hex') for update;
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  if respond_to_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(respond_to_quote.name), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_quote.selected is not null then
      if jsonb_typeof(respond_to_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(respond_to_quote.name), ''),
    "decision_note" = nullif(trim(respond_to_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_user_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_user_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if respond_to_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_bot_mode (
  conversation uuid,
  mode         text,
  reason       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_before text;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = set_bot_mode.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_before := v_conv."bot_mode";
  update "better_supabase"."inbox_conversations" set "bot_mode" = mode where "id" = v_conv."id" returning * into v_conv;
  if v_before is distinct from mode then
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_bot_mode.mode, 'reason', set_bot_mode.reason));
    if v_before = 'bot' and mode = 'human' then
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.handoff',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', coalesce(set_bot_mode.reason, v_conv."last_message_preview"),
        'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
        'key', 'inbox.handoff:' || v_conv."id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id", 'reason', set_bot_mode.reason)
      ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_maintenance_request_assignees (
  work_item uuid,
  users     uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_maintenance_request_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."maintenance_request_assignees" ("tenant_id", "maintenance_request_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'maintenance_request', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'maintenance_request.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'maintenance_request',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'task.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('maintenanceRequestId', v_row."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('maintenance_request.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  end if;
  return cardinality(v_users);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_shipment_label (
  shipment_id     uuid,
  carrier         text,
  service         text,
  tracking_number text,
  label_id        text,
  label_cost      bigint,
  currency        text,
  label_format    text   DEFAULT 'pdf'::text,
  label_url       text   DEFAULT NULL::text,
  tracking_url    text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_ship "better_supabase"."shipments"%rowtype;
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;
  v_line record;
  v_part record;
  v_movement uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ship from "better_supabase"."shipments" x where x."id" = set_shipment_label.shipment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_ship."tenant_id", 'shipments.manage'), false)) then
    raise exception 'shipment not found' using errcode = 'P0002', hint = 'SHIPMENT_NOT_FOUND';
  end if;
  if v_ship."status" <> 'draft' then
    raise exception 'only a draft shipment gets a label' using errcode = '55000', hint = 'SHIPMENT_NOT_DRAFT';
  end if;
  begin
    update "better_supabase"."shipments" x set
      "carrier" = set_shipment_label.carrier,
      "service" = set_shipment_label.service,
      "tracking_number" = set_shipment_label.tracking_number,
      "tracking_url" = set_shipment_label.tracking_url,
      "label_id" = set_shipment_label.label_id,
      "label_url" = set_shipment_label.label_url,
      "label_format" = coalesce(set_shipment_label.label_format, 'pdf'),
      "label_cost" = set_shipment_label.label_cost,
      "currency" = set_shipment_label.currency,
      "labeled_at" = now(),
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
  exception
    when unique_violation then
      raise exception 'another shipment has this carrier and tracking number' using errcode = '23505', hint = 'SHIPMENT_TRACKING_TAKEN';
    when check_violation or not_null_violation then
      raise exception 'a label needs a carrier, service, tracking number, label id, a cost of zero or more and a currency' using errcode = '22023', hint = 'SHIPMENT_LABEL_INVALID';
  end;
  if v_ship."carrier" is null or v_ship."service" is null or v_ship."tracking_number" is null or v_ship."label_id" is null or v_ship."label_cost" is null then
    raise exception 'a label needs a carrier, service, tracking number, label id, a cost of zero or more and a currency' using errcode = '22023', hint = 'SHIPMENT_LABEL_INVALID';
  end if;
  if not better_supabase.import_run() is not null then
  for v_line in
    select x."id" as id, x."variant_id" as variant, x."location_id" as location, x."quantity" as quantity,
      x."detail" as detail, x."allocation_id" as allocation
    from "better_supabase"."shipment_lines" x
    where x."shipment_id" = v_ship."id" and x."direction" = 'outbound' and x."movement_id" is null
    order by x."position"
  loop
    if v_line.allocation is not null then
      v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_movement := ("better_supabase"."fulfill_allocation"(v_line.allocation, v_line.quantity, v_line.detail) ->> 'movementId')::uuid;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    else
      v_movement := "better_supabase"."move_stock"(v_ship."tenant_id", v_line.variant, v_line.location, -v_line.quantity, 'sale', 'shipment', v_ship."id"::text, null, v_line.detail);
    end if;
    update "better_supabase"."shipment_lines" x set "movement_id" = v_movement, "moved_at" = now(),
      "detail" = jsonb_strip_nulls(coalesce(v_line.detail, '{}'::jsonb) || jsonb_build_object('parts', (select jsonb_agg(jsonb_build_object('lotId', g.lot, 'quantity', g.quantity::text))
    from (select a."metadata" ->> 'lotId' as lot, (sum(-e."amount" / power(10::numeric, a."scale")))::numeric(20, 6) as quantity
      from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      where e."transaction_id" = v_movement and a."kind" = 'stock'
      group by a."metadata" ->> 'lotId') g)))
    where x."id" = v_line.id;
  end loop;
  end if;
  insert into "better_supabase"."shipment_tracking_events" ("tenant_id", "shipment_id", "external_id", "status", "occurred_at", "description", "source")
  values (v_ship."tenant_id", v_ship."id", 'label:' || v_ship."label_id", 'label_created', now(), 'Label created', 'carrier')
  on conflict ("shipment_id", "external_id") do nothing;
  perform "better_supabase".emit_event('shipment.labeled', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  perform better_supabase.audit_event(
    event_type => 'shipment.labeled',
    category => 'data',
    target_type => 'shipment',
    record_id => v_ship."id"::text,
    target_label => v_ship."reference",
    summary => 'bought shipping label',
    tenant => (v_ship."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number")
  );
  select t."status", t."occurred_at" into v_status, v_at
    from "better_supabase"."shipment_tracking_events" t
    where t."shipment_id" = v_ship."id"
    order by t."occurred_at" desc, array_position(array['label_created', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned']::text[], t."status") desc
    limit 1;
  if v_status is not null and v_ship."status" <> 'cancelled' and v_status <> v_ship."status" then
    v_from := v_ship."status";
    update "better_supabase"."shipments" x set
      "status" = v_status,
      "delivered_at" = case when v_status = 'delivered' then v_at end,
      "updated_at" = now()
    where x."id" = v_ship."id"
    returning * into v_ship;
    perform "better_supabase".emit_event('shipment.status_changed', jsonb_build_object('organizationId', v_ship."tenant_id"::text, 'id', v_ship."id", 'from', v_from, 'to', v_ship."status", 'trackingNumber', v_ship."tracking_number"), 'shipments/' || v_ship."id"::text, (v_ship."tenant_id")::text, null, 'better-supabase/shipments');
  end if;
  return jsonb_build_object('id', v_ship."id", 'organizationId', v_ship."tenant_id"::text, 'reference', v_ship."reference", 'status', v_ship."status", 'from', v_ship."from_address", 'to', v_ship."to_address", 'fromLocationId', v_ship."from_location_id", 'subjectType', v_ship."subject_type", 'subjectId', v_ship."subject_id", 'carrier', v_ship."carrier", 'service', v_ship."service", 'trackingNumber', v_ship."tracking_number", 'trackingUrl', v_ship."tracking_url", 'labelId', v_ship."label_id", 'labelUrl', v_ship."label_url", 'labelFormat', v_ship."label_format", 'labelCost', v_ship."label_cost"::text, 'currency', v_ship."currency", 'labeledAt', v_ship."labeled_at", 'deliveredAt', v_ship."delivered_at", 'cancelledAt', v_ship."cancelled_at", 'createdBy', v_ship."created_by", 'createdAt', v_ship."created_at", 'updatedAt', v_ship."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = v_ship."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = v_ship."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_work_item_assignees (
  work_item uuid,
  users     uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'work_item', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'work_item.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'work_item',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'task.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('workItemId', v_row."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('task.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return cardinality(v_users);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unassign_shift (
  assignment_id uuid,
  reason        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_was text;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = unassign_shift.assignment_id for update;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  v_was := v_row."status";
  if v_was <> 'released' then
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('shift_assignment.released', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', nullif(trim(unassign_shift.reason), '')), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.released',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment released',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', nullif(trim(unassign_shift.reason), ''))
  );
    if v_was = 'assigned' and v_shift."status" = 'published' then
      if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.released',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'You are off a shift',
      'recipients', jsonb_build_array(v_row."user_id"),
      'key', 'shift_assignment.released:' || v_shift."id"::text || ':' || v_row."user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_activity (
  engagement uuid,
  attrs      jsonb,
  subjects   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := update_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'audience', '') is not null and not (update_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if update_activity.attrs ? 'restrictedRoles' and jsonb_typeof(update_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'category', '') is not null and not (update_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "type" = coalesce(update_activity.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_activity.attrs ? 'dueAt' then (update_activity.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_activity.attrs ? 'doneAt' then (update_activity.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_activity.attrs ? 'durationSeconds' then (update_activity.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_activity.attrs ? 'audience' then coalesce(nullif(update_activity.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_activity.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_activity.attrs -> 'restrictedRoles') = 'array' then update_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_activity.attrs ? 'category' then nullif(update_activity.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_activity.attrs ? 'goalId' then nullif(update_activity.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_activity.attrs ? 'type' then coalesce(x."locked_at", case when update_activity.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_activity.subjects is not null then
    
  if jsonb_typeof(coalesce(update_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('activity.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.wake_snoozed_conversations()
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_until timestamptz;
  v_count integer := 0;
  v_claims text;
begin
  for v_conv in
    select * from "better_supabase"."inbox_conversations"
    where "status" = 'snoozed' and "snoozed_until" <= now()
    order by "snoozed_until"
    for update skip locked
  loop
    v_until := v_conv."snoozed_until";
    update "better_supabase"."inbox_conversations" set "status" = 'open', "snoozed_until" = null
    where "id" = v_conv."id"
    returning * into v_conv;
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
    values (v_conv."tenant_id", v_conv."id", 'unsnoozed', null, jsonb_build_object('snoozed_until', v_until));
    perform "better_supabase".emit_event('inbox_conversation.unsnoozed', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.snooze_ended',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', coalesce(v_conv."subject", v_conv."last_message_preview"),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.snooze_ended:' || v_conv."id"::text || ':' || extract(epoch from v_until)::text,
      'data', jsonb_build_object('conversationId', v_conv."id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
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
  where x."id" = write_off_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.manage' end), false)) and x."status" in ('issued', 'partially_paid')
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'only an open invoice you can manage is written off' using errcode = '55000', hint = 'INVOICE_NOT_OPEN';
  end if;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_write_off', v_row."id"::text);
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
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
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

REVOKE ALL ON FUNCTION "api"."begin_import_session"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."begin_import_session"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_run"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_run"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."begin_import_session"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."begin_import_session"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_run"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_run"() TO "anon", "authenticated", "service_role";
