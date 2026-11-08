-- ==== alone: schema supabase/schemas/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block e-prescribing@1 managed
-- @bsb-hash sha256:bfb3db90c92dd51a87ed6c3bdff8941160a2221795f434d97e1afe5abfdc352a
-- Prescriptions over medication orders with the states draft, signed, sent, dispensed and cancelled, a signature only the prescriber can give, and delivery through a PrescriptionGateway port that carries a FHIR R4 MedicationRequest.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- E-prescribing: prescriptions over medication orders with states draft, signed,
-- sent, dispensed and cancelled, a signature only the prescriber can give, and
-- delivery recorded for a gateway that plugs in through the PrescriptionGateway
-- port.

-- A prescription of one medication order. It starts as a draft by the prescriber,
-- the prescriber signs it (snapshot freezes the order), a gateway delivers it
-- and the pharmacy dispenses it. Only the functions change it; a signed
-- prescription always has a signer and a time.
create table "better_supabase"."prescriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "prescriber_id" uuid not null,
  "prescriber_name" text constraint bsb_prescriptions_prescriber_name_check check ("prescriber_name" is null or length("prescriber_name") <= 300),
  "status" text not null default 'draft' constraint bsb_prescriptions_status_check check ("status" in ('draft', 'signed', 'sent', 'dispensed', 'cancelled')),
  "snapshot" jsonb,
  "signed_by" uuid,
  "signed_at" timestamptz,
  "gateway" text constraint bsb_prescriptions_gateway_check check ("gateway" is null or length("gateway") >= 1 and length("gateway") <= 100),
  "gateway_reference" text constraint bsb_prescriptions_gateway_reference_check check ("gateway_reference" is null or length("gateway_reference") <= 200),
  "sent_at" timestamptz,
  "delivery_error" text constraint bsb_prescriptions_delivery_error_check check ("delivery_error" is null or length("delivery_error") <= 1000),
  "dispensed_at" timestamptz,
  "cancelled_at" timestamptz,
  "cancel_reason" text constraint bsb_prescriptions_cancel_reason_check check ("cancel_reason" is null or length("cancel_reason") <= 1000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_prescriptions_check check ("status" in ('draft', 'cancelled') or ("signed_by" is not null and "signed_at" is not null and "snapshot" is not null)),
  constraint bsb_prescriptions_check1 check ("signed_by" is null or "signed_by" = "prescriber_id"),
  constraint bsb_prescriptions_check2 check ("status" not in ('sent', 'dispensed') or ("sent_at" is not null and "gateway" is not null)),
  constraint bsb_prescriptions_check3 check ("status" <> 'dispensed' or "dispensed_at" is not null),
  constraint bsb_prescriptions_check4 check ("status" <> 'cancelled' or "cancelled_at" is not null),
  foreign key ("tenant_id", "order_id") references "better_supabase"."medication_orders" ("tenant_id", "id")
);
create unique index "prescriptions_live_order_key" on "better_supabase"."prescriptions" ("tenant_id", "order_id") where "status" <> 'cancelled';
create index "prescriptions_order_idx" on "better_supabase"."prescriptions" ("tenant_id", "order_id");
create index "prescriptions_subject_idx" on "better_supabase"."prescriptions" ("tenant_id", "subject_type", "subject_id");
create index "prescriptions_status_idx" on "better_supabase"."prescriptions" ("tenant_id", "status");
alter table "better_supabase"."prescriptions" enable row level security;
revoke all on "better_supabase"."prescriptions" from public, anon, authenticated;
grant select on "better_supabase"."prescriptions" to authenticated;
grant all on "better_supabase"."prescriptions" to service_role;
create policy bsb_prescriptions_read on "better_supabase"."prescriptions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')));

-- What a signed prescription freezes: the order's dose, schedule and bounds with
-- the medication's name and code, so later edits of the order do not change it.
create or replace function "better_supabase"."prescription_order_snapshot"(tenant uuid, order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'orderId', x."id", 'medicationId', x."medication_id", 'medicationName', mx."name",
    'codeSystem', mx."code_system", 'code', mx."code", 'dose', x."dose", 'doseUnit', x."dose_unit",
    'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed",
    'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day",
    'startsOn', x."starts_on", 'endsOn', x."ends_on")
  from "better_supabase"."medication_orders" x join "better_supabase"."medications" mx on mx."tenant_id" = x."tenant_id" and mx."id" = x."medication_id"
  where x."tenant_id" = prescription_order_snapshot.tenant and x."id" = prescription_order_snapshot.order_id;
$$;
revoke all on function "better_supabase"."prescription_order_snapshot"(uuid, uuid) from public, anon, authenticated;

