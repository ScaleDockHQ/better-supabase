SET local check_function_bodies = off;

create or replace function "better_supabase"."archive_leave_type"(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leave_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leave_types" x where x."id" = archive_leave_type.type_id for update;
  if not found then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then
    raise exception 'not allowed to manage leave types' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  update "better_supabase"."leave_types" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('leave_type.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name"), 'leave-types/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_type.archived',
    category => 'data',
    target_type => 'leave_type',
    record_id => v_row."id"::text,
    summary => 'archived leave type' || ' ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'paid', v_row."paid", 'tracked', v_row."tracked", 'allowance', v_row."allowance"::text, 'carryoverMax', v_row."carryover_max"::text, 'color', v_row."color", 'autoApprove', v_row."auto_approve", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_leave_type"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_leave_type"(uuid) to authenticated, service_role;

create or replace function "api"."archive_leave_type"(type_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_leave_type"($1) $$;
revoke execute on function "api"."archive_leave_type"(uuid) from public, anon;
grant execute on function "api"."archive_leave_type"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."restore_leave_type"(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leave_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leave_types" x where x."id" = restore_leave_type.type_id for update;
  if not found then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then
    raise exception 'not allowed to manage leave types' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  update "better_supabase"."leave_types" x set "archived_at" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('leave_type.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name"), 'leave-types/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_type.restored',
    category => 'data',
    target_type => 'leave_type',
    record_id => v_row."id"::text,
    summary => 'restored leave type' || ' ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'paid', v_row."paid", 'tracked', v_row."tracked", 'allowance', v_row."allowance"::text, 'carryoverMax', v_row."carryover_max"::text, 'color', v_row."color", 'autoApprove', v_row."auto_approve", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."restore_leave_type"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_leave_type"(uuid) to authenticated, service_role;

create or replace function "api"."restore_leave_type"(type_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_leave_type"($1) $$;
revoke execute on function "api"."restore_leave_type"(uuid) from public, anon;
grant execute on function "api"."restore_leave_type"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_expense_category"(category_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_categories" c where c."id" = archive_expense_category.category_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'no such expense category you can manage' using errcode = 'P0002', hint = 'EXPENSE_CATEGORY_NOT_FOUND';
  end if;
  update "better_supabase"."expense_categories" c set "archived_at" = coalesce(c."archived_at", now()), "updated_at" = now()
    where c."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('expense_category.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key"), 'expense-categories/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_category.archived',
    category => 'data',
    target_type => 'expense_category',
    record_id => v_row."id"::text,
    summary => 'archived an expense category',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_expense_category"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "api"."archive_expense_category"(category_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_expense_category"($1) $$;
revoke execute on function "api"."archive_expense_category"(uuid) from public, anon;
grant execute on function "api"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."restore_expense_category"(category_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_categories" c where c."id" = restore_expense_category.category_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'no such expense category you can manage' using errcode = 'P0002', hint = 'EXPENSE_CATEGORY_NOT_FOUND';
  end if;
  update "better_supabase"."expense_categories" c set "archived_at" = null, "updated_at" = now()
    where c."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('expense_category.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key"), 'expense-categories/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_category.restored',
    category => 'data',
    target_type => 'expense_category',
    record_id => v_row."id"::text,
    summary => 'restored an expense category',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."restore_expense_category"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_expense_category"(uuid) to authenticated, service_role;

create or replace function "api"."restore_expense_category"(category_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_expense_category"($1) $$;
revoke execute on function "api"."restore_expense_category"(uuid) from public, anon;
grant execute on function "api"."restore_expense_category"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_donation_fund"(fund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donation_funds" x where x."id" = archive_donation_fund.fund_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such fund you can manage' using errcode = 'P0002', hint = 'DONATION_FUND_NOT_FOUND';
  end if;
  update "better_supabase"."donation_funds" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('donation_fund.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key"), 'donation-funds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation_fund.archived',
    category => 'data',
    target_type => 'donation_fund',
    record_id => v_row."id"::text,
    summary => 'archived a fund',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_donation_fund"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_donation_fund"(uuid) to authenticated, service_role;

create or replace function "api"."archive_donation_fund"(fund_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_donation_fund"($1) $$;
revoke execute on function "api"."archive_donation_fund"(uuid) from public, anon;
grant execute on function "api"."archive_donation_fund"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."restore_donation_fund"(fund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donation_funds" x where x."id" = restore_donation_fund.fund_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such fund you can manage' using errcode = 'P0002', hint = 'DONATION_FUND_NOT_FOUND';
  end if;
  update "better_supabase"."donation_funds" x set "archived_at" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('donation_fund.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key"), 'donation-funds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation_fund.restored',
    category => 'data',
    target_type => 'donation_fund',
    record_id => v_row."id"::text,
    summary => 'restored a fund',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."restore_donation_fund"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_donation_fund"(uuid) to authenticated, service_role;

create or replace function "api"."restore_donation_fund"(fund_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_donation_fund"($1) $$;
revoke execute on function "api"."restore_donation_fund"(uuid) from public, anon;
grant execute on function "api"."restore_donation_fund"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_qualification_type"(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."qualification_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."qualification_types" x where x."id" = archive_qualification_type.type_id;
  if not found then
    raise exception 'qualification type not found' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.manage'), false)) then
    raise exception 'not allowed to manage qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."qualification_types" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('qualification_type.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'qualificationTypeId', v_row."id", 'key', v_row."key"), 'qualification-types/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/qualifications');
  perform better_supabase.audit_event(
    event_type => 'qualification_type.archived',
    category => 'configuration',
    target_type => 'qualification_type',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'Qualification type archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'qualificationTypeId', v_row."id", 'key', v_row."key")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'holderTypes', to_jsonb(v_row."holder_types"), 'validForMonths', v_row."valid_for_months", 'evidenceRequired', v_row."evidence_required", 'courseId', v_row."course_id", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_qualification_type"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_qualification_type"(uuid) to authenticated, service_role;

create or replace function "api"."archive_qualification_type"(type_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_qualification_type"($1) $$;
revoke execute on function "api"."archive_qualification_type"(uuid) from public, anon;
grant execute on function "api"."archive_qualification_type"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."restore_qualification_type"(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."qualification_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."qualification_types" x where x."id" = restore_qualification_type.type_id;
  if not found then
    raise exception 'qualification type not found' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.manage'), false)) then
    raise exception 'not allowed to manage qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    update "better_supabase"."qualification_types" x set "archived_at" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('qualification_type.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'qualificationTypeId', v_row."id", 'key', v_row."key"), 'qualification-types/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/qualifications');
  perform better_supabase.audit_event(
    event_type => 'qualification_type.restored',
    category => 'configuration',
    target_type => 'qualification_type',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'Qualification type restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'qualificationTypeId', v_row."id", 'key', v_row."key")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'holderTypes', to_jsonb(v_row."holder_types"), 'validForMonths', v_row."valid_for_months", 'evidenceRequired', v_row."evidence_required", 'courseId', v_row."course_id", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."restore_qualification_type"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_qualification_type"(uuid) to authenticated, service_role;

create or replace function "api"."restore_qualification_type"(type_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_qualification_type"($1) $$;
revoke execute on function "api"."restore_qualification_type"(uuid) from public, anon;
grant execute on function "api"."restore_qualification_type"(uuid) to authenticated, service_role;