-- Drafts a prescription for an active medication order. The caller becomes the
-- prescriber; the service role names one in attrs.prescriberId. attrs is
-- { prescriberId, prescriberName }. Needs e_prescribing.write.
create or replace function "better_supabase"."create_prescription"(tenant uuid, order_id uuid, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'not allowed to draft prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  begin
    v_prescriber := coalesce(v_prescriber, nullif(v_attrs ->> 'prescriberId', '')::uuid);
  exception when invalid_text_representation then
    raise exception 'prescriberId is a uuid' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end;
  if v_prescriber is null then
    raise exception 'a prescription needs a prescriber' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_name is not null and length(v_name) > 300 then
    raise exception 'a prescriber name is up to 300 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = create_prescription.tenant and x."id" = create_prescription.order_id;
  if not found then
    raise exception 'the order is not one of the organization' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'only an active medication order can be prescribed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  begin
    insert into "better_supabase"."prescriptions" ("tenant_id", "order_id", "subject_type", "subject_id", "prescriber_id", "prescriber_name")
    values (create_prescription.tenant, v_order."id", v_order."subject_type", v_order."subject_id", v_prescriber, v_name)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'this order already has a prescription that is not cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) to authenticated, service_role;

-- Signs a draft. Only the prescriber signs, as a signed-in user holding
-- e_prescribing.sign; the service role never does. The order must still be
-- active and not ended. The signature freezes the order into the prescription.
create or replace function "better_supabase"."sign_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.sign'), false))) then
    raise exception 'not allowed to sign prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."prescriber_id" is distinct from auth.uid() or auth.uid() is null then
    raise exception 'only the prescriber signs a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft can be signed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = v_row."tenant_id" and x."id" = v_row."order_id";
  if not found or v_order."status" <> 'active' or (v_order."ends_on" is not null and v_order."ends_on" < (now() at time zone 'UTC')::date) then
    raise exception 'the order is no longer active' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
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
  null;
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
$$;
revoke execute on function "better_supabase"."sign_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."sign_prescription"(uuid) to authenticated, service_role;

-- Records what the gateway answered for a signed prescription: with an error it
-- stays signed so it can be sent again, otherwise it is sent. gateway is the
-- port's key and reference the gateway's id for it. Needs e_prescribing.write.
create or replace function "better_supabase"."record_prescription_delivery"(prescription_id uuid, gateway text, reference text default null, error text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to send prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_gateway is null or length(v_gateway) > 100 then
    raise exception 'gateway is 1 to 100 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reference, '')) > 200 or length(coalesce(v_error, '')) > 1000 then
    raise exception 'a reference is up to 200 characters and an error up to 1000' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_row."status" <> 'signed' then
    raise exception 'only a signed prescription can be sent' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_error is not null then
    update "better_supabase"."prescriptions" x set "gateway" = v_gateway, "delivery_error" = v_error, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "better_supabase"."prescriptions" x set "status" = 'sent', "gateway" = v_gateway, "gateway_reference" = v_reference,
      "sent_at" = now(), "delivery_error" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) to authenticated, service_role;

-- Marks a sent prescription as dispensed, when the pharmacy reports it. Needs
-- e_prescribing.write.
create or replace function "better_supabase"."record_prescription_dispense"(prescription_id uuid, dispensed_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = record_prescription_dispense.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to record dispensing' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'sent' then
    raise exception 'only a sent prescription can be dispensed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'dispensed', "dispensed_at" = coalesce(record_prescription_dispense.dispensed_at, now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) to authenticated, service_role;

-- Cancels a prescription that is not dispensed. The prescriber, or a member with
-- e_prescribing.manage, cancels; a signed or sent one needs a reason.
create or replace function "better_supabase"."cancel_prescription"(prescription_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.manage'), false))) and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) and v_row."prescriber_id" is not distinct from auth.uid()) then
    raise exception 'only the prescriber or a manager cancels a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" in ('dispensed', 'cancelled') then
    raise exception 'a dispensed or cancelled prescription cannot be cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_reason is null and v_row."status" <> 'draft' then
    raise exception 'cancelling a signed or sent prescription needs a reason' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reason, '')) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'cancelled', "cancelled_at" = now(), "cancel_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_prescription"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_prescription"(uuid, text) to authenticated, service_role;

-- One prescription. Needs e_prescribing.read.
create or replace function "better_supabase"."get_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = get_prescription.prescription_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."get_prescription"(uuid) to authenticated, service_role;

-- The organization's prescriptions, newest first. filters is { orderId,
-- subjectType, subjectId, status, prescriberId, limit, offset }. Needs
-- e_prescribing.read.
create or replace function "better_supabase"."list_prescriptions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_prescriptions.tenant is not null and coalesce(better_supabase.can('tenant', list_prescriptions.tenant, 'e_prescribing.read'), false))) then
    raise exception 'not allowed to read prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_filters ->> 'status' is not null and v_filters ->> 'status' not in ('draft', 'signed', 'sent', 'dispensed', 'cancelled') then
    raise exception 'status is draft, signed, sent, dispensed or cancelled' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
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
$$;
revoke execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."prescriptions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."prescriptions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."prescriptions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."prescriptions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block-data e-prescribing
-- @bsb-hash sha256:ee8e0a6f8aee44c28fe5af663969a83d12a0783824592651edb998fa04f281fe
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('e-prescribing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block e-prescribing@1 managed
-- @bsb-hash sha256:9006b23cb11c8bcfebb46a60085667ee000ae30385bab156f45c31dd0d58eb27
-- Prescriptions over medication orders with the states draft, signed, sent, dispensed and cancelled, a signature only the prescriber can give, and delivery through a PrescriptionGateway port that carries a FHIR R4 MedicationRequest.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- E-prescribing: prescriptions over medication orders with states draft, signed,
-- sent, dispensed and cancelled, a signature only the prescriber can give, and
-- delivery recorded for a gateway that plugs in through the PrescriptionGateway
-- port.

-- A prescription of one medication order. It starts as a draft by the prescriber,
-- the prescriber signs it (snapshot freezes the order), a gateway delivers it
-- and the pharmacy dispenses it. Only the functions change it; a signed
-- prescription always has a signer and a time.
create table "better_supabase"."prescriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "prescriber_id" uuid not null,
  "prescriber_name" text constraint bsb_prescriptions_prescriber_name_check check ("prescriber_name" is null or length("prescriber_name") <= 300),
  "status" text not null default 'draft' constraint bsb_prescriptions_status_check check ("status" in ('draft', 'signed', 'sent', 'dispensed', 'cancelled')),
  "snapshot" jsonb,
  "signed_by" uuid,
  "signed_at" timestamptz,
  "gateway" text constraint bsb_prescriptions_gateway_check check ("gateway" is null or length("gateway") >= 1 and length("gateway") <= 100),
  "gateway_reference" text constraint bsb_prescriptions_gateway_reference_check check ("gateway_reference" is null or length("gateway_reference") <= 200),
  "sent_at" timestamptz,
  "delivery_error" text constraint bsb_prescriptions_delivery_error_check check ("delivery_error" is null or length("delivery_error") <= 1000),
  "dispensed_at" timestamptz,
  "cancelled_at" timestamptz,
  "cancel_reason" text constraint bsb_prescriptions_cancel_reason_check check ("cancel_reason" is null or length("cancel_reason") <= 1000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_prescriptions_check check ("status" in ('draft', 'cancelled') or ("signed_by" is not null and "signed_at" is not null and "snapshot" is not null)),
  constraint bsb_prescriptions_check1 check ("signed_by" is null or "signed_by" = "prescriber_id"),
  constraint bsb_prescriptions_check2 check ("status" not in ('sent', 'dispensed') or ("sent_at" is not null and "gateway" is not null)),
  constraint bsb_prescriptions_check3 check ("status" <> 'dispensed' or "dispensed_at" is not null),
  constraint bsb_prescriptions_check4 check ("status" <> 'cancelled' or "cancelled_at" is not null),
  foreign key ("tenant_id", "order_id") references "better_supabase"."medication_orders" ("tenant_id", "id")
);
create unique index "prescriptions_live_order_key" on "better_supabase"."prescriptions" ("tenant_id", "order_id") where "status" <> 'cancelled';
create index "prescriptions_order_idx" on "better_supabase"."prescriptions" ("tenant_id", "order_id");
create index "prescriptions_subject_idx" on "better_supabase"."prescriptions" ("tenant_id", "subject_type", "subject_id");
create index "prescriptions_status_idx" on "better_supabase"."prescriptions" ("tenant_id", "status");
alter table "better_supabase"."prescriptions" enable row level security;
revoke all on "better_supabase"."prescriptions" from public, anon, authenticated;
grant select on "better_supabase"."prescriptions" to authenticated;
grant all on "better_supabase"."prescriptions" to service_role;
create policy bsb_prescriptions_read on "better_supabase"."prescriptions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')));

-- What a signed prescription freezes: the order's dose, schedule and bounds with
-- the medication's name and code, so later edits of the order do not change it.
create or replace function "better_supabase"."prescription_order_snapshot"(tenant uuid, order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'orderId', x."id", 'medicationId', x."medication_id", 'medicationName', mx."name",
    'codeSystem', mx."code_system", 'code', mx."code", 'dose', x."dose", 'doseUnit', x."dose_unit",
    'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed",
    'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day",
    'startsOn', x."starts_on", 'endsOn', x."ends_on")
  from "better_supabase"."medication_orders" x join "better_supabase"."medications" mx on mx."tenant_id" = x."tenant_id" and mx."id" = x."medication_id"
  where x."tenant_id" = prescription_order_snapshot.tenant and x."id" = prescription_order_snapshot.order_id;
$$;
revoke all on function "better_supabase"."prescription_order_snapshot"(uuid, uuid) from public, anon, authenticated;

-- Drafts a prescription for an active medication order. The caller becomes the
-- prescriber; the service role names one in attrs.prescriberId. attrs is
-- { prescriberId, prescriberName }. Needs e_prescribing.write.
create or replace function "better_supabase"."create_prescription"(tenant uuid, order_id uuid, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'not allowed to draft prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  begin
    v_prescriber := coalesce(v_prescriber, nullif(v_attrs ->> 'prescriberId', '')::uuid);
  exception when invalid_text_representation then
    raise exception 'prescriberId is a uuid' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end;
  if v_prescriber is null then
    raise exception 'a prescription needs a prescriber' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_name is not null and length(v_name) > 300 then
    raise exception 'a prescriber name is up to 300 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = create_prescription.tenant and x."id" = create_prescription.order_id;
  if not found then
    raise exception 'the order is not one of the organization' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'only an active medication order can be prescribed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  begin
    insert into "better_supabase"."prescriptions" ("tenant_id", "order_id", "subject_type", "subject_id", "prescriber_id", "prescriber_name")
    values (create_prescription.tenant, v_order."id", v_order."subject_type", v_order."subject_id", v_prescriber, v_name)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'this order already has a prescription that is not cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
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
$$;
revoke execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) to authenticated, service_role;

-- Signs a draft. Only the prescriber signs, as a signed-in user holding
-- e_prescribing.sign; the service role never does. The order must still be
-- active and not ended. The signature freezes the order into the prescription.
create or replace function "better_supabase"."sign_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.sign'), false))) then
    raise exception 'not allowed to sign prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."prescriber_id" is distinct from auth.uid() or auth.uid() is null then
    raise exception 'only the prescriber signs a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft can be signed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = v_row."tenant_id" and x."id" = v_row."order_id";
  if not found or v_order."status" <> 'active' or (v_order."ends_on" is not null and v_order."ends_on" < (now() at time zone 'UTC')::date) then
    raise exception 'the order is no longer active' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
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
$$;
revoke execute on function "better_supabase"."sign_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."sign_prescription"(uuid) to authenticated, service_role;

-- Records what the gateway answered for a signed prescription: with an error it
-- stays signed so it can be sent again, otherwise it is sent. gateway is the
-- port's key and reference the gateway's id for it. Needs e_prescribing.write.
create or replace function "better_supabase"."record_prescription_delivery"(prescription_id uuid, gateway text, reference text default null, error text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to send prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_gateway is null or length(v_gateway) > 100 then
    raise exception 'gateway is 1 to 100 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reference, '')) > 200 or length(coalesce(v_error, '')) > 1000 then
    raise exception 'a reference is up to 200 characters and an error up to 1000' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_row."status" <> 'signed' then
    raise exception 'only a signed prescription can be sent' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
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
$$;
revoke execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) to authenticated, service_role;

-- Marks a sent prescription as dispensed, when the pharmacy reports it. Needs
-- e_prescribing.write.
create or replace function "better_supabase"."record_prescription_dispense"(prescription_id uuid, dispensed_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = record_prescription_dispense.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to record dispensing' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'sent' then
    raise exception 'only a sent prescription can be dispensed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
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
$$;
revoke execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) to authenticated, service_role;

-- Cancels a prescription that is not dispensed. The prescriber, or a member with
-- e_prescribing.manage, cancels; a signed or sent one needs a reason.
create or replace function "better_supabase"."cancel_prescription"(prescription_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.manage'), false))) and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) and v_row."prescriber_id" is not distinct from auth.uid()) then
    raise exception 'only the prescriber or a manager cancels a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" in ('dispensed', 'cancelled') then
    raise exception 'a dispensed or cancelled prescription cannot be cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_reason is null and v_row."status" <> 'draft' then
    raise exception 'cancelling a signed or sent prescription needs a reason' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reason, '')) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
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
$$;
revoke execute on function "better_supabase"."cancel_prescription"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_prescription"(uuid, text) to authenticated, service_role;

-- One prescription. Needs e_prescribing.read.
create or replace function "better_supabase"."get_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = get_prescription.prescription_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."get_prescription"(uuid) to authenticated, service_role;

-- The organization's prescriptions, newest first. filters is { orderId,
-- subjectType, subjectId, status, prescriberId, limit, offset }. Needs
-- e_prescribing.read.
create or replace function "better_supabase"."list_prescriptions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_prescriptions.tenant is not null and coalesce(better_supabase.can('tenant', list_prescriptions.tenant, 'e_prescribing.read'), false))) then
    raise exception 'not allowed to read prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_filters ->> 'status' is not null and v_filters ->> 'status' not in ('draft', 'signed', 'sent', 'dispensed', 'cancelled') then
    raise exception 'status is draft, signed, sent, dispensed or cancelled' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
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
$$;
revoke execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."prescriptions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."prescriptions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."prescriptions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."prescriptions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.prescriptions deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"prescription","event_prefix":"prescription"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block-data e-prescribing
-- @bsb-hash sha256:ee8e0a6f8aee44c28fe5af663969a83d12a0783824592651edb998fa04f281fe
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('e-prescribing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block e-prescribing@1 managed
-- @bsb-hash sha256:3dc6f430f4db99571f0dff529bcd036955987f0cd2e8e4517d325a8c82a8aeb9
-- Prescriptions over medication orders with the states draft, signed, sent, dispensed and cancelled, a signature only the prescriber can give, and delivery through a PrescriptionGateway port that carries a FHIR R4 MedicationRequest.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- E-prescribing: prescriptions over medication orders with states draft, signed,
-- sent, dispensed and cancelled, a signature only the prescriber can give, and
-- delivery recorded for a gateway that plugs in through the PrescriptionGateway
-- port.

-- A prescription of one medication order. It starts as a draft by the prescriber,
-- the prescriber signs it (snapshot freezes the order), a gateway delivers it
-- and the pharmacy dispenses it. Only the functions change it; a signed
-- prescription always has a signer and a time.
create table "app_private"."prescriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "prescriber_id" uuid not null,
  "prescriber_name" text constraint bsb_prescriptions_prescriber_name_check check ("prescriber_name" is null or length("prescriber_name") <= 300),
  "status" text not null default 'draft' constraint bsb_prescriptions_status_check check ("status" in ('draft', 'signed', 'sent', 'dispensed', 'cancelled')),
  "snapshot" jsonb,
  "signed_by" uuid,
  "signed_at" timestamptz,
  "gateway" text constraint bsb_prescriptions_gateway_check check ("gateway" is null or length("gateway") >= 1 and length("gateway") <= 100),
  "gateway_reference" text constraint bsb_prescriptions_gateway_reference_check check ("gateway_reference" is null or length("gateway_reference") <= 200),
  "sent_at" timestamptz,
  "delivery_error" text constraint bsb_prescriptions_delivery_error_check check ("delivery_error" is null or length("delivery_error") <= 1000),
  "dispensed_at" timestamptz,
  "cancelled_at" timestamptz,
  "cancel_reason" text constraint bsb_prescriptions_cancel_reason_check check ("cancel_reason" is null or length("cancel_reason") <= 1000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_prescriptions_check check ("status" in ('draft', 'cancelled') or ("signed_by" is not null and "signed_at" is not null and "snapshot" is not null)),
  constraint bsb_prescriptions_check1 check ("signed_by" is null or "signed_by" = "prescriber_id"),
  constraint bsb_prescriptions_check2 check ("status" not in ('sent', 'dispensed') or ("sent_at" is not null and "gateway" is not null)),
  constraint bsb_prescriptions_check3 check ("status" <> 'dispensed' or "dispensed_at" is not null),
  constraint bsb_prescriptions_check4 check ("status" <> 'cancelled' or "cancelled_at" is not null),
  foreign key ("tenant_id", "order_id") references "better_supabase"."medication_orders" ("tenant_id", "id")
);
create unique index "prescriptions_live_order_key" on "app_private"."prescriptions" ("tenant_id", "order_id") where "status" <> 'cancelled';
create index "prescriptions_order_idx" on "app_private"."prescriptions" ("tenant_id", "order_id");
create index "prescriptions_subject_idx" on "app_private"."prescriptions" ("tenant_id", "subject_type", "subject_id");
create index "prescriptions_status_idx" on "app_private"."prescriptions" ("tenant_id", "status");
alter table "app_private"."prescriptions" enable row level security;
revoke all on "app_private"."prescriptions" from public, anon, authenticated;
grant select on "app_private"."prescriptions" to authenticated;
grant all on "app_private"."prescriptions" to service_role;
create policy bsb_prescriptions_read on "app_private"."prescriptions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')));

-- What a signed prescription freezes: the order's dose, schedule and bounds with
-- the medication's name and code, so later edits of the order do not change it.
create or replace function "app_private"."prescription_order_snapshot"(tenant uuid, order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'orderId', x."id", 'medicationId', x."medication_id", 'medicationName', mx."name",
    'codeSystem', mx."code_system", 'code', mx."code", 'dose', x."dose", 'doseUnit', x."dose_unit",
    'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed",
    'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day",
    'startsOn', x."starts_on", 'endsOn', x."ends_on")
  from "better_supabase"."medication_orders" x join "better_supabase"."medications" mx on mx."tenant_id" = x."tenant_id" and mx."id" = x."medication_id"
  where x."tenant_id" = prescription_order_snapshot.tenant and x."id" = prescription_order_snapshot.order_id;
$$;
revoke all on function "app_private"."prescription_order_snapshot"(uuid, uuid) from public, anon, authenticated;

-- Drafts a prescription for an active medication order. The caller becomes the
-- prescriber; the service role names one in attrs.prescriberId. attrs is
-- { prescriberId, prescriberName }. Needs e_prescribing.write.
create or replace function "app_private"."create_prescription"(tenant uuid, order_id uuid, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_attrs jsonb := coalesce(create_prescription.attrs, '{}'::jsonb);
  v_order "better_supabase"."medication_orders";
  v_row "app_private"."prescriptions";
  v_prescriber uuid := auth.uid();
  v_name text := nullif(trim(v_attrs ->> 'prescriberName'), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_prescription.tenant is not null and coalesce(better_supabase.can('tenant', create_prescription.tenant, 'e_prescribing.write'), false))) then
    raise exception 'not allowed to draft prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  begin
    v_prescriber := coalesce(v_prescriber, nullif(v_attrs ->> 'prescriberId', '')::uuid);
  exception when invalid_text_representation then
    raise exception 'prescriberId is a uuid' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end;
  if v_prescriber is null then
    raise exception 'a prescription needs a prescriber' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_name is not null and length(v_name) > 300 then
    raise exception 'a prescriber name is up to 300 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = create_prescription.tenant and x."id" = create_prescription.order_id;
  if not found then
    raise exception 'the order is not one of the organization' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'only an active medication order can be prescribed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  begin
    insert into "app_private"."prescriptions" ("tenant_id", "order_id", "subject_type", "subject_id", "prescriber_id", "prescriber_name")
    values (create_prescription.tenant, v_order."id", v_order."subject_type", v_order."subject_id", v_prescriber, v_name)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'this order already has a prescription that is not cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."create_prescription"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."create_prescription"(uuid, uuid, jsonb) to authenticated, service_role;

-- Signs a draft. Only the prescriber signs, as a signed-in user holding
-- e_prescribing.sign; the service role never does. The order must still be
-- active and not ended. The signature freezes the order into the prescription.
create or replace function "app_private"."sign_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."prescriptions";
  v_order "better_supabase"."medication_orders";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."prescriptions" x where x."id" = sign_prescription.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.sign'), false))) then
    raise exception 'not allowed to sign prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."prescriber_id" is distinct from auth.uid() or auth.uid() is null then
    raise exception 'only the prescriber signs a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft can be signed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = v_row."tenant_id" and x."id" = v_row."order_id";
  if not found or v_order."status" <> 'active' or (v_order."ends_on" is not null and v_order."ends_on" < (now() at time zone 'UTC')::date) then
    raise exception 'the order is no longer active' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_prescription_sign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "app_private"."prescriptions" x set "status" = 'signed', "signed_by" = auth.uid(), "signed_at" = now(),
    "snapshot" = "app_private"."prescription_order_snapshot"(v_row."tenant_id", v_row."order_id"), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
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
$$;
revoke execute on function "app_private"."sign_prescription"(uuid) from public, anon;
grant execute on function "app_private"."sign_prescription"(uuid) to authenticated, service_role;

-- Records what the gateway answered for a signed prescription: with an error it
-- stays signed so it can be sent again, otherwise it is sent. gateway is the
-- port's key and reference the gateway's id for it. Needs e_prescribing.write.
create or replace function "app_private"."record_prescription_delivery"(prescription_id uuid, gateway text, reference text default null, error text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."prescriptions";
  v_gateway text := nullif(trim(record_prescription_delivery.gateway), '');
  v_reference text := nullif(trim(record_prescription_delivery.reference), '');
  v_error text := nullif(trim(record_prescription_delivery.error), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."prescriptions" x where x."id" = record_prescription_delivery.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to send prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_gateway is null or length(v_gateway) > 100 then
    raise exception 'gateway is 1 to 100 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reference, '')) > 200 or length(coalesce(v_error, '')) > 1000 then
    raise exception 'a reference is up to 200 characters and an error up to 1000' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_row."status" <> 'signed' then
    raise exception 'only a signed prescription can be sent' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_error is not null then
    update "app_private"."prescriptions" x set "gateway" = v_gateway, "delivery_error" = v_error, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "app_private"."prescriptions" x set "status" = 'sent', "gateway" = v_gateway, "gateway_reference" = v_reference,
      "sent_at" = now(), "delivery_error" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."record_prescription_delivery"(uuid, text, text, text) from public, anon;
grant execute on function "app_private"."record_prescription_delivery"(uuid, text, text, text) to authenticated, service_role;

-- Marks a sent prescription as dispensed, when the pharmacy reports it. Needs
-- e_prescribing.write.
create or replace function "app_private"."record_prescription_dispense"(prescription_id uuid, dispensed_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."prescriptions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."prescriptions" x where x."id" = record_prescription_dispense.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to record dispensing' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'sent' then
    raise exception 'only a sent prescription can be dispensed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  update "app_private"."prescriptions" x set "status" = 'dispensed', "dispensed_at" = coalesce(record_prescription_dispense.dispensed_at, now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."record_prescription_dispense"(uuid, timestamptz) from public, anon;
grant execute on function "app_private"."record_prescription_dispense"(uuid, timestamptz) to authenticated, service_role;

-- Cancels a prescription that is not dispensed. The prescriber, or a member with
-- e_prescribing.manage, cancels; a signed or sent one needs a reason.
create or replace function "app_private"."cancel_prescription"(prescription_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."prescriptions";
  v_reason text := nullif(trim(cancel_prescription.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."prescriptions" x where x."id" = cancel_prescription.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.manage'), false))) and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) and v_row."prescriber_id" is not distinct from auth.uid()) then
    raise exception 'only the prescriber or a manager cancels a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" in ('dispensed', 'cancelled') then
    raise exception 'a dispensed or cancelled prescription cannot be cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_reason is null and v_row."status" <> 'draft' then
    raise exception 'cancelling a signed or sent prescription needs a reason' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reason, '')) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  update "app_private"."prescriptions" x set "status" = 'cancelled', "cancelled_at" = now(), "cancel_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."cancel_prescription"(uuid, text) from public, anon;
grant execute on function "app_private"."cancel_prescription"(uuid, text) to authenticated, service_role;

-- One prescription. Needs e_prescribing.read.
create or replace function "app_private"."get_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."prescriptions";
begin
  select * into v_row from "app_private"."prescriptions" x where x."id" = get_prescription.prescription_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."get_prescription"(uuid) from public, anon;
grant execute on function "app_private"."get_prescription"(uuid) to authenticated, service_role;

-- The organization's prescriptions, newest first. filters is { orderId,
-- subjectType, subjectId, status, prescriberId, limit, offset }. Needs
-- e_prescribing.read.
create or replace function "app_private"."list_prescriptions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_prescriptions.tenant is not null and coalesce(better_supabase.can('tenant', list_prescriptions.tenant, 'e_prescribing.read'), false))) then
    raise exception 'not allowed to read prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_filters ->> 'status' is not null and v_filters ->> 'status' not in ('draft', 'signed', 'sent', 'dispensed', 'cancelled') then
    raise exception 'status is draft, signed, sent, dispensed or cancelled' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'orderId', q."order_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'prescriberId', q."prescriber_id", 'prescriberName', q."prescriber_name", 'status', q."status", 'order', q."snapshot", 'signedBy', q."signed_by", 'signedAt', q."signed_at", 'gateway', q."gateway", 'gatewayReference', q."gateway_reference", 'sentAt', q."sent_at", 'deliveryError', q."delivery_error", 'dispensedAt', q."dispensed_at", 'cancelledAt', q."cancelled_at", 'cancelReason', q."cancel_reason", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id")
    from (
      select y.* from "app_private"."prescriptions" y
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
$$;
revoke execute on function "app_private"."list_prescriptions"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_prescriptions"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."prescriptions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."prescriptions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."prescriptions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."prescriptions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block-data e-prescribing
-- @bsb-hash sha256:ee8e0a6f8aee44c28fe5af663969a83d12a0783824592651edb998fa04f281fe
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('e-prescribing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block e-prescribing@1 managed
-- @bsb-hash sha256:a5f451611c359f13cc2bc60a12467e95c2db1e9d68bc0c4dd5f7fc7ce4249b0a
-- Prescriptions over medication orders with the states draft, signed, sent, dispensed and cancelled, a signature only the prescriber can give, and delivery through a PrescriptionGateway port that carries a FHIR R4 MedicationRequest.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- E-prescribing: prescriptions over medication orders with states draft, signed,
-- sent, dispensed and cancelled, a signature only the prescriber can give, and
-- delivery recorded for a gateway that plugs in through the PrescriptionGateway
-- port.

-- A prescription of one medication order. It starts as a draft by the prescriber,
-- the prescriber signs it (snapshot freezes the order), a gateway delivers it
-- and the pharmacy dispenses it. Only the functions change it; a signed
-- prescription always has a signer and a time.
create table "better_supabase"."prescriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "prescriber_id" uuid not null,
  "prescriber_name" text constraint bsb_prescriptions_prescriber_name_check check ("prescriber_name" is null or length("prescriber_name") <= 300),
  "status" text not null default 'draft' constraint bsb_prescriptions_status_check check ("status" in ('draft', 'signed', 'sent', 'dispensed', 'cancelled')),
  "snapshot" jsonb,
  "signed_by" uuid,
  "signed_at" timestamptz,
  "gateway" text constraint bsb_prescriptions_gateway_check check ("gateway" is null or length("gateway") >= 1 and length("gateway") <= 100),
  "gateway_reference" text constraint bsb_prescriptions_gateway_reference_check check ("gateway_reference" is null or length("gateway_reference") <= 200),
  "sent_at" timestamptz,
  "delivery_error" text constraint bsb_prescriptions_delivery_error_check check ("delivery_error" is null or length("delivery_error") <= 1000),
  "dispensed_at" timestamptz,
  "cancelled_at" timestamptz,
  "cancel_reason" text constraint bsb_prescriptions_cancel_reason_check check ("cancel_reason" is null or length("cancel_reason") <= 1000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_prescriptions_check check ("status" in ('draft', 'cancelled') or ("signed_by" is not null and "signed_at" is not null and "snapshot" is not null)),
  constraint bsb_prescriptions_check1 check ("signed_by" is null or "signed_by" = "prescriber_id"),
  constraint bsb_prescriptions_check2 check ("status" not in ('sent', 'dispensed') or ("sent_at" is not null and "gateway" is not null)),
  constraint bsb_prescriptions_check3 check ("status" <> 'dispensed' or "dispensed_at" is not null),
  constraint bsb_prescriptions_check4 check ("status" <> 'cancelled' or "cancelled_at" is not null),
  foreign key ("tenant_id", "order_id") references "better_supabase"."medication_orders" ("tenant_id", "id")
);
create unique index "prescriptions_live_order_key" on "better_supabase"."prescriptions" ("tenant_id", "order_id") where "status" <> 'cancelled';
create index "prescriptions_order_idx" on "better_supabase"."prescriptions" ("tenant_id", "order_id");
create index "prescriptions_subject_idx" on "better_supabase"."prescriptions" ("tenant_id", "subject_type", "subject_id");
create index "prescriptions_status_idx" on "better_supabase"."prescriptions" ("tenant_id", "status");
alter table "better_supabase"."prescriptions" enable row level security;
revoke all on "better_supabase"."prescriptions" from public, anon, authenticated;
grant select on "better_supabase"."prescriptions" to authenticated;
grant all on "better_supabase"."prescriptions" to service_role;
create policy bsb_prescriptions_read on "better_supabase"."prescriptions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')));

-- What a signed prescription freezes: the order's dose, schedule and bounds with
-- the medication's name and code, so later edits of the order do not change it.
create or replace function "better_supabase"."prescription_order_snapshot"(tenant uuid, order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'orderId', x."id", 'medicationId', x."medication_id", 'medicationName', mx."name",
    'codeSystem', mx."code_system", 'code', mx."code", 'dose', x."dose", 'doseUnit', x."dose_unit",
    'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed",
    'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day",
    'startsOn', x."starts_on", 'endsOn', x."ends_on")
  from "better_supabase"."medication_orders" x join "better_supabase"."medications" mx on mx."tenant_id" = x."tenant_id" and mx."id" = x."medication_id"
  where x."tenant_id" = prescription_order_snapshot.tenant and x."id" = prescription_order_snapshot.order_id;
$$;
revoke all on function "better_supabase"."prescription_order_snapshot"(uuid, uuid) from public, anon, authenticated;

-- Drafts a prescription for an active medication order. The caller becomes the
-- prescriber; the service role names one in attrs.prescriberId. attrs is
-- { prescriberId, prescriberName }. Needs e_prescribing.write.
create or replace function "better_supabase"."create_prescription"(tenant uuid, order_id uuid, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'not allowed to draft prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  begin
    v_prescriber := coalesce(v_prescriber, nullif(v_attrs ->> 'prescriberId', '')::uuid);
  exception when invalid_text_representation then
    raise exception 'prescriberId is a uuid' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end;
  if v_prescriber is null then
    raise exception 'a prescription needs a prescriber' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_name is not null and length(v_name) > 300 then
    raise exception 'a prescriber name is up to 300 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = create_prescription.tenant and x."id" = create_prescription.order_id;
  if not found then
    raise exception 'the order is not one of the organization' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'only an active medication order can be prescribed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  begin
    insert into "better_supabase"."prescriptions" ("tenant_id", "order_id", "subject_type", "subject_id", "prescriber_id", "prescriber_name")
    values (create_prescription.tenant, v_order."id", v_order."subject_type", v_order."subject_id", v_prescriber, v_name)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'this order already has a prescription that is not cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) to authenticated, service_role;

-- Signs a draft. Only the prescriber signs, as a signed-in user holding
-- e_prescribing.sign; the service role never does. The order must still be
-- active and not ended. The signature freezes the order into the prescription.
create or replace function "better_supabase"."sign_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.sign'), false))) then
    raise exception 'not allowed to sign prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."prescriber_id" is distinct from auth.uid() or auth.uid() is null then
    raise exception 'only the prescriber signs a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft can be signed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = v_row."tenant_id" and x."id" = v_row."order_id";
  if not found or v_order."status" <> 'active' or (v_order."ends_on" is not null and v_order."ends_on" < (now() at time zone 'UTC')::date) then
    raise exception 'the order is no longer active' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
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
  null;
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
$$;
revoke execute on function "better_supabase"."sign_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."sign_prescription"(uuid) to authenticated, service_role;

-- Records what the gateway answered for a signed prescription: with an error it
-- stays signed so it can be sent again, otherwise it is sent. gateway is the
-- port's key and reference the gateway's id for it. Needs e_prescribing.write.
create or replace function "better_supabase"."record_prescription_delivery"(prescription_id uuid, gateway text, reference text default null, error text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to send prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_gateway is null or length(v_gateway) > 100 then
    raise exception 'gateway is 1 to 100 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reference, '')) > 200 or length(coalesce(v_error, '')) > 1000 then
    raise exception 'a reference is up to 200 characters and an error up to 1000' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_row."status" <> 'signed' then
    raise exception 'only a signed prescription can be sent' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_error is not null then
    update "better_supabase"."prescriptions" x set "gateway" = v_gateway, "delivery_error" = v_error, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "better_supabase"."prescriptions" x set "status" = 'sent', "gateway" = v_gateway, "gateway_reference" = v_reference,
      "sent_at" = now(), "delivery_error" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) to authenticated, service_role;

-- Marks a sent prescription as dispensed, when the pharmacy reports it. Needs
-- e_prescribing.write.
create or replace function "better_supabase"."record_prescription_dispense"(prescription_id uuid, dispensed_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = record_prescription_dispense.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to record dispensing' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'sent' then
    raise exception 'only a sent prescription can be dispensed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'dispensed', "dispensed_at" = coalesce(record_prescription_dispense.dispensed_at, now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) to authenticated, service_role;

-- Cancels a prescription that is not dispensed. The prescriber, or a member with
-- e_prescribing.manage, cancels; a signed or sent one needs a reason.
create or replace function "better_supabase"."cancel_prescription"(prescription_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.manage'), false))) and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) and v_row."prescriber_id" is not distinct from auth.uid()) then
    raise exception 'only the prescriber or a manager cancels a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" in ('dispensed', 'cancelled') then
    raise exception 'a dispensed or cancelled prescription cannot be cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_reason is null and v_row."status" <> 'draft' then
    raise exception 'cancelling a signed or sent prescription needs a reason' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reason, '')) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'cancelled', "cancelled_at" = now(), "cancel_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_prescription"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_prescription"(uuid, text) to authenticated, service_role;

-- One prescription. Needs e_prescribing.read.
create or replace function "better_supabase"."get_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = get_prescription.prescription_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."get_prescription"(uuid) to authenticated, service_role;

-- The organization's prescriptions, newest first. filters is { orderId,
-- subjectType, subjectId, status, prescriberId, limit, offset }. Needs
-- e_prescribing.read.
create or replace function "better_supabase"."list_prescriptions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_prescriptions.tenant is not null and coalesce(better_supabase.can('tenant', list_prescriptions.tenant, 'e_prescribing.read'), false))) then
    raise exception 'not allowed to read prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_filters ->> 'status' is not null and v_filters ->> 'status' not in ('draft', 'signed', 'sent', 'dispensed', 'cancelled') then
    raise exception 'status is draft, signed, sent, dispensed or cancelled' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
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
$$;
revoke execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."prescriptions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."prescriptions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."prescriptions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."prescriptions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.e-prescribing.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_prescription"(tenant uuid, order_id uuid, attrs jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_prescription"($1, $2, $3) $$;
revoke execute on function "api"."create_prescription"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."create_prescription"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."sign_prescription"(prescription_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sign_prescription"($1) $$;
revoke execute on function "api"."sign_prescription"(uuid) from public, anon;
grant execute on function "api"."sign_prescription"(uuid) to authenticated, service_role;

create or replace function "api"."record_prescription_delivery"(prescription_id uuid, gateway text, reference text default null, error text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_prescription_delivery"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_prescription_delivery"(uuid, text, text, text) from public, anon;
grant execute on function "api"."record_prescription_delivery"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."record_prescription_dispense"(prescription_id uuid, dispensed_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_prescription_dispense"($1, $2) $$;
revoke execute on function "api"."record_prescription_dispense"(uuid, timestamptz) from public, anon;
grant execute on function "api"."record_prescription_dispense"(uuid, timestamptz) to authenticated, service_role;

create or replace function "api"."cancel_prescription"(prescription_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_prescription"($1, $2) $$;
revoke execute on function "api"."cancel_prescription"(uuid, text) from public, anon;
grant execute on function "api"."cancel_prescription"(uuid, text) to authenticated, service_role;

create or replace function "api"."get_prescription"(prescription_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_prescription"($1) $$;
revoke execute on function "api"."get_prescription"(uuid) from public, anon;
grant execute on function "api"."get_prescription"(uuid) to authenticated, service_role;

create or replace function "api"."list_prescriptions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_prescriptions"($1, $2) $$;
revoke execute on function "api"."list_prescriptions"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_prescriptions"(uuid, jsonb) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block-data e-prescribing
-- @bsb-hash sha256:ee8e0a6f8aee44c28fe5af663969a83d12a0783824592651edb998fa04f281fe
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('e-prescribing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block e-prescribing@1 managed
-- @bsb-hash sha256:998f5e8c06d19805d6808ce1e9e033cb66e4f8eb634467af2f100c2242dbe991
-- Prescriptions over medication orders with the states draft, signed, sent, dispensed and cancelled, a signature only the prescriber can give, and delivery through a PrescriptionGateway port that carries a FHIR R4 MedicationRequest.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- E-prescribing: prescriptions over medication orders with states draft, signed,
-- sent, dispensed and cancelled, a signature only the prescriber can give, and
-- delivery recorded for a gateway that plugs in through the PrescriptionGateway
-- port.

-- A prescription of one medication order. It starts as a draft by the prescriber,
-- the prescriber signs it (snapshot freezes the order), a gateway delivers it
-- and the pharmacy dispenses it. Only the functions change it; a signed
-- prescription always has a signer and a time.
-- better_supabase.prescriptions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."prescriptions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."prescriptions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."prescriptions" add column if not exists "order_id" uuid;
alter table "better_supabase"."prescriptions" add column if not exists "subject_type" text;
alter table "better_supabase"."prescriptions" add column if not exists "subject_id" text;
alter table "better_supabase"."prescriptions" add column if not exists "prescriber_id" uuid;
alter table "better_supabase"."prescriptions" add column if not exists "prescriber_name" text constraint bsb_prescriptions_prescriber_name_check check ("prescriber_name" is null or length("prescriber_name") <= 300);
alter table "better_supabase"."prescriptions" add column if not exists "status" text not null default 'draft' constraint bsb_prescriptions_status_check check ("status" in ('draft', 'signed', 'sent', 'dispensed', 'cancelled'));
alter table "better_supabase"."prescriptions" add column if not exists "snapshot" jsonb;
alter table "better_supabase"."prescriptions" add column if not exists "signed_by" uuid;
alter table "better_supabase"."prescriptions" add column if not exists "signed_at" timestamptz;
alter table "better_supabase"."prescriptions" add column if not exists "gateway" text constraint bsb_prescriptions_gateway_check check ("gateway" is null or length("gateway") >= 1 and length("gateway") <= 100);
alter table "better_supabase"."prescriptions" add column if not exists "gateway_reference" text constraint bsb_prescriptions_gateway_reference_check check ("gateway_reference" is null or length("gateway_reference") <= 200);
alter table "better_supabase"."prescriptions" add column if not exists "sent_at" timestamptz;
alter table "better_supabase"."prescriptions" add column if not exists "delivery_error" text constraint bsb_prescriptions_delivery_error_check check ("delivery_error" is null or length("delivery_error") <= 1000);
alter table "better_supabase"."prescriptions" add column if not exists "dispensed_at" timestamptz;
alter table "better_supabase"."prescriptions" add column if not exists "cancelled_at" timestamptz;
alter table "better_supabase"."prescriptions" add column if not exists "cancel_reason" text constraint bsb_prescriptions_cancel_reason_check check ("cancel_reason" is null or length("cancel_reason") <= 1000);
alter table "better_supabase"."prescriptions" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."prescriptions" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_prescriptions_tenant_id_key" on "better_supabase"."prescriptions" ("tenant_id", "id");
create unique index if not exists "prescriptions_live_order_key" on "better_supabase"."prescriptions" ("tenant_id", "order_id") where "status" <> 'cancelled';
create index if not exists "prescriptions_order_idx" on "better_supabase"."prescriptions" ("tenant_id", "order_id");
create index if not exists "prescriptions_subject_idx" on "better_supabase"."prescriptions" ("tenant_id", "subject_type", "subject_id");
create index if not exists "prescriptions_status_idx" on "better_supabase"."prescriptions" ("tenant_id", "status");
alter table "better_supabase"."prescriptions" enable row level security;
grant select on "better_supabase"."prescriptions" to authenticated;
grant all on "better_supabase"."prescriptions" to service_role;
create policy bsb_prescriptions_read on "better_supabase"."prescriptions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')));

-- What a signed prescription freezes: the order's dose, schedule and bounds with
-- the medication's name and code, so later edits of the order do not change it.
create or replace function "better_supabase"."prescription_order_snapshot"(tenant uuid, order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'orderId', x."id", 'medicationId', x."medication_id", 'medicationName', mx."name",
    'codeSystem', mx."code_system", 'code', mx."code", 'dose', x."dose", 'doseUnit', x."dose_unit",
    'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed",
    'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day",
    'startsOn', x."starts_on", 'endsOn', x."ends_on")
  from "better_supabase"."medication_orders" x join "better_supabase"."medications" mx on mx."tenant_id" = x."tenant_id" and mx."id" = x."medication_id"
  where x."tenant_id" = prescription_order_snapshot.tenant and x."id" = prescription_order_snapshot.order_id;
$$;
revoke all on function "better_supabase"."prescription_order_snapshot"(uuid, uuid) from public, anon, authenticated;

-- Drafts a prescription for an active medication order. The caller becomes the
-- prescriber; the service role names one in attrs.prescriberId. attrs is
-- { prescriberId, prescriberName }. Needs e_prescribing.write.
create or replace function "better_supabase"."create_prescription"(tenant uuid, order_id uuid, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'not allowed to draft prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  begin
    v_prescriber := coalesce(v_prescriber, nullif(v_attrs ->> 'prescriberId', '')::uuid);
  exception when invalid_text_representation then
    raise exception 'prescriberId is a uuid' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end;
  if v_prescriber is null then
    raise exception 'a prescription needs a prescriber' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_name is not null and length(v_name) > 300 then
    raise exception 'a prescriber name is up to 300 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = create_prescription.tenant and x."id" = create_prescription.order_id;
  if not found then
    raise exception 'the order is not one of the organization' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'only an active medication order can be prescribed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  begin
    insert into "better_supabase"."prescriptions" ("tenant_id", "order_id", "subject_type", "subject_id", "prescriber_id", "prescriber_name")
    values (create_prescription.tenant, v_order."id", v_order."subject_type", v_order."subject_id", v_prescriber, v_name)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'this order already has a prescription that is not cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) to authenticated, service_role;

-- Signs a draft. Only the prescriber signs, as a signed-in user holding
-- e_prescribing.sign; the service role never does. The order must still be
-- active and not ended. The signature freezes the order into the prescription.
create or replace function "better_supabase"."sign_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.sign'), false))) then
    raise exception 'not allowed to sign prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."prescriber_id" is distinct from auth.uid() or auth.uid() is null then
    raise exception 'only the prescriber signs a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft can be signed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = v_row."tenant_id" and x."id" = v_row."order_id";
  if not found or v_order."status" <> 'active' or (v_order."ends_on" is not null and v_order."ends_on" < (now() at time zone 'UTC')::date) then
    raise exception 'the order is no longer active' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
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
  null;
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
$$;
revoke execute on function "better_supabase"."sign_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."sign_prescription"(uuid) to authenticated, service_role;

-- Records what the gateway answered for a signed prescription: with an error it
-- stays signed so it can be sent again, otherwise it is sent. gateway is the
-- port's key and reference the gateway's id for it. Needs e_prescribing.write.
create or replace function "better_supabase"."record_prescription_delivery"(prescription_id uuid, gateway text, reference text default null, error text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to send prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_gateway is null or length(v_gateway) > 100 then
    raise exception 'gateway is 1 to 100 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reference, '')) > 200 or length(coalesce(v_error, '')) > 1000 then
    raise exception 'a reference is up to 200 characters and an error up to 1000' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_row."status" <> 'signed' then
    raise exception 'only a signed prescription can be sent' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_error is not null then
    update "better_supabase"."prescriptions" x set "gateway" = v_gateway, "delivery_error" = v_error, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "better_supabase"."prescriptions" x set "status" = 'sent', "gateway" = v_gateway, "gateway_reference" = v_reference,
      "sent_at" = now(), "delivery_error" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) to authenticated, service_role;

-- Marks a sent prescription as dispensed, when the pharmacy reports it. Needs
-- e_prescribing.write.
create or replace function "better_supabase"."record_prescription_dispense"(prescription_id uuid, dispensed_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = record_prescription_dispense.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to record dispensing' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'sent' then
    raise exception 'only a sent prescription can be dispensed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'dispensed', "dispensed_at" = coalesce(record_prescription_dispense.dispensed_at, now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) to authenticated, service_role;

-- Cancels a prescription that is not dispensed. The prescriber, or a member with
-- e_prescribing.manage, cancels; a signed or sent one needs a reason.
create or replace function "better_supabase"."cancel_prescription"(prescription_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.manage'), false))) and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) and v_row."prescriber_id" is not distinct from auth.uid()) then
    raise exception 'only the prescriber or a manager cancels a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" in ('dispensed', 'cancelled') then
    raise exception 'a dispensed or cancelled prescription cannot be cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_reason is null and v_row."status" <> 'draft' then
    raise exception 'cancelling a signed or sent prescription needs a reason' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reason, '')) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'cancelled', "cancelled_at" = now(), "cancel_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_prescription"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_prescription"(uuid, text) to authenticated, service_role;

-- One prescription. Needs e_prescribing.read.
create or replace function "better_supabase"."get_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = get_prescription.prescription_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."get_prescription"(uuid) to authenticated, service_role;

-- The organization's prescriptions, newest first. filters is { orderId,
-- subjectType, subjectId, status, prescriberId, limit, offset }. Needs
-- e_prescribing.read.
create or replace function "better_supabase"."list_prescriptions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_prescriptions.tenant is not null and coalesce(better_supabase.can('tenant', list_prescriptions.tenant, 'e_prescribing.read'), false))) then
    raise exception 'not allowed to read prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_filters ->> 'status' is not null and v_filters ->> 'status' not in ('draft', 'signed', 'sent', 'dispensed', 'cancelled') then
    raise exception 'status is draft, signed, sent, dispensed or cancelled' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
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
$$;
revoke execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."prescriptions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."prescriptions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."prescriptions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."prescriptions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block-data e-prescribing
-- @bsb-hash sha256:ee8e0a6f8aee44c28fe5af663969a83d12a0783824592651edb998fa04f281fe
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('e-prescribing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block e-prescribing@1 managed
-- @bsb-hash sha256:99b0e763c3620536d76e2c36ccae2925015b720a9ab199d7fe0c353414aef5a0
-- Prescriptions over medication orders with the states draft, signed, sent, dispensed and cancelled, a signature only the prescriber can give, and delivery through a PrescriptionGateway port that carries a FHIR R4 MedicationRequest.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- E-prescribing: prescriptions over medication orders with states draft, signed,
-- sent, dispensed and cancelled, a signature only the prescriber can give, and
-- delivery recorded for a gateway that plugs in through the PrescriptionGateway
-- port.

-- A prescription of one medication order. It starts as a draft by the prescriber,
-- the prescriber signs it (snapshot freezes the order), a gateway delivers it
-- and the pharmacy dispenses it. Only the functions change it; a signed
-- prescription always has a signer and a time.
create table "better_supabase"."prescriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "order_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "prescriber_id" uuid not null,
  "prescriber_name" text constraint bsb_prescriptions_prescriber_name_check check ("prescriber_name" is null or length("prescriber_name") <= 300),
  "status" text not null default 'draft' constraint bsb_prescriptions_status_check check ("status" in ('draft', 'signed', 'sent', 'dispensed', 'cancelled')),
  "snapshot" jsonb,
  "signed_by" uuid,
  "signed_at" timestamptz,
  "gateway" text constraint bsb_prescriptions_gateway_check check ("gateway" is null or length("gateway") >= 1 and length("gateway") <= 100),
  "gateway_reference" text constraint bsb_prescriptions_gateway_reference_check check ("gateway_reference" is null or length("gateway_reference") <= 200),
  "sent_at" timestamptz,
  "delivery_error" text constraint bsb_prescriptions_delivery_error_check check ("delivery_error" is null or length("delivery_error") <= 1000),
  "dispensed_at" timestamptz,
  "cancelled_at" timestamptz,
  "cancel_reason" text constraint bsb_prescriptions_cancel_reason_check check ("cancel_reason" is null or length("cancel_reason") <= 1000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_prescriptions_check check ("status" in ('draft', 'cancelled') or ("signed_by" is not null and "signed_at" is not null and "snapshot" is not null)),
  constraint bsb_prescriptions_check1 check ("signed_by" is null or "signed_by" = "prescriber_id"),
  constraint bsb_prescriptions_check2 check ("status" not in ('sent', 'dispensed') or ("sent_at" is not null and "gateway" is not null)),
  constraint bsb_prescriptions_check3 check ("status" <> 'dispensed' or "dispensed_at" is not null),
  constraint bsb_prescriptions_check4 check ("status" <> 'cancelled' or "cancelled_at" is not null),
  foreign key ("org_id", "order_id") references "better_supabase"."medication_orders" ("org_id", "id")
);
create unique index "prescriptions_live_order_key" on "better_supabase"."prescriptions" ("org_id", "order_id") where "status" <> 'cancelled';
create index "prescriptions_order_idx" on "better_supabase"."prescriptions" ("org_id", "order_id");
create index "prescriptions_subject_idx" on "better_supabase"."prescriptions" ("org_id", "subject_type", "subject_id");
create index "prescriptions_status_idx" on "better_supabase"."prescriptions" ("org_id", "status");
alter table "better_supabase"."prescriptions" enable row level security;
revoke all on "better_supabase"."prescriptions" from public, anon, authenticated;
grant select on "better_supabase"."prescriptions" to authenticated;
grant all on "better_supabase"."prescriptions" to service_role;
create policy bsb_prescriptions_read on "better_supabase"."prescriptions"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')));

-- What a signed prescription freezes: the order's dose, schedule and bounds with
-- the medication's name and code, so later edits of the order do not change it.
create or replace function "better_supabase"."prescription_order_snapshot"(tenant uuid, order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'orderId', x."id", 'medicationId', x."medication_id", 'medicationName', mx."name",
    'codeSystem', mx."code_system", 'code', mx."code", 'dose', x."dose", 'doseUnit', x."dose_unit",
    'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed",
    'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day",
    'startsOn', x."starts_on", 'endsOn', x."ends_on")
  from "better_supabase"."medication_orders" x join "better_supabase"."medications" mx on mx."org_id" = x."org_id" and mx."id" = x."medication_id"
  where x."org_id" = prescription_order_snapshot.tenant and x."id" = prescription_order_snapshot.order_id;
$$;
revoke all on function "better_supabase"."prescription_order_snapshot"(uuid, uuid) from public, anon, authenticated;

-- Drafts a prescription for an active medication order. The caller becomes the
-- prescriber; the service role names one in attrs.prescriberId. attrs is
-- { prescriberId, prescriberName }. Needs e_prescribing.write.
create or replace function "better_supabase"."create_prescription"(tenant uuid, order_id uuid, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'not allowed to draft prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  begin
    v_prescriber := coalesce(v_prescriber, nullif(v_attrs ->> 'prescriberId', '')::uuid);
  exception when invalid_text_representation then
    raise exception 'prescriberId is a uuid' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end;
  if v_prescriber is null then
    raise exception 'a prescription needs a prescriber' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_name is not null and length(v_name) > 300 then
    raise exception 'a prescriber name is up to 300 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."org_id" = create_prescription.tenant and x."id" = create_prescription.order_id;
  if not found then
    raise exception 'the order is not one of the organization' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'only an active medication order can be prescribed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  begin
    insert into "better_supabase"."prescriptions" ("org_id", "order_id", "subject_type", "subject_id", "prescriber_id", "prescriber_name")
    values (create_prescription.tenant, v_order."id", v_order."subject_type", v_order."subject_id", v_prescriber, v_name)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'this order already has a prescription that is not cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_prescription"(uuid, uuid, jsonb) to authenticated, service_role;

-- Signs a draft. Only the prescriber signs, as a signed-in user holding
-- e_prescribing.sign; the service role never does. The order must still be
-- active and not ended. The signature freezes the order into the prescription.
create or replace function "better_supabase"."sign_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
  v_order "better_supabase"."medication_orders";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = sign_prescription.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.sign'), false))) then
    raise exception 'not allowed to sign prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."prescriber_id" is distinct from auth.uid() or auth.uid() is null then
    raise exception 'only the prescriber signs a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft can be signed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."org_id" = v_row."org_id" and x."id" = v_row."order_id";
  if not found or v_order."status" <> 'active' or (v_order."ends_on" is not null and v_order."ends_on" < (now() at time zone 'UTC')::date) then
    raise exception 'the order is no longer active' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
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
    "snapshot" = "better_supabase"."prescription_order_snapshot"(v_row."org_id", v_row."order_id"), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_prescription_sign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."sign_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."sign_prescription"(uuid) to authenticated, service_role;

-- Records what the gateway answered for a signed prescription: with an error it
-- stays signed so it can be sent again, otherwise it is sent. gateway is the
-- port's key and reference the gateway's id for it. Needs e_prescribing.write.
create or replace function "better_supabase"."record_prescription_delivery"(prescription_id uuid, gateway text, reference text default null, error text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to send prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_gateway is null or length(v_gateway) > 100 then
    raise exception 'gateway is 1 to 100 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reference, '')) > 200 or length(coalesce(v_error, '')) > 1000 then
    raise exception 'a reference is up to 200 characters and an error up to 1000' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_row."status" <> 'signed' then
    raise exception 'only a signed prescription can be sent' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_error is not null then
    update "better_supabase"."prescriptions" x set "gateway" = v_gateway, "delivery_error" = v_error, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    update "better_supabase"."prescriptions" x set "status" = 'sent', "gateway" = v_gateway, "gateway_reference" = v_reference,
      "sent_at" = now(), "delivery_error" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_prescription_delivery"(uuid, text, text, text) to authenticated, service_role;

-- Marks a sent prescription as dispensed, when the pharmacy reports it. Needs
-- e_prescribing.write.
create or replace function "better_supabase"."record_prescription_dispense"(prescription_id uuid, dispensed_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = record_prescription_dispense.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to record dispensing' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'sent' then
    raise exception 'only a sent prescription can be dispensed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'dispensed', "dispensed_at" = coalesce(record_prescription_dispense.dispensed_at, now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."record_prescription_dispense"(uuid, timestamptz) to authenticated, service_role;

-- Cancels a prescription that is not dispensed. The prescriber, or a member with
-- e_prescribing.manage, cancels; a signed or sent one needs a reason.
create or replace function "better_supabase"."cancel_prescription"(prescription_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
  v_reason text := nullif(trim(cancel_prescription.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = cancel_prescription.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.manage'), false))) and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.write'), false))) and v_row."prescriber_id" is not distinct from auth.uid()) then
    raise exception 'only the prescriber or a manager cancels a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" in ('dispensed', 'cancelled') then
    raise exception 'a dispensed or cancelled prescription cannot be cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_reason is null and v_row."status" <> 'draft' then
    raise exception 'cancelling a signed or sent prescription needs a reason' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reason, '')) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'cancelled', "cancelled_at" = now(), "cancel_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_prescription"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_prescription"(uuid, text) to authenticated, service_role;

-- One prescription. Needs e_prescribing.read.
create or replace function "better_supabase"."get_prescription"(prescription_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = get_prescription.prescription_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_prescription"(uuid) from public, anon;
grant execute on function "better_supabase"."get_prescription"(uuid) to authenticated, service_role;

-- The organization's prescriptions, newest first. filters is { orderId,
-- subjectType, subjectId, status, prescriberId, limit, offset }. Needs
-- e_prescribing.read.
create or replace function "better_supabase"."list_prescriptions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_prescriptions.tenant is not null and coalesce(better_supabase.can('tenant', list_prescriptions.tenant, 'e_prescribing.read'), false))) then
    raise exception 'not allowed to read prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_filters ->> 'status' is not null and v_filters ->> 'status' not in ('draft', 'signed', 'sent', 'dispensed', 'cancelled') then
    raise exception 'status is draft, signed, sent, dispensed or cancelled' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."org_id", 'orderId', q."order_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'prescriberId', q."prescriber_id", 'prescriberName', q."prescriber_name", 'status', q."status", 'order', q."snapshot", 'signedBy', q."signed_by", 'signedAt', q."signed_at", 'gateway', q."gateway", 'gatewayReference', q."gateway_reference", 'sentAt', q."sent_at", 'deliveryError', q."delivery_error", 'dispensedAt', q."dispensed_at", 'cancelledAt', q."cancelled_at", 'cancelReason', q."cancel_reason", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id")
    from (
      select y.* from "better_supabase"."prescriptions" y
      where y."org_id" = list_prescriptions.tenant
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
$$;
revoke execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_prescriptions"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."prescriptions" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('e_prescribing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."prescriptions" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."prescriptions" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."prescriptions" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_177_e_prescribing.sql
-- better-supabase module: e-prescribing
-- @bsb-block-data e-prescribing
-- @bsb-hash sha256:ee8e0a6f8aee44c28fe5af663969a83d12a0783824592651edb998fa04f281fe
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('e-prescribing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
