SET local check_function_bodies = off;

DROP POLICY "activity_entries_read" ON "better_supabase"."activity_entries";

ALTER TABLE "better_supabase"."invoice_payments"
  DROP CONSTRAINT "invoice_payments_invoice_id_fkey";

ALTER TABLE "better_supabase"."stock_movements"
  DROP CONSTRAINT "stock_movements_location_id_fkey";

ALTER TABLE "better_supabase"."stock_movements"
  DROP CONSTRAINT "stock_movements_variant_id_fkey";

DROP TABLE "better_supabase"."invoice_payments";

DROP TABLE "better_supabase"."stock_movements";

DROP FUNCTION "better_supabase"."apply_stock_movement"();

DROP FUNCTION "better_supabase"."stock_movements_append_only"();

CREATE TABLE "better_supabase"."ledger_accounts" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "kind"            text                     NOT NULL,
  "code"            text                     NOT NULL,
  "name"            text                     NOT NULL,
  "unit"            text                     NOT NULL,
  "scale"           smallint                 NOT NULL DEFAULT 0,
  "holder_type"     text,
  "holder_id"       text,
  "owner_id"        uuid,
  "allow_negative"  boolean                  NOT NULL DEFAULT false,
  "read_permission" text,
  "managed_by"      text,
  "metadata"        jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "closed_at"       timestamp with time zone,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ledger_accounts_check" CHECK (((holder_type IS NULL) = (holder_id IS NULL))),
  CONSTRAINT "ledger_accounts_code_check" CHECK (((length(code) >= 1) AND (length(code) <= 200))),
  CONSTRAINT "ledger_accounts_kind_check" CHECK ((kind ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "ledger_accounts_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "ledger_accounts_pkey" PRIMARY KEY (id),
  CONSTRAINT "ledger_accounts_scale_check" CHECK (((scale >= 0) AND (scale <= 6))),
  CONSTRAINT "ledger_accounts_tenant_id_code_key" UNIQUE (tenant_id, code),
  CONSTRAINT "ledger_accounts_unit_check" CHECK ((unit ~ '^([A-Z]{3}|[a-z][a-z0-9_]{0,31})$'::text))
);

ALTER TABLE "better_supabase"."ledger_accounts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ledger_balances" (
  "account_id" uuid                     NOT NULL,
  "tenant_id"  uuid                     NOT NULL,
  "balance"    bigint                   NOT NULL DEFAULT 0,
  "held"       bigint                   NOT NULL DEFAULT 0,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ledger_balances_held_check" CHECK ((held >= 0)),
  CONSTRAINT "ledger_balances_pkey" PRIMARY KEY (account_id)
);

ALTER TABLE "better_supabase"."ledger_balances"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ledger_entries" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid                     NOT NULL,
  "transaction_id" uuid                     NOT NULL,
  "account_id"     uuid                     NOT NULL,
  "amount"         bigint                   NOT NULL,
  "unit"           text                     NOT NULL,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ledger_entries_amount_check" CHECK ((amount <> 0)),
  CONSTRAINT "ledger_entries_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."ledger_entries"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ledger_holds" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid                     NOT NULL,
  "account_id"     uuid                     NOT NULL,
  "amount"         bigint                   NOT NULL,
  "status"         text                     NOT NULL DEFAULT 'active'::text,
  "reference_type" text,
  "reference_id"   text,
  "expires_at"     timestamp with time zone,
  "transaction_id" uuid,
  "created_by"     uuid,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ledger_holds_amount_check" CHECK ((amount > 0)),
  CONSTRAINT "ledger_holds_pkey" PRIMARY KEY (id),
  CONSTRAINT "ledger_holds_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'captured'::text, 'released'::text, 'expired'::text])))
);

ALTER TABLE "better_supabase"."ledger_holds"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ledger_transactions" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "kind"            text                     NOT NULL,
  "reference_type"  text,
  "reference_id"    text,
  "memo"            text,
  "idempotency_key" text,
  "reverses"        uuid,
  "metadata"        jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "effective_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "actor_id"        uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ledger_transactions_kind_check" CHECK ((kind ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$'::text)),
  CONSTRAINT "ledger_transactions_memo_check" CHECK (((memo IS NULL) OR (length(memo) <= 2000))),
  CONSTRAINT "ledger_transactions_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."ledger_transactions"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."ledger_balances"
  ADD COLUMN "available" bigint GENERATED ALWAYS AS ((balance - held)) STORED;

CREATE OR REPLACE FUNCTION better_supabase.activity_subject_deliveries (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  before       timestamp with time zone,
  max_rows     integer
)
  RETURNS TABLE (
    entry jsonb,
    at    timestamp with time zone,
    id    text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  select jsonb_build_object('id', d."id"::text, 'organization_id', ev."organization_id", 'event_id', null::text, 'type', 'delivery.' || d."status", 'actor_id', null::uuid, 'subject_type', activity_subject_deliveries.subject_type, 'subject_id', activity_subject_deliveries.subject_id, 'summary', ev."summary", 'data', jsonb_strip_nulls(jsonb_build_object('notificationId', ev."id", 'notificationType', ev."type", 'channel', d."channel", 'status', d."status", 'userId', rc."user_id", 'providerStatus', d."provider_status", 'templateKey', d."template_key", 'error', d."error", 'deliveredAt', d."delivered_at")), 'occurred_at', d."created_at", 'source', 'delivery'),
    d."created_at", d."id"::text
  from "better_supabase"."notification_deliveries" d
  join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where activity_subject_deliveries.subject_type = any ('{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,document,customer,drive_node,application,project,task}'::text[])
    and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
      or (coalesce(better_supabase.can('tenant', activity_subject_deliveries.tenant, 'activity.read'), false) and coalesce(better_supabase.can('tenant', activity_subject_deliveries.tenant, 'notifications.send'), false)))
    and ev."organization_id" = activity_subject_deliveries.tenant
    and ev."subject_type" = activity_subject_deliveries.subject_type
    and ev."subject_id" = activity_subject_deliveries.subject_id
    and (activity_subject_deliveries.before is null or d."created_at" < activity_subject_deliveries.before)
  order by d."created_at" desc, d."id" desc
  limit least(greatest(coalesce(activity_subject_deliveries.max_rows, 50), 1), 500);
end;
$function$;

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

CREATE OR REPLACE FUNCTION better_supabase.apply_to_job (
  job       uuid,
  candidate jsonb,
  source    text,
  owner     uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_job "better_supabase"."jobs";
  v_row "better_supabase"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "better_supabase"."jobs" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'HIRING_JOB_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'HIRING_JOB_NOT_OPEN';
  end if;
  if v_id is null or not (case v_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_type, v_id, 'read')) then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_user_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  perform "better_supabase".emit_event('application.created', jsonb_build_object('organizationId', v_row."tenant_id", 'applicationId', v_row."id", 'subjectType', 'application', 'subjectId', v_row."id"::text, 'jobId', v_row."job_id", 'candidateType', v_row."candidate_type", 'candidateId', v_row."candidate_id"), 'applications/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/hiring');
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select subject_type is null or case subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case can_subject.subject_type
    when 'comment' then
      return exists (
        select 1 from "better_supabase"."comments" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."organization_id", 'comments.create'), false)
          else true
        end)
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end)
      );
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.write'), false)
          else true
        end)
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.write'), false)
          else true
        end)
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end)
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.manage'), false)
          else true
        end)
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.write'), false)
          else true
        end)
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.write'), false)
          else true
        end)
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false)
          else true
        end)
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          else true
        end)
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end)
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and true
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    else
      return false;
  end case;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject_for (
  member       uuid,
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  case can_subject_for.subject_type
    when 'comment' then
      return exists (
        select 1 from "better_supabase"."comments" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'comments.create'), false)
          else false
        end
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.write'), false)
          else false
        end
      );
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.write'), false)
          else false
        end
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.write'), false)
          else false
        end
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.write'), false)
          else false
        end
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.manage'), false)
          else false
        end
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.write'), false)
          else false
        end
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.write'), false)
          else false
        end
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.write'), false)
          else false
        end
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.manage'), false)
          else false
        end
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.write'), false)
          else false
        end
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and false
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_transfer (
  transfer uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = cancel_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('draft', 'in_transit') then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  if v_row.status = 'in_transit' then
    perform "better_supabase"."move_stock"(v_row.tenant, x."variant_id", v_row.from_location, x."quantity", 'transfer_in', 'transfer', cancel_transfer.transfer::text, null)
  from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = cancel_transfer.transfer;
  end if;
  update "better_supabase"."stock_transfers" x set "status" = 'cancelled' where x."id" = cancel_transfer.transfer;
  perform "better_supabase".emit_event('transfer.cancelled', jsonb_build_object('organizationId', v_row.tenant, 'id', cancel_transfer.transfer, 'from', v_row.from_location, 'to', v_row.to_location, 'status', 'cancelled'), 'stock-transfers/' || cancel_transfer.transfer::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.capture_ledger_hold (
  hold_id    uuid,
  to_account uuid,
  amount     bigint DEFAULT NULL::bigint,
  kind       text   DEFAULT 'ledger.capture'::text,
  memo       text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
  v_amount bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = capture_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  v_amount := coalesce(capture_ledger_hold.amount, v_row."amount");
  if v_amount <= 0 or v_amount > v_row."amount" then
    raise exception 'a capture takes more than zero and at most the held amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x where x."id" = capture_ledger_hold.to_account and x."managed_by" is not null) and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_row := "better_supabase"."ledger_unhold"(v_row."id", 'captured');
  update "better_supabase"."ledger_holds" x set "transaction_id" = "better_supabase"."ledger_post"(v_row."tenant_id", coalesce(capture_ledger_hold.kind, 'ledger.capture'),
      jsonb_build_array(
        jsonb_build_object('account', v_row."account_id", 'amount', (-v_amount)::text),
        jsonb_build_object('account', capture_ledger_hold.to_account, 'amount', v_amount::text)),
      v_row."reference_type", v_row."reference_id", capture_ledger_hold.memo)
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('ledger_hold.captured', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'transactionId', v_row."transaction_id"), 'ledger-holds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_ledger_account (
  account_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ledger_accounts" x where x."id" = close_ledger_account.account_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or v_row."owner_id" = auth.uid() or (v_row."read_permission" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", v_row."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_row."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  select * into v_balance from "better_supabase"."ledger_balances" x where x."account_id" = v_row."id" for update;
  if coalesce(v_balance."balance", 0) <> 0 or coalesce(v_balance."held", 0) <> 0 then
    raise exception 'only an account with a zero balance and no holds can be closed' using errcode = '55000', hint = 'LEDGER_ACCOUNT_NOT_EMPTY';
  end if;
  if v_row."closed_at" is null then
    update "better_supabase"."ledger_accounts" x set "closed_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('ledger_account.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id"), 'ledger-accounts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  perform better_supabase.audit_event(
    event_type => 'ledger_account.closed',
    category => 'billing',
    target_type => 'ledger_account',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'closed ledger account ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_after_write()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_new uuid[];
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."deleted_at" is not null then
    perform "better_supabase".emit_event('comment.deleted', jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id"), 'comments/' || new."id"::text, (new."organization_id")::text, null, 'better-supabase/comments');
  perform better_supabase.audit_event(
    event_type => 'comment.deleted',
    category => 'data',
    target_type => 'comment',
    record_id => new."id"::text,
    tenant => (new."organization_id")::uuid,
    metadata => jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id")
  );
    return null;
  end if;
  v_new := array(
    select x from unnest(new."mentions") x
    where (tg_op = 'INSERT' or not x = any(old."mentions"))
      and coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'comments.read'), false)
      and case new."subject_type" when 'comment' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'comments.read'), false) when 'company' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'parties.read'), false) when 'person' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'parties.read'), false) when 'deal' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'deals.read'), false) when 'engagement' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'engagements.read'), false) when 'work_item' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'work_items.read'), false) when 'employee' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'employees.read'), false) when 'ledger_account' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'ledger.read'), false) when 'product' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'catalog.read'), false) when 'product_variant' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'catalog.read'), false) when 'calendar_event' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'calendar.read'), false) when 'document' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'documents.read'), false) when 'customer' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'customers.read'), false) when 'drive_node' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'drive.read'), false) when 'application' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'hiring.read'), false) else true end
  );
  if tg_op = 'INSERT' then
    perform "better_supabase".emit_event('comment.created', jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id", 'parentId', new."parent_id", 'mentionIds', to_jsonb(new."mentions")), 'comments/' || new."id"::text, (new."organization_id")::text, null, 'better-supabase/comments');
  end if;
  if cardinality(v_new) > 0 then
    perform "better_supabase".emit_event('comment.mentioned', jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id", 'mentionIds', to_jsonb(v_new)), 'comments/' || new."id"::text, (new."organization_id")::text, null, 'better-supabase/comments');
  end if;
  -- notify() trusts only the service role, so the mention is sent as it,
  -- with the comment's author as the actor; the claims are restored after.
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'comment.mentioned',
      'tenant', new."organization_id",
      'actor', new."author_id",
      'subject_type', new."subject_type",
      'subject_id', new."subject_id",
      'summary', left(new."body", 140),
      'subject_label', null::text,
      'action_path', null::text,
      'recipients', to_jsonb(v_new),
      'key', 'comment.mentioned:' || new."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('commentId', new."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  -- The author and newly mentioned members follow the subject
  -- (participating); a level a member already chose stays.
  insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
  select distinct new."organization_id", f.x, new."subject_type", new."subject_id", 'participating'
  from unnest(case when tg_op = 'INSERT' then array[new."author_id"] else '{}'::uuid[] end || v_new) f(x)
  where f.x is not null
  on conflict do nothing;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.commit_reservation (
  reservation uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
  v_movement uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."variant_id" as variant, x."location_id" as location,
    x."quantity" as quantity, x."status" as status, x."expires_at" as expires_at,
    x."reference_type" as reference_type, x."reference_id" as reference_id
  into v_row from "better_supabase"."stock_reservations" x where x."id" = commit_reservation.reservation for update;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002', hint = 'INVENTORY_RESERVATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.reserve'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'active' then
    raise exception 'the reservation is no longer active' using errcode = '55000', hint = 'INVENTORY_RESERVATION_CLOSED';
  end if;
  if v_row.expires_at <= now() then
    raise exception 'the reservation has expired' using errcode = '55000', hint = 'INVENTORY_RESERVATION_EXPIRED';
  end if;
  update "better_supabase"."stock_levels" x set "reserved" = greatest(x."reserved" - v_row.quantity, 0), "updated_at" = now()
  where x."variant_id" = v_row.variant and x."location_id" = v_row.location;
  update "better_supabase"."stock_reservations" x set "status" = 'committed', "updated_at" = now()
  where x."id" = commit_reservation.reservation;
  v_movement := "better_supabase"."move_stock"(v_row.tenant, v_row.variant, v_row.location, -v_row.quantity, 'sale', v_row.reference_type, v_row.reference_id, null);
  perform "better_supabase".emit_event('reservation.committed', jsonb_build_object('organizationId', v_row.tenant, 'id', commit_reservation.reservation, 'variantId', v_row.variant, 'locationId', v_row.location, 'quantity', v_row.quantity::text), 'stock-reservations/' || commit_reservation.reservation::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return jsonb_build_object('id', commit_reservation.reservation, 'movementId', v_movement);
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

CREATE OR REPLACE FUNCTION better_supabase.create_deal (
  tenant   uuid,
  attrs    jsonb,
  contacts jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_deal uuid;
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."deals";
  v_company_type text := coalesce(create_deal.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_deal.attrs -> 'company' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_deal.tenant, 'deals.write'), false)) then
    raise exception 'not allowed to change deals' using errcode = '42501', hint = 'DEAL_FORBIDDEN';
  end if;
  if nullif(trim(create_deal.attrs ->> 'name'), '') is null or (create_deal.attrs ->> 'closeOn') is null then
    raise exception 'a deal needs a name and a close date' using errcode = '23502', hint = 'DEAL_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_deal.tenant, create_deal.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id",
      "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period",
      "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind",
      "flags", "source", "note", "created_by")
    values (create_deal.tenant, v_seq, v_identifier, trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion', create_deal.attrs ->> 'priority', create_deal.attrs ->> 'product', (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0), coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')), coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid, (create_deal.attrs ->> 'stageId')::uuid, (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast', (create_deal.attrs ->> 'closeOn')::date, create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz, create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source', create_deal.attrs ->> 'note', auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a deal field has an invalid value' using errcode = '22023', hint = 'DEAL_ATTRS_INVALID';
  end;
  v_deal := v_row."id";
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
  if create_deal.contacts is not null then
    perform "better_supabase"."set_deal_contacts"(v_deal, create_deal.contacts);
  end if;
  perform "better_supabase".emit_event('deal.created', jsonb_build_object('organizationId', create_deal.tenant, 'dealId', v_deal, 'subjectType', 'deal', 'subjectId', v_deal::text, 'name', v_row."name"), 'deals/' || v_deal::text, (create_deal.tenant::text)::text, null, 'better-supabase/deals');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_deal;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = v_deal);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_invoice (
  tenant uuid,
  attrs  jsonb,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_company_type text := coalesce(create_invoice.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_invoice.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_invoice.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_invoice.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_invoice.tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if nullif(trim(create_invoice.attrs ->> 'title'), '') is null then
    raise exception 'an invoice needs a title' using errcode = '23502', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_CONTACT_FORBIDDEN';
  end if;
  begin
    insert into "better_supabase"."invoices" ("tenant_id", "title", "company_type", "company_id", "contact_type", "contact_id", "currency",
      "terms_days", "note", "origin_type", "origin_id", "deposit_bps", "created_by")
    values (create_invoice.tenant, trim(create_invoice.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      upper(coalesce(create_invoice.attrs ->> 'currency', 'EUR')), coalesce((create_invoice.attrs ->> 'termsDays')::integer, 30),
      create_invoice.attrs ->> 'note', create_invoice.attrs -> 'origin' ->> 'type', create_invoice.attrs -> 'origin' ->> 'id',
      (create_invoice.attrs ->> 'depositBps')::integer, auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation then
    raise exception 'an invoice field has an invalid value' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end;
  if create_invoice.lines is not null then
    perform "better_supabase"."set_invoice_lines"(v_row."id", create_invoice.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'invoice', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'invoice' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('invoice.created', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'balance', (x."total" - x."credited_total" - x."paid_total")::text,
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference') order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_quote (
  tenant uuid,
  attrs  jsonb,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'quote', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'quote' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('quote.created', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_share_link (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  role         text,
  version_id   uuid                     DEFAULT NULL::uuid,
  expires_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_uses     integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_subject_ok boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_share_link.tenant, 'share_links.create'), false)) then
    raise exception 'not allowed to share' using errcode = '42501', hint = 'SHARE_FORBIDDEN';
  end if;
  if create_share_link.expires_at is not null and create_share_link.expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023', hint = 'SHARE_EXPIRY_INVALID';
  end if;
  if create_share_link.max_uses is not null and create_share_link.max_uses < 1 then
    raise exception 'max_uses must be at least 1' using errcode = '22023', hint = 'SHARE_MAX_USES_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    v_subject_ok := case create_share_link.subject_type
    when 'ai-chat' then exists (select 1 from "better_supabase".ai_chats s where s.id::text = create_share_link.subject_id and s.organization_id::text = create_share_link.tenant::text and s.owner_id = auth.uid())
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'calendar' then exists (select 1 from "better_supabase"."calendars" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'booking_service' then exists (select 1 from "better_supabase"."booking_services" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    else case create_share_link.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'customers.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    else null
  end
  end;
    if v_subject_ok is null then
      raise exception 'this subject type can''t be shared' using errcode = '22023', hint = 'SHARE_SUBJECT_UNKNOWN';
    end if;
    if not v_subject_ok then
      raise exception 'the subject does not exist in this organization' using errcode = 'P0002', hint = 'SHARE_SUBJECT_NOT_FOUND';
    end if;
  end if;
  if create_share_link.version_id is not null then
    declare
      v_version jsonb := "better_supabase"."get_version"(create_share_link.version_id);
    begin
      if v_version ->> 'subjectType' is distinct from create_share_link.subject_type
        or v_version ->> 'subjectId' is distinct from create_share_link.subject_id then
        raise exception 'the version belongs to another subject' using errcode = '22023', hint = 'SHARE_VERSION_INVALID';
      end if;
    end;
  end if;
  insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "role", "expires_at", "max_uses", "created_by", "version_id")
  values (create_share_link.tenant, create_share_link.subject_type, create_share_link.subject_id, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), coalesce(create_share_link.role, 'view'), create_share_link.expires_at, create_share_link.max_uses, auth.uid(), create_share_link.version_id)
  returning "id" into v_id;
  perform "better_supabase".emit_event('share_link.created', jsonb_build_object('organizationId', create_share_link.tenant, 'id', v_id, 'subjectType', create_share_link.subject_type, 'subjectId', create_share_link.subject_id), 'share-links/' || v_id::text, (create_share_link.tenant)::text, null, 'better-supabase/share-links');
  return jsonb_build_object('id', v_id, 'token', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.credit_invoice (
  invoice uuid,
  lines   jsonb,
  note    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_original "better_supabase"."invoices";
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_original from "better_supabase"."invoices" x where x."id" = credit_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false));
  if v_original."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_original."kind" <> 'invoice' or v_original."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice is credited' using errcode = '55000', hint = 'INVOICE_NOT_CREDITABLE';
  end if;
  insert into "better_supabase"."invoices" ("tenant_id", "kind", "original_id", "title", "company_type", "company_id", "contact_type", "contact_id",
    "currency", "terms_days", "note", "created_by")
  values (v_original."tenant_id", 'credit_note', v_original."id", 'Credit for ' || coalesce(v_original."identifier", v_original."title"),
    v_original."company_type", v_original."company_id", v_original."contact_type", v_original."contact_id",
    v_original."currency", 0, nullif(trim(credit_invoice.note), ''), auth.uid())
  returning * into v_row;
  if credit_invoice.lines is null then
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select x."tenant_id", v_row."id", x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."position"
    from "better_supabase"."invoice_lines" x where x."parent_id" = v_original."id";
  else
    perform "better_supabase"."set_invoice_lines"(v_row."id", credit_invoice.lines);
  end if;
  perform "better_supabase".emit_event('invoice.created', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'balance', (x."total" - x."credited_total" - x."paid_total")::text,
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference') order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
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
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.comments', '"better_supabase"."comments"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.onboarding_progress', '"better_supabase"."onboarding_progress"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.conversation_participants', '"better_supabase"."conversation_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_reads', '"better_supabase"."conversation_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_mentions', '"better_supabase"."inbox_mentions"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comments', '"better_supabase"."comments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.onboarding_progress', '"better_supabase"."onboarding_progress"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_messages', '"better_supabase"."inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_mentions', '"better_supabase"."inbox_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.collections', '"better_supabase"."collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', false, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.jobs', '"better_supabase"."jobs"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true)
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

CREATE OR REPLACE FUNCTION better_supabase.delete_product (
  product uuid
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
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = delete_product.product;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) in (select v."id" from "better_supabase"."product_variants" v where v."product_id" = delete_product.product)) then
    raise exception 'the stock ledger has movements for this record; archive it instead' using errcode = '23503', hint = 'CATALOG_PRODUCT_IN_USE';
  end if;
  delete from "better_supabase"."products" x where x."id" = delete_product.product;
  perform "better_supabase".emit_event('product.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_product.product), 'products/' || delete_product.product::text, (v_tenant)::text, null, 'better-supabase/catalog');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_variant (
  variant uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_product uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."product_id" into v_tenant, v_product from "better_supabase"."product_variants" x where x."id" = delete_variant.variant;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) in (delete_variant.variant)) then
    raise exception 'the stock ledger has movements for this record; archive it instead' using errcode = '23503', hint = 'CATALOG_VARIANT_IN_USE';
  end if;
  delete from "better_supabase"."product_variants" x where x."id" = delete_variant.variant;
  perform "better_supabase".emit_event('variant.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_variant.variant, 'productId', v_product), 'variants/' || delete_variant.variant::text, (v_tenant)::text, null, 'better-supabase/catalog');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_access (
  document_id uuid,
  write       boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = document_access.document_id;
  if not found then
    return false;
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return true;
  end if;
  if document_access.write then
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.employee_from_application (
  application uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_application "better_supabase"."applications";
  v_job "better_supabase"."jobs";
  v_existing "better_supabase"."employees";
begin
  select * into v_application from "better_supabase"."applications" x where x."id" = employee_from_application.application;
  if v_application."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_application."tenant_id", 'employees.write'), false)) then
    raise exception 'no such application you can turn into an employee' using errcode = 'P0002', hint = 'EMPLOYEE_ORIGIN_NOT_FOUND';
  end if;
  select * into v_existing from "better_supabase"."employees" x
  where x."tenant_id" = v_application."tenant_id" and x."origin_type" = 'application' and x."origin_id" = v_application."id"::text;
  if v_existing."id" is not null then
    return to_jsonb(v_existing);
  end if;
  if v_application."state" <> 'hired' then
    raise exception 'only a hired application becomes an employee' using errcode = '55000', hint = 'EMPLOYEE_APPLICATION_NOT_HIRED';
  end if;
  select * into v_job from "better_supabase"."jobs" x where x."id" = v_application."job_id";
  return "better_supabase"."create_employee"(v_application."tenant_id", jsonb_strip_nulls(jsonb_build_object(
      'name', (case v_application."candidate_type"
      when 'comment' then (select s."body"::text from "better_supabase"."comments" s where s."id" = (v_application."candidate_id")::uuid)
      when 'company' then (select s."name"::text from "better_supabase"."companies" s where s."id" = (v_application."candidate_id")::uuid)
      when 'person' then (select s."name"::text from "better_supabase"."people" s where s."id" = (v_application."candidate_id")::uuid)
      when 'deal' then (select s."name"::text from "better_supabase"."deals" s where s."id" = (v_application."candidate_id")::uuid)
      when 'engagement' then (select s."title"::text from "better_supabase"."engagements" s where s."id" = (v_application."candidate_id")::uuid)
      when 'work_item' then (select s."title"::text from "better_supabase"."work_items" s where s."id" = (v_application."candidate_id")::uuid)
      when 'employee' then (select s."name"::text from "better_supabase"."employees" s where s."id" = (v_application."candidate_id")::uuid)
      when 'ledger_account' then (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product' then (select s."title"::text from "better_supabase"."products" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product_variant' then (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (v_application."candidate_id")::uuid)
      when 'calendar_event' then (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (v_application."candidate_id")::uuid)
      when 'document' then (select s."name"::text from "better_supabase"."documents" s where s."id" = (v_application."candidate_id")::uuid)
      when 'customer' then (select s."name"::text from "public"."customers" s where s."id" = (v_application."candidate_id")::uuid)
      when 'drive_node' then (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (v_application."candidate_id")::uuid)
      when 'project' then (select s."name"::text from "public"."projects" s where s."id" = (v_application."candidate_id")::uuid)
      when 'task' then (select s."title"::text from "public"."tasks" s where s."id" = (v_application."candidate_id")::uuid)
      else null::text
    end),
      'jobTitle', v_job."title",
      'teamId', v_job."team_id",
      'employmentType', case when v_job."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[]) then v_job."employment_type" end,
      'status', 'preboarding'))
    || coalesce(employee_from_application.attrs, '{}'::jsonb)
    || jsonb_build_object('origin', jsonb_build_object('type', 'application', 'id', v_application."id"::text)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expire_ledger_holds (
  max_rows integer DEFAULT 500
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_holds"%rowtype;
  v_count integer := 0;
begin
  for v_id in
    select x."id" from "better_supabase"."ledger_holds" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit least(greatest(coalesce(expire_ledger_holds.max_rows, 500), 1), 5000)
    for update skip locked
  loop
    v_row := "better_supabase"."ledger_unhold"(v_id, 'expired');
    perform "better_supabase".emit_event('ledger_hold.released', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'transactionId', v_row."transaction_id"), 'ledger-holds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_approval (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = get_approval.request_id;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_req."requested_by" = auth.uid() or "better_supabase"."approval_eligible"(v_req."id")
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (not v_req."subject_type" in ('ai_tool_approval') and (v_req."subject_type" in ('access_request', 'timesheet') or case v_req."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    else false
  end)))) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'createdAt', v_req."created_at") || jsonb_build_object(
    'canDecide', "better_supabase"."approval_eligible"(v_req."id"),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'step', x."step", 'approver', x."approver", 'decision', x."decision", 'delegateTo', x."delegate_to", 'comment', x."comment", 'createdAt', x."created_at") order by x."created_at", x."id")
      from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id"
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_document_version (
  document_id uuid,
  version_id  uuid
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_state text;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = get_document_version.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select x."content" ->> 'state' into v_state from "better_supabase"."versions" x
  where x."id" = get_document_version.version_id
    and x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text;
  if v_state is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'DOCUMENT_VERSION_NOT_FOUND';
  end if;
  return v_state;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ledger_transaction (
  transaction_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = get_ledger_transaction.transaction_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_row."id" and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
  )) then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invoice_from_quote (
  quote       uuid,
  deposit_bps integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_quote "better_supabase"."quotes";
  v_row "better_supabase"."invoices";
  v_lines jsonb;
begin
  select * into v_quote from "better_supabase"."quotes" x where x."id" = invoice_from_quote.quote;
  if v_quote."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_quote."tenant_id", 'invoices.write'), false)) then
    raise exception 'no such quote you can invoice' using errcode = 'P0002', hint = 'INVOICE_ORIGIN_NOT_FOUND';
  end if;
  if v_quote."status" <> 'accepted' then
    raise exception 'only an accepted quote is invoiced' using errcode = '55000', hint = 'INVOICE_QUOTE_NOT_ACCEPTED';
  end if;
  if invoice_from_quote.deposit_bps is not null and (invoice_from_quote.deposit_bps <= 0 or invoice_from_quote.deposit_bps >= 10000) then
    raise exception 'a deposit is between 0 and 100 percent' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_bps is null then
    select * into v_row from "better_supabase"."invoices" x
    where x."origin_type" = 'quote' and x."origin_id" = v_quote."id"::text
      and x."deposit_bps" is null and x."status" <> 'void' and x."kind" = 'invoice'
    limit 1;
    if v_row."id" is not null then
      return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference') order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('description', x."description", 'quantity', x."quantity", 'unitAmount', x."unit_amount"::text,
        'discountBps', x."discount_bps", 'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code",
        'product', case when x."product_type" is null then null else jsonb_build_object('type', x."product_type", 'id', x."product_id") end
      ) order by x."position"), '[]'::jsonb) into v_lines
    from "better_supabase"."quote_lines" x where x."parent_id" = v_quote."id";
    select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', 'Deposit ' || d."identifier", 'quantity', 1, 'unitAmount', (-d."subtotal")::text,
        'taxRateBps', case when d."subtotal" = 0 then 0 else round(d."tax_total" * 10000.0 / d."subtotal")::integer end)), '[]'::jsonb)
      into v_lines
    from "better_supabase"."invoices" d
    where d."origin_type" = 'quote' and d."origin_id" = v_quote."id"::text and d."deposit_bps" is not null and d."status" not in ('draft', 'void');
  else
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit ' || (invoice_from_quote.deposit_bps / 100.0)::text || '% of ' || v_quote."identifier",
      'quantity', 1,
      'unitAmount', round(v_quote."subtotal"::numeric * invoice_from_quote.deposit_bps / 10000)::bigint::text,
      'taxRateBps', case when v_quote."subtotal" = 0 then 0 else round(v_quote."tax_total" * 10000.0 / v_quote."subtotal")::integer end));
  end if;
  v_row := null;
  return "better_supabase"."create_invoice"(v_quote."tenant_id", jsonb_build_object(
    'title', v_quote."title", 'currency', v_quote."currency", 'depositBps', invoice_from_quote.deposit_bps,
    'company', case when v_quote."company_id" is null then null else jsonb_build_object('type', v_quote."company_type", 'id', v_quote."company_id") end,
    'contact', case when v_quote."contact_id" is null then null else jsonb_build_object('type', v_quote."contact_type", 'id', v_quote."contact_id") end,
    'origin', jsonb_build_object('type', 'quote', 'id', v_quote."id"::text)), v_lines);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_invoice (
  invoice   uuid,
  issued_on date
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'the invoice was already issued' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  if not exists (select 1 from "better_supabase"."invoice_lines" x where x."parent_id" = v_row."id") then
    raise exception 'an invoice needs a line before it is issued' using errcode = '23514', hint = 'INVOICE_EMPTY';
  end if;
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
    if v_row."total" > (v_original."total" - v_original."credited_total" - v_original."paid_total") then
      raise exception 'a credit note can''t exceed what is still owed' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':credit_note', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'CN-' || v_seq::text;
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':invoice', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'INV-' || v_seq::text;
  end if;
  update "better_supabase"."invoices" x set "status" = 'issued', "number" = v_seq, "identifier" = v_identifier,
    "issued_on" = coalesce(issue_invoice.issued_on, current_date),
    "due_on" = coalesce(issue_invoice.issued_on, current_date) + x."terms_days",
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
      when (x."total" - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_original."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_original;
    perform "better_supabase".emit_event('invoice.credited', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'creditNoteId', v_row."id", 'amount', v_row."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    if v_original."status" = 'paid' then
      perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'total', v_original."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference') order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_account_entries (
  account_id uuid,
  before     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size  integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_rows jsonb;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = ledger_account_entries.account_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.read'), false) or v_account."owner_id" = auth.uid() or (v_account."read_permission" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", v_account."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit",
        'transactionId', r."id", 'kind', r."kind", 'referenceType', r."reference_type", 'referenceId', r."reference_id",
        'memo', r."memo", 'reverses', r."reverses", 'metadata', r."metadata", 'effectiveAt', r."effective_at", 'createdAt', y."created_at") as item,
      y."created_at" as created, y."id" as id
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where y."account_id" = v_account."id"
      and (ledger_account_entries.before is null or y."created_at" < ledger_account_entries.before)
    order by y."created_at" desc, y."id" desc
    limit least(greatest(coalesce(ledger_account_entries.page_size, 50), 1), 500)
  ) z;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_account_for (
  tenant          uuid,
  kind            text,
  code            text,
  name            text,
  unit            text,
  scale           smallint DEFAULT 0,
  holder_type     text     DEFAULT NULL::text,
  holder_id       text     DEFAULT NULL::text,
  owner_id        uuid     DEFAULT NULL::uuid,
  allow_negative  boolean  DEFAULT false,
  read_permission text     DEFAULT NULL::text,
  managed_by      text     DEFAULT NULL::text,
  metadata        jsonb    DEFAULT NULL::jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."ledger_accounts" x
    where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  if found then
    return v_id;
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "managed_by", "metadata")
  values (ledger_account_for.tenant, ledger_account_for.kind, ledger_account_for.code, ledger_account_for.name, ledger_account_for.unit,
    coalesce(ledger_account_for.scale, 0), ledger_account_for.holder_type, ledger_account_for.holder_id, ledger_account_for.owner_id,
    coalesce(ledger_account_for.allow_negative, false), ledger_account_for.read_permission, ledger_account_for.managed_by,
    coalesce(ledger_account_for.metadata, '{}'::jsonb))
  on conflict ("tenant_id", "code") do nothing
  returning "id" into v_id;
  if v_id is null then
    select x."id" into v_id from "better_supabase"."ledger_accounts" x
      where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_append_only()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  raise exception 'ledger entries and transactions can''t be changed or deleted; post a reversal' using errcode = '55000', hint = 'LEDGER_APPEND_ONLY';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_apply_entry()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_available bigint;
begin
  insert into "better_supabase"."ledger_balances" as x ("account_id", "tenant_id", "balance")
  values (new."account_id", new."tenant_id", new."amount")
  on conflict ("account_id") do update set "balance" = x."balance" + excluded."balance", "updated_at" = now()
  returning x."balance" - x."held" into v_available;
  if new."amount" < 0 and v_available < 0 and not exists (
    select 1 from "better_supabase"."ledger_accounts" y where y."id" = new."account_id" and y."allow_negative"
  ) then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_check_balanced()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if exists (
    select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = new."transaction_id"
    group by y."unit" having sum(y."amount") <> 0
  ) then
    raise exception 'the entries of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_post (
  tenant          uuid,
  kind            text,
  lines           jsonb,
  reference_type  text                     DEFAULT NULL::text,
  reference_id    text                     DEFAULT NULL::text,
  memo            text                     DEFAULT NULL::text,
  idempotency_key text                     DEFAULT NULL::text,
  effective_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  metadata        jsonb                    DEFAULT NULL::jsonb,
  reverses        uuid                     DEFAULT NULL::uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if ledger_post.idempotency_key is not null then
    select x."id" into v_id from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = ledger_post.tenant and x."idempotency_key" = ledger_post.idempotency_key;
    if found then
      return v_id;
    end if;
  end if;
  if ledger_post.kind is null or ledger_post.kind !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$' then
    raise exception 'kind must be lowercase words joined by dots, such as credit.grant' using errcode = '22023', hint = 'LEDGER_KIND_INVALID';
  end if;
  if jsonb_typeof(ledger_post.lines) is distinct from 'array' or jsonb_array_length(ledger_post.lines) < 2 then
    raise exception 'a transaction needs at least two lines' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    where jsonb_typeof(l.value) is distinct from 'object'
      or coalesce(l.value ->> 'account', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(l.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
      or (l.value ->> 'amount')::bigint = 0
  ) then
    raise exception 'every line needs an account id and a non-zero integer amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    left join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
      and x."tenant_id" = ledger_post.tenant and x."closed_at" is null
    where x."id" is null
  ) then
    raise exception 'an account of the transaction doesn''t exist here or is closed' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
    group by x."unit" having sum((l.value ->> 'amount')::bigint) <> 0
  ) then
    raise exception 'the lines of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_ledger_transaction_post"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using ledger_post.tenant, ledger_post.kind, ledger_post.lines;
    end if;
  end;
  insert into "better_supabase"."ledger_transactions" ("tenant_id", "kind", "reference_type", "reference_id", "memo", "idempotency_key", "reverses", "metadata", "effective_at", "actor_id")
  values (ledger_post.tenant, ledger_post.kind, ledger_post.reference_type, ledger_post.reference_id, nullif(trim(ledger_post.memo), ''),
    ledger_post.idempotency_key, ledger_post.reverses, coalesce(ledger_post.metadata, '{}'::jsonb), coalesce(ledger_post.effective_at, now()), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."ledger_entries" ("tenant_id", "transaction_id", "account_id", "amount", "unit")
  select ledger_post.tenant, v_row."id", x."id", (l.value ->> 'amount')::bigint, x."unit"
  from jsonb_array_elements(ledger_post.lines) with ordinality as l(value, n)
  join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
  order by l.n;
  perform "better_supabase".emit_event('ledger_transaction.posted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id")), 'ledger-transactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_ledger_transaction_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row."id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_read_grants()
  RETURNS TABLE (
    tenant     uuid,
    permission text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  select p.tenant, p.permission from (
    select distinct x."tenant_id" as tenant, x."read_permission" as permission
    from "better_supabase"."ledger_accounts" x
    where x."read_permission" is not null and x."tenant_id" in (select better_supabase.member_organization_ids())
  ) p
  where coalesce(better_supabase.can('tenant', p.tenant, p.permission), false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ledger_unhold (
  hold_id uuid,
  status  text
)
  RETURNS better_supabase.ledger_holds
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = ledger_unhold.hold_id for update;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'this hold is no longer active' using errcode = '55000', hint = 'LEDGER_HOLD_CLOSED';
  end if;
  update "better_supabase"."ledger_balances" x set "held" = x."held" - v_row."amount", "updated_at" = now()
    where x."account_id" = v_row."account_id";
  update "better_supabase"."ledger_holds" x set "status" = ledger_unhold.status, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.link (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text,
  data        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_id uuid;
  v_created boolean := false;
  v_previous jsonb;
  v_replaced jsonb;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', link.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to link records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;
  if link.data is not null and jsonb_typeof(link.data) <> 'object' then
    raise exception 'data must be an object' using errcode = '22023', hint = 'RELATION_INVALID';
  end if;
  if link.source_type = link.target_type and link.source_id = link.target_id then
    raise exception 'a record can''t link to itself' using errcode = '22023', hint = 'RELATION_SELF';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = link.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := link.target_type; v_source_id := link.target_id;
    v_target_type := link.source_type; v_target_id := link.source_id;
  else
    v_source_type := link.source_type; v_source_id := link.source_id;
    v_target_type := link.target_type; v_target_id := link.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if not (case link.source_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    else false
  end)
     or not (case link.target_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    else false
  end) then
    raise exception 'not allowed to link these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_relation_link"(uuid, text, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text, $6::text)', v_hook::oid::regproc)
        using link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id;
    end if;
  end;
  if v_acyclic or v_single then
    perform pg_advisory_xact_lock(hashtext(link.tenant::text || ':relations:' || v_kind));
  end if;
  select "id", "data" into v_id, v_previous from "better_supabase"."relations"
    where "tenant_id" = link.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id;
  if v_id is null then
    if v_acyclic and exists (
      with recursive reach(t, i, depth) as (
        select v_target_type, v_target_id, 0
        union
        select r."target_type", r."target_id", reach.depth + 1
        from "better_supabase"."relations" r join reach
          on r."source_type" = reach.t and r."source_id" = reach.i
        where r."tenant_id" = link.tenant and r."kind" = v_kind and reach.depth < 1000
      )
      select 1 from reach where t = v_source_type and i = v_source_id
    ) then
      raise exception 'this link would create a cycle' using errcode = '23514', hint = 'RELATION_CYCLE';
    end if;
    if v_single then
      delete from "better_supabase"."relations"
        where "tenant_id" = link.tenant and "kind" = v_kind
          and "source_type" = v_source_type and "source_id" = v_source_id
        returning * into v_old;
      if v_old."id" is not null then
        v_replaced := jsonb_build_object('targetType', v_old."target_type", 'targetId', v_old."target_id", 'data', v_old."data");
        perform "better_supabase".emit_event('subject.unlinked', jsonb_build_object('organizationId', link.tenant, 'id', v_old."id", 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_old."target_type", 'targetId', v_old."target_id"), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
      end if;
    end if;
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "data", "created_by")
    values (link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id, coalesce(link.data, '{}'::jsonb), auth.uid())
    returning "id" into v_id;
    v_created := true;
    perform "better_supabase".emit_event('subject.linked', jsonb_build_object('organizationId', link.tenant, 'id', v_id, 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
  elsif link.data is not null then
    update "better_supabase"."relations" set "data" = link.data where "id" = v_id;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_relation_link"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object(
    'id', v_id, 'kind', v_kind, 'created', v_created,
    'sourceType', v_source_type, 'sourceId', v_source_id,
    'targetType', v_target_type, 'targetId', v_target_id,
    'previousData', case when v_created then null else v_previous end,
    'replaced', v_replaced);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50,
  sources      text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
  v_table text;
begin
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,document,customer,drive_node,application,project,task}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
      when 'comment' then 'better_supabase.comments'
      when 'company' then 'better_supabase.companies'
      when 'person' then 'better_supabase.people'
      when 'deal' then 'better_supabase.deals'
      when 'engagement' then 'better_supabase.engagements'
      when 'work_item' then 'better_supabase.work_items'
      when 'employee' then 'better_supabase.employees'
      when 'ledger_account' then 'better_supabase.ledger_accounts'
      when 'product' then 'better_supabase.products'
      when 'product_variant' then 'better_supabase.product_variants'
      when 'calendar_event' then 'better_supabase.calendar_events'
      when 'document' then 'better_supabase.documents'
      when 'customer' then 'public.customers'
      when 'drive_node' then 'better_supabase.drive_nodes'
      when 'application' then 'better_supabase.applications'
      when 'project' then 'public.projects'
      when 'task' then 'public.tasks'
    end;
  end if;
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', l."id"::text, 'organization_id', l."organization_id", 'event_id', null::text, 'type', coalesce(l."event_type", 'audit.' || l."op"), 'actor_id', l."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', l."summary", 'data', jsonb_strip_nulls(jsonb_build_object('op', l."op", 'changed', to_jsonb(l."changed"), 'table', l."table_name")), 'occurred_at', l."occurred_at", 'source', 'audit') as entry,
      l."occurred_at" as at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where v_table is not null
      and (list_activity.sources is null or 'audit' = any (list_activity.sources))
      and l."table_name" = v_table
      and l."record_id" = list_activity.subject_id
      and l."organization_id" = list_activity.tenant
      and (list_activity.before is null or l."occurred_at" < list_activity.before)
    order by l."occurred_at" desc, l."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', r."id"::text, 'organization_id', r."tenant_id", 'event_id', null::text, 'type', 'run.' || r."status", 'actor_id', r."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('runId', r."id", 'definition', r."definition", 'engine', r."engine", 'status', r."status", 'mode', r."mode", 'error', r."error"::text, 'completedAt', r."completed_at")), 'occurred_at', r."created_at", 'source', 'run') as entry,
      r."created_at" as at, r."id"::text as id
    from "better_supabase"."workflow_runs" r
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,document,customer,drive_node,application,project,task}'::text[])
      and (list_activity.sources is null or 'run' = any (list_activity.sources))
      and r."tenant_id" = list_activity.tenant
      and r."subject_type" = list_activity.subject_type
      and r."subject_id" = list_activity.subject_id
      and (list_activity.before is null or r."created_at" < list_activity.before)
    order by r."created_at" desc, r."id" desc
    limit v_limit)
    union all
    (select d.entry, d.at, d.id
    from "better_supabase"."activity_subject_deliveries"(list_activity.tenant, list_activity.subject_type, list_activity.subject_id, list_activity.before, v_limit) d
    where list_activity.subject_id is not null
      and (list_activity.sources is null or 'delivery' = any (list_activity.sources)))
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_approvals (
  tenant       uuid,
  status       text                     DEFAULT 'pending'::text,
  assigned     boolean                  DEFAULT false,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
  v_read boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_approvals.tenant, 'approvals.read'), false);
begin
  select coalesce(jsonb_agg(t.j order by t.at desc, t.id), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'action', x."action", 'status', x."status", 'step', x."step", 'steps', x."policy" -> 'steps', 'requestedBy', x."requested_by", 'reason', x."reason", 'payload', x."payload", 'expiresAt', x."expires_at", 'decidedAt', x."decided_at", 'createdAt', x."created_at") as j, x."created_at" as at, x."id" as id
    from "better_supabase"."approval_requests" x
    where x."tenant_id" = list_approvals.tenant
      and (list_approvals.status is null or x."status" = list_approvals.status)
      and (list_approvals.subject_type is null or x."subject_type" = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x."subject_id" = list_approvals.subject_id)
      and (list_approvals.before is null or x."created_at" < list_approvals.before)
      and case
        when list_approvals.assigned then "better_supabase"."approval_eligible"(x."id")
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (not x."subject_type" in ('ai_tool_approval') and (x."subject_type" in ('access_request', 'timesheet') or case x."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)))) or "better_supabase"."approval_eligible"(x."id")
      end
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_approvals.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_document_versions (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_versions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."number" desc), '[]'::jsonb)
    from "better_supabase"."versions" x
    where x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ledger_accounts (
  tenant      uuid,
  kind        text    DEFAULT NULL::text,
  holder_type text    DEFAULT NULL::text,
  holder_id   text    DEFAULT NULL::text,
  page_size   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(z.item order by z.code), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'code', x."code", 'name', x."name", 'unit', x."unit", 'scale', x."scale", 'holderType', x."holder_type", 'holderId', x."holder_id", 'ownerId', x."owner_id", 'allowNegative', x."allow_negative", 'readPermission', x."read_permission", 'managedBy', x."managed_by", 'metadata', x."metadata", 'closedAt', x."closed_at", 'createdAt', x."created_at", 'balance', coalesce(y."balance", 0)::text, 'held', coalesce(y."held", 0)::text, 'available', coalesce(y."balance" - y."held", 0)::text) as item, x."code" as code
    from "better_supabase"."ledger_accounts" x
    left join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
    where (list_ledger_accounts.tenant is null or x."tenant_id" = list_ledger_accounts.tenant)
      and (list_ledger_accounts.kind is null or x."kind" = list_ledger_accounts.kind)
      and (list_ledger_accounts.holder_type is null or x."holder_type" = list_ledger_accounts.holder_type)
      and (list_ledger_accounts.holder_id is null or x."holder_id" = list_ledger_accounts.holder_id)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
    order by x."code"
    limit least(greatest(coalesce(list_ledger_accounts.page_size, 100), 1), 1000)
  ) z
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_engagement (
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
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'engagements.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner,
    (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz,
    (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid())
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at",
    "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/engagements');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_time (
  tenant        uuid,
  started_at    timestamp with time zone,
  ended_at      timestamp with time zone,
  subject_type  text                     DEFAULT NULL::text,
  subject_id    text                     DEFAULT NULL::text,
  billable      boolean                  DEFAULT false,
  rate          bigint                   DEFAULT NULL::bigint,
  rate_currency text                     DEFAULT NULL::text,
  note          text                     DEFAULT NULL::text,
  user_id       uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "public"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case log_time.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (log_time.rate is null) <> (log_time.rate_currency is null) then
    raise exception 'name both rate and rate_currency, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if log_time.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."rate_currency" := log_time.rate_currency;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_stock (
  tenant         uuid,
  variant        uuid,
  location       uuid,
  quantity       integer,
  reason         text,
  reference_type text    DEFAULT NULL::text,
  reference_id   text    DEFAULT NULL::text,
  note           text    DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_stock uuid;
  v_counter uuid;
  v_id uuid;
  v_on_hand integer;
  v_after integer;
  v_point integer;
begin
  if move_stock.quantity is null or move_stock.quantity = 0 then
    raise exception 'the quantity must not be zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  if move_stock.reason is null or move_stock.reason not in ('adjustment', 'damage', 'loss', 'count', 'receipt', 'sale', 'return', 'transfer_out', 'transfer_in') then
    raise exception 'unknown stock movement reason' using errcode = '22023', hint = 'INVENTORY_REASON_INVALID';
  end if;
  v_stock := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock', 'stock:' || move_stock.variant::text || ':' || move_stock.location::text,
    'Stock', 'item', 0::smallint, 'product-variants', move_stock.variant::text, null, true, 'inventory.read', 'inventory',
    jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location));
  v_counter := "better_supabase"."ledger_account_for"(move_stock.tenant, 'stock_counter', case move_stock.reason when 'adjustment' then 'stock:adjustments' when 'damage' then 'stock:adjustments' when 'loss' then 'stock:adjustments' when 'count' then 'stock:adjustments' when 'receipt' then 'stock:suppliers' when 'sale' then 'stock:customers' when 'return' then 'stock:customers' when 'transfer_out' then 'stock:transit' when 'transfer_in' then 'stock:transit' end,
    case move_stock.reason when 'adjustment' then 'Adjustments' when 'damage' then 'Adjustments' when 'loss' then 'Adjustments' when 'count' then 'Adjustments' when 'receipt' then 'Suppliers' when 'sale' then 'Customers' when 'return' then 'Customers' when 'transfer_out' then 'In transit' when 'transfer_in' then 'In transit' end, 'item', 0::smallint, null, null, null, true, 'inventory.read', 'inventory', null);
  v_id := "better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason,
    jsonb_build_array(
      jsonb_build_object('account', v_stock, 'amount', move_stock.quantity),
      jsonb_build_object('account', v_counter, 'amount', -move_stock.quantity)),
    move_stock.reference_type, move_stock.reference_id, move_stock.note, null, null,
    jsonb_build_object('variantId', move_stock.variant, 'locationId', move_stock.location, 'reason', move_stock.reason));
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "on_hand")
  values (move_stock.tenant, move_stock.variant, move_stock.location, move_stock.quantity)
  on conflict ("variant_id", "location_id") do update
    set "on_hand" = x."on_hand" + excluded."on_hand", "updated_at" = now()
  returning x."on_hand", x."available", x."reorder_point" into v_on_hand, v_after, v_point;
  if move_stock.quantity < 0
    and (v_on_hand < 0 or (v_after < 0 and move_stock.reason in ('sale', 'transfer_out')))
    and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = move_stock.variant and cv."track_inventory" and not cv."allow_backorder") then
    raise exception 'not enough stock at this location' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  if v_point is not null and (v_after - move_stock.quantity) > v_point and v_after <= v_point then
    perform "better_supabase".emit_event('stock.reorder_point_reached', jsonb_build_object('organizationId', move_stock.tenant, 'subjectType', 'product_variant', 'subjectId', move_stock.variant::text, 'variantId', move_stock.variant, 'locationId', move_stock.location, 'available', v_after::text, 'reorderPoint', v_point::text), 'stock-levels/' || move_stock.variant::text || '/' || move_stock.location::text, (move_stock.tenant)::text, null, 'better-supabase/inventory');
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_document (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  name         text DEFAULT 'body'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
  v_write boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d
  where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
  if found and v_doc."tenant_id" <> open_document.tenant then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not found then
    v_doc."tenant_id" := open_document.tenant;
    v_doc."subject_type" := open_document.subject_type;
    v_doc."subject_id" := open_document.subject_id;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end) then
        raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
      end if;
      raise exception 'not allowed to open this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name;
    end if;
  end;
    insert into "better_supabase"."documents" ("tenant_id", "subject_type", "subject_id", "name", "created_by")
    values (open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name, auth.uid())
    on conflict ("subject_type", "subject_id", "name") do nothing
    returning * into v_doc;
    if found then
      perform "better_supabase".emit_event('document.created', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  perform better_supabase.audit_event(
    event_type => 'document.created',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name")
  );
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_doc."id";
    end if;
  end;
    else
      select * into v_doc from "better_supabase"."documents" d
      where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'snapshot', case when v_snapshot."document_id" is null then null else replace(encode(v_snapshot."state", 'base64'), E'\n', '') end,
    'snapshotSeq', coalesce(v_snapshot."seq", 0),
    'updates', "better_supabase"."document_updates_after"(v_doc."id", coalesce(v_snapshot."seq", 0))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_ledger_account (
  tenant          uuid,
  kind            text,
  code            text,
  name            text,
  unit            text,
  scale           smallint DEFAULT 0,
  holder_type     text     DEFAULT NULL::text,
  holder_id       text     DEFAULT NULL::text,
  owner_id        uuid     DEFAULT NULL::uuid,
  allow_negative  boolean  DEFAULT false,
  read_permission text     DEFAULT NULL::text,
  metadata        jsonb    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_ledger_account.tenant, 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x where x."tenant_id" = open_ledger_account.tenant and x."code" = open_ledger_account.code) then
    raise exception 'an account with this code already exists' using errcode = '23505', hint = 'LEDGER_ACCOUNT_CODE_TAKEN';
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "metadata")
  values (open_ledger_account.tenant, open_ledger_account.kind, open_ledger_account.code, open_ledger_account.name, open_ledger_account.unit,
    coalesce(open_ledger_account.scale, 0), open_ledger_account.holder_type, open_ledger_account.holder_id, open_ledger_account.owner_id,
    coalesce(open_ledger_account.allow_negative, false), open_ledger_account.read_permission, coalesce(open_ledger_account.metadata, '{}'::jsonb))
  returning * into v_row;
  perform "better_supabase".emit_event('ledger_account.opened', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id"), 'ledger-accounts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  perform better_supabase.audit_event(
    event_type => 'ledger_account.opened',
    category => 'billing',
    target_type => 'ledger_account',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'opened ledger account ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.place_ledger_hold (
  account_id     uuid,
  amount         bigint,
  reference_type text                     DEFAULT NULL::text,
  reference_id   text                     DEFAULT NULL::text,
  expires_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = place_ledger_hold.account_id;
  if not found or v_account."closed_at" is not null then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_account."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  if place_ledger_hold.amount is null or place_ledger_hold.amount <= 0 then
    raise exception 'a hold needs an amount greater than zero' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  insert into "better_supabase"."ledger_balances" ("account_id", "tenant_id") values (v_account."id", v_account."tenant_id")
    on conflict ("account_id") do nothing;
  select * into v_balance from "better_supabase"."ledger_balances" x where x."account_id" = v_account."id" for update;
  if not v_account."allow_negative" and v_balance."balance" - v_balance."held" < place_ledger_hold.amount then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  update "better_supabase"."ledger_balances" x set "held" = x."held" + place_ledger_hold.amount, "updated_at" = now()
    where x."account_id" = v_account."id";
  insert into "better_supabase"."ledger_holds" ("tenant_id", "account_id", "amount", "reference_type", "reference_id", "expires_at", "created_by")
  values (v_account."tenant_id", v_account."id", place_ledger_hold.amount, place_ledger_hold.reference_type, place_ledger_hold.reference_id, place_ledger_hold.expires_at, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('ledger_hold.placed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'transactionId', v_row."transaction_id"), 'ledger-holds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_ledger_transaction (
  tenant          uuid,
  kind            text,
  lines           jsonb,
  reference_type  text                     DEFAULT NULL::text,
  reference_id    text                     DEFAULT NULL::text,
  memo            text                     DEFAULT NULL::text,
  idempotency_key text                     DEFAULT NULL::text,
  effective_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  metadata        jsonb                    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_ledger_transaction.tenant, 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if jsonb_typeof(post_ledger_transaction.lines) = 'array' and exists (
    select 1 from jsonb_array_elements(post_ledger_transaction.lines) l
    join "better_supabase"."ledger_accounts" x on x."id"::text = l.value ->> 'account'
    where x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_id := "better_supabase"."ledger_post"(post_ledger_transaction.tenant, post_ledger_transaction.kind, post_ledger_transaction.lines,
    post_ledger_transaction.reference_type, post_ledger_transaction.reference_id, post_ledger_transaction.memo,
    post_ledger_transaction.idempotency_key, post_ledger_transaction.effective_at, post_ledger_transaction.metadata);
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pull_document_updates (
  document_id uuid,
  after_seq   bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = pull_document_updates.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  if v_snapshot."document_id" is not null and pull_document_updates.after_seq < v_snapshot."seq" then
    return jsonb_build_object(
      'snapshot', replace(encode(v_snapshot."state", 'base64'), E'\n', ''),
      'snapshotSeq', v_snapshot."seq",
      'updates', "better_supabase"."document_updates_after"(v_doc."id", v_snapshot."seq")
    );
  end if;
  return jsonb_build_object('updates', "better_supabase"."document_updates_after"(v_doc."id", pull_document_updates.after_seq));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.push_document_update (
  document_id uuid,
  payload     text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_bytes bytea;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = push_document_update.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(push_document_update.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_bytes, auth.uid())
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    perform "better_supabase"."enqueue_job"(queue => 'documents.compact', payload => jsonb_build_object('documentId', v_doc."id"), dedupe_key => 'documents.compact:' || v_doc."id"::text, dedupe_running => false);
  end if;
  return v_seq;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reaction_subject_visible (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case reaction_subject_visible.subject_type
    when 'inbox_message' then exists (select 1 from "better_supabase"."inbox_messages" m where m."id"::text = reaction_subject_visible.subject_id and m."tenant_id" = reaction_subject_visible.tenant)
    else case reaction_subject_visible.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."deleted_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    else false
  end
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.receive_purchase_order (
  purchase_order uuid,
  lines          jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
  v_line record;
  v_backordered bigint;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."location_id" as location, x."status" as status,
    x."supplier_type" as supplier_type, x."supplier_id" as supplier_id
  into v_row from "better_supabase"."purchase_orders" x where x."id" = receive_purchase_order.purchase_order for update;
  if not found then
    raise exception 'purchase order not found' using errcode = 'P0002', hint = 'INVENTORY_PURCHASE_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.purchase'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status not in ('ordered', 'partially_received') then
    raise exception 'the purchase order can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_PURCHASE_ORDER_STATUS';
  end if;
  if jsonb_typeof(receive_purchase_order.lines) is distinct from 'array' or jsonb_array_length(receive_purchase_order.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(receive_purchase_order.lines) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        or coalesce(e ->> 'quantity', '') !~ '^[1-9][0-9]{0,8}$'
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(receive_purchase_order.lines) e) <> jsonb_array_length(receive_purchase_order.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a positive whole quantity each' using errcode = '22023', hint = 'INVENTORY_LINES_INVALID';
  end if;
  for v_line in
    select y."id" as id, y."variant_id" as variant, y."quantity_ordered" as ordered,
      y."quantity_received" as received, (e ->> 'quantity')::integer as quantity
    from jsonb_array_elements(receive_purchase_order.lines) e
    left join "better_supabase"."purchase_order_lines" y on y."id" = (e ->> 'lineId')::uuid and y."purchase_order_id" = receive_purchase_order.purchase_order
  loop
    if v_line.id is null then
      raise exception 'a line isn''t on this purchase order' using errcode = 'P0002', hint = 'INVENTORY_LINE_NOT_FOUND';
    end if;
    if v_line.received + v_line.quantity > v_line.ordered then
      raise exception 'a line would receive more than was ordered' using errcode = '22023', hint = 'INVENTORY_OVER_RECEIPT';
    end if;
    update "better_supabase"."purchase_order_lines" y set "quantity_received" = y."quantity_received" + v_line.quantity where y."id" = v_line.id;
    update "better_supabase"."stock_levels" x set "incoming" = greatest(x."incoming" - v_line.quantity, 0), "updated_at" = now()
    where x."variant_id" = v_line.variant and x."location_id" = v_row.location;
    perform "better_supabase"."move_stock"(v_row.tenant, v_line.variant, v_row.location, v_line.quantity, 'receipt', 'purchase_order', receive_purchase_order.purchase_order::text, null);
  end loop;
  select coalesce(sum(y."quantity_ordered" - y."quantity_received"), 0) into v_backordered
  from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = receive_purchase_order.purchase_order;
  v_status := case when v_backordered = 0 then 'received' else 'partially_received' end;
  update "better_supabase"."purchase_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = receive_purchase_order.purchase_order;
  perform "better_supabase".emit_event('purchase_order.received', jsonb_build_object('organizationId', v_row.tenant, 'id', receive_purchase_order.purchase_order, 'locationId', v_row.location, 'status', v_status, 'supplierType', v_row.supplier_type, 'supplierId', v_row.supplier_id), 'purchase-orders/' || receive_purchase_order.purchase_order::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return jsonb_build_object('status', v_status, 'backordered', v_backordered);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.receive_return (
  return_id uuid,
  restock   boolean DEFAULT true,
  location  uuid    DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_return record;
  v_order record;
  v_line record;
  v_units integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."order_id" as order_id, x."status" as status into v_return
  from "better_supabase"."order_returns" x where x."id" = receive_return.return_id for update;
  if not found then
    raise exception 'return not found' using errcode = 'P0002', hint = 'ORDERS_RETURN_NOT_FOUND';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_return.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_return.status = 'received' then
    return false;
  end if;
  if v_return.status <> 'requested' then
    raise exception 'only a requested return can be received' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  for v_line in
    select y."order_line_id" as line, y."quantity" as quantity, l."variant_id" as variant, l."location_id" as location
    from "better_supabase"."order_return_lines" y join "better_supabase"."order_lines" l on l."id" = y."order_line_id"
    where y."return_id" = v_return.id
  loop
    update "better_supabase"."order_lines" x set "quantity_returned" = x."quantity_returned" + v_line.quantity where x."id" = v_line.line;
    if receive_return.restock and v_line.variant is not null and coalesce(receive_return.location, v_line.location) is not null
      and exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = v_line.variant and cv."track_inventory") then
      perform "better_supabase"."move_stock"(v_order.tenant, v_line.variant, coalesce(receive_return.location, v_line.location), v_line.quantity, 'return', 'order_return', receive_return.return_id::text, null);
    end if;
    v_units := v_units + v_line.quantity;
  end loop;
  update "better_supabase"."order_returns" x set "status" = 'received', "received_at" = now() where x."id" = v_return.id;
  perform "better_supabase".emit_event('return.received', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_return.id, 'orderId', v_order.id, 'number', v_order.number, 'quantity', v_units::text), 'orders/' || v_order.id::text, (v_order.tenant)::text, null, 'better-supabase/orders');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.receive_transfer (
  transfer uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = receive_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'in_transit' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  perform "better_supabase"."move_stock"(v_row.tenant, x."variant_id", v_row.to_location, x."quantity", 'transfer_in', 'transfer', receive_transfer.transfer::text, null)
  from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = receive_transfer.transfer;
  update "better_supabase"."stock_transfers" x set "status" = 'received', "received_at" = now() where x."id" = receive_transfer.transfer;
  perform "better_supabase".emit_event('transfer.received', jsonb_build_object('organizationId', v_row.tenant, 'id', receive_transfer.transfer, 'from', v_row.from_location, 'to', v_row.to_location, 'status', 'received'), 'stock-transfers/' || receive_transfer.transfer::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_invoice_payment (
  invoice   uuid,
  amount    bigint,
  currency  text,
  paid_at   timestamp with time zone,
  method    text,
  reference text
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
  select * into v_row from "better_supabase"."invoices" x where x."id" = record_invoice_payment.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false)) for update;
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
  -- A recorded reference is a replay that adds nothing, so it skips the check.
  v_reference := nullif(trim(record_invoice_payment.reference), '');
  if v_reference is not null and exists (
    select 1 from "better_supabase"."ledger_transactions" y
    where y."tenant_id" = v_row."tenant_id" and y."idempotency_key" = 'invoice-payment:' || v_reference
  ) then
    return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference') order by y."effective_at", y."created_at")
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
  v_payment := "better_supabase"."ledger_post"(v_row."tenant_id", case when record_invoice_payment.amount < 0 then 'invoice.refund' else 'invoice.payment' end,
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -record_invoice_payment.amount),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'cash',
      'invoices:cash:' || v_row."currency", 'Invoice payments ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', record_invoice_payment.amount)),
    'invoices', v_row."id"::text, null,
    case when v_reference is not null then 'invoice-payment:' || v_reference end, coalesce(record_invoice_payment.paid_at, now()),
    jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row."id", 'method', record_invoice_payment.method, 'reference', v_reference)));
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.payment_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', v_payment, 'amount', record_invoice_payment.amount::text, 'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
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
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference') order by y."effective_at", y."created_at")
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
  if v_order.status = 'pending_payment' and v_paid >= v_order.total then
    perform "better_supabase"."order_transition"(v_order.id, 'paid');
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
          perform "better_supabase"."move_stock"(v_order.tenant, v_line.variant, v_line.location, -v_line.quantity, 'sale', 'order', v_order.id::text, null);
        exception when sqlstate '23514' then
          update "better_supabase"."order_lines" x set "backordered" = true where x."id" = v_line.id;
        end;
      end;
    end loop;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_order.tenant::text || ':orders:invoice', 0));
  select coalesce(max(x."invoice_sequence"), 0) + 1 into v_seq from "better_supabase"."orders" x where x."tenant_id" = v_order.tenant;
  v_number := v_seq::text;
    update "better_supabase"."orders" x set "invoice_number" = v_number, "invoice_sequence" = v_seq, "invoiced_at" = now()
    where x."id" = v_order.id;
    perform "better_supabase".emit_event('order.paid', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer, 'currency', v_order.currency, 'total', v_order.total::text, 'units', (select coalesce(sum(l."quantity"), 0)::text from "better_supabase"."order_lines" l where l."order_id" = v_order.id), 'invoiceNumber', v_number), 'orders/' || v_order.id::text, (v_order.tenant)::text, 'order.paid:' || v_order.id::text, 'better-supabase/orders');
    v_newly := true;
  end if;
  return jsonb_build_object('orderId', v_order.id, 'status', (select x."status" from "better_supabase"."orders" x where x."id" = v_order.id),
    'paidTotal', v_paid::text, 'newlyPaid', v_newly,
    'invoiceNumber', coalesce(v_number, v_order.invoice_number));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_sla_event (
  subject_type text,
  subject_id   text,
  event        text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text := (case record_sla_event.subject_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (record_sla_event.subject_id)::uuid)
      else null::text
    end);
  v_clock "better_supabase"."sla_clocks";
  v_policy "better_supabase"."sla_policies";
  v_meet text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if pg_trigger_depth() = 0 and not ((auth.role() = 'service_role') or (case record_sla_event.subject_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (record_sla_event.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (record_sla_event.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (record_sla_event.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (record_sla_event.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(record_sla_event.subject_type, record_sla_event.subject_id, 'read'))) then
    raise exception 'not allowed to move clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  case record_sla_event.event
    when 'responded' then v_meet := array['first_response', 'next_response'];
    when 'resolved' then v_meet := array['first_response', 'next_response', 'resolution'];
    when 'paused' then
      update "better_supabase"."sla_clocks" x set "paused_at" = now()
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'resumed' then
      update "better_supabase"."sla_clocks" x set
        "due_at" = x."due_at" + (now() - x."paused_at"),
        "paused_seconds" = x."paused_seconds" + extract(epoch from now() - x."paused_at")::integer,
        "paused_at" = null
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is not null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'reopened' then v_meet := array[]::text[];
    else
      raise exception 'event is responded, resolved, reopened, paused or resumed' using errcode = '22023', hint = 'SLA_EVENT_INVALID';
  end case;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "met_at" = now(), "paused_at" = null
    where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
      and x."met_at" is null and x."metric" = any (v_meet)
    returning *
  loop
    perform "better_supabase".emit_event('sla.completed', jsonb_build_object('organizationId', v_clock."tenant_id", 'clockId', v_clock."id", 'subjectType', v_clock."subject_type", 'subjectId', v_clock."subject_id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at", 'late', v_clock."met_at" > v_clock."due_at"), 'sla-clocks/' || v_clock."id"::text, (v_clock."tenant_id"::text)::text, null, 'better-supabase/sla');
  end loop;
  select x.* into v_policy from "better_supabase"."sla_clocks" c join "better_supabase"."sla_policies" x on x."id" = c."policy_id"
  where c."subject_type" = record_sla_event.subject_type and c."subject_id" = record_sla_event.subject_id
  order by c."created_at" desc limit 1;
  if v_policy."id" is not null then
    if record_sla_event.event = 'responded' and v_policy."next_response_minutes" is not null
      and exists (select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id and x."metric" = 'resolution' and x."met_at" is null) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'next_response', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."next_response_minutes", v_policy."business_hours"))
      on conflict do nothing;
    elsif record_sla_event.event = 'reopened' and v_policy."resolution_minutes" is not null then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'resolution', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."resolution_minutes", v_policy."business_hours"))
      on conflict do nothing;
    end if;
  end if;
  return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relation_rollup (
  tenant       uuid,
  kind         text,
  subject_type text,
  subject_id   text,
  of_type      text,
  column_name  text,
  agg          text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_table text;
  v_id_col text;
  v_tenant_col text;
  v_ids text[];
  v_result jsonb;
begin
  if relation_rollup.agg is null or relation_rollup.agg not in ('count', 'sum', 'avg', 'min', 'max') then
    raise exception 'agg must be count, sum, avg, min or max' using errcode = '22023', hint = 'RELATION_ROLLUP_INVALID';
  end if;
  if relation_rollup.agg <> 'count' and relation_rollup.column_name is null then
    raise exception 'this aggregate needs a column' using errcode = '22023', hint = 'RELATION_ROLLUP_INVALID';
  end if;
  case relation_rollup.of_type
    when 'comment' then v_table := '"better_supabase"."comments"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    when 'company' then v_table := '"better_supabase"."companies"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'person' then v_table := '"better_supabase"."people"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'deal' then v_table := '"better_supabase"."deals"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'engagement' then v_table := '"better_supabase"."engagements"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'work_item' then v_table := '"better_supabase"."work_items"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'employee' then v_table := '"better_supabase"."employees"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'ledger_account' then v_table := '"better_supabase"."ledger_accounts"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'product' then v_table := '"better_supabase"."products"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'product_variant' then v_table := '"better_supabase"."product_variants"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'calendar_event' then v_table := '"better_supabase"."calendar_events"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'document' then v_table := '"better_supabase"."documents"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'customer' then v_table := '"public"."customers"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    when 'drive_node' then v_table := '"better_supabase"."drive_nodes"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'application' then v_table := '"better_supabase"."applications"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'project' then v_table := '"public"."projects"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    when 'task' then v_table := '"public"."tasks"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    else null;
  end case;
  if v_table is null then
    raise exception 'this subject type has no table' using errcode = '22023', hint = 'RELATION_SUBJECT_UNKNOWN';
  end if;
  select array_agg(w.id) into v_ids
  from "better_supabase"."relation_walk"(relation_rollup.tenant, relation_rollup.kind, relation_rollup.subject_type, relation_rollup.subject_id, false, null) w
  where w.type = relation_rollup.of_type;
  execute format(
    'select to_jsonb(%s) from %s s where s.%I::text = any ($1)%s',
    case when relation_rollup.agg = 'count' and relation_rollup.column_name is null then 'count(*)'
      else format('%s(s.%I)', relation_rollup.agg, relation_rollup.column_name) end,
    v_table,
    v_id_col,
    case when v_tenant_col is null then '' else format(' and s.%I = $2', v_tenant_col) end
  ) into v_result using coalesce(v_ids, '{}'::text[]), relation_rollup.tenant;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_ledger_hold (
  hold_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = release_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  v_row := "better_supabase"."ledger_unhold"(v_row."id", 'released');
  perform "better_supabase".emit_event('ledger_hold.released', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'transactionId', v_row."transaction_id"), 'ledger-holds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_approval (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  action       text,
  reason       text  DEFAULT NULL::text,
  payload      jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_policy jsonb := "better_supabase"."approval_policy"(request_approval.subject_type, request_approval.action);
begin
  if v_policy is null then
    raise exception 'no approval policy for this subject type and action' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and case request_approval.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    else false
  end)) then
    raise exception 'not allowed to request approval for this record' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  return "better_supabase"."open_approval"(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reverse_ledger_transaction (
  transaction_id uuid,
  memo           text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."ledger_transactions"%rowtype;
  v_row "better_supabase"."ledger_transactions"%rowtype;
  v_id uuid;
begin
  select * into v_old from "better_supabase"."ledger_transactions" x where x."id" = reverse_ledger_transaction.transaction_id;
  if not found then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_old."id" and x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  if v_old."reverses" is not null
    or exists (select 1 from "better_supabase"."ledger_transactions" x where x."reverses" = v_old."id") then
    raise exception 'this transaction is a reversal or is already reversed' using errcode = '55000', hint = 'LEDGER_ALREADY_REVERSED';
  end if;
  v_id := "better_supabase"."ledger_post"(v_old."tenant_id", v_old."kind",
    (select jsonb_agg(jsonb_build_object('account', y."account_id", 'amount', (-y."amount")::text) order by y."created_at", y."id")
      from "better_supabase"."ledger_entries" y where y."transaction_id" = v_old."id"),
    v_old."reference_type", v_old."reference_id", coalesce(reverse_ledger_transaction.memo, v_old."memo"),
    null, null, v_old."metadata", v_old."id");
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  perform "better_supabase".emit_event('ledger_transaction.reversed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id")), 'ledger-transactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  perform better_supabase.audit_event(
    event_type => 'ledger_transaction.reversed',
    category => 'billing',
    target_type => 'ledger_transaction',
    record_id => v_old."id"::text,
    summary => 'reversed a ' || v_old."kind" || ' transaction',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_document_version (
  document_id uuid,
  state       text,
  label       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = save_document_version.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'comment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'comments.create'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  return "better_supabase"."version_insert"(v_doc."tenant_id", 'document', v_doc."id"::text,
    jsonb_build_object('state', save_document_version.state, 'name', v_doc."name"),
    null, nullif(trim(save_document_version.label), ''), 'manual', false, auth.uid());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_deal_contacts (
  deal     uuid,
  contacts jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_deal uuid := set_deal_contacts.deal;
  v_item jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not (case coalesce(v_item ->> 'type', 'person')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(v_item ->> 'type', 'person'), (v_item ->> 'id'), 'read')) then
      raise exception 'a contact is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_CONTACT_FORBIDDEN';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(set_deal_contacts.contacts) x where coalesce((x.value ->> 'primary')::boolean, false)) > 1 then
    raise exception 'a deal has one primary contact' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  delete from "better_supabase"."deal_contacts" x where x."deal_id" = v_deal;
  insert into "better_supabase"."deal_contacts" ("tenant_id", "deal_id", "contact_type", "contact_id", "role", "is_primary")
  select v_tenant, v_deal, coalesce(x.value ->> 'type', 'person'), x.value ->> 'id', x.value ->> 'role', coalesce((x.value ->> 'primary')::boolean, false)
  from jsonb_array_elements(set_deal_contacts.contacts) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ship_transfer (
  transfer uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."from_location_id" as from_location, x."to_location_id" as to_location, x."status" as status
  into v_row from "better_supabase"."stock_transfers" x where x."id" = ship_transfer.transfer for update;
  if not found then
    raise exception 'transfer not found' using errcode = 'P0002', hint = 'INVENTORY_TRANSFER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row.tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_row.status <> 'draft' then
    raise exception 'the transfer can''t do this in its current status' using errcode = '55000', hint = 'INVENTORY_TRANSFER_STATUS';
  end if;
  perform "better_supabase"."move_stock"(v_row.tenant, x."variant_id", v_row.from_location, -x."quantity", 'transfer_out', 'transfer', ship_transfer.transfer::text, null)
  from "better_supabase"."stock_transfer_lines" x where x."transfer_id" = ship_transfer.transfer;
  update "better_supabase"."stock_transfers" x set "status" = 'in_transit', "shipped_at" = now() where x."id" = ship_transfer.transfer;
  perform "better_supabase".emit_event('transfer.shipped', jsonb_build_object('organizationId', v_row.tenant, 'id', ship_transfer.transfer, 'from', v_row.from_location, 'to', v_row.to_location, 'status', 'in_transit'), 'stock-transfers/' || ship_transfer.transfer::text, (v_row.tenant)::text, null, 'better-supabase/inventory');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_sla_clocks (
  subject_type text,
  subject_id   text,
  priority     text,
  trusted      boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text := (case start_sla_clocks.subject_type
      when 'comment' then (select s."organization_id"::text from "better_supabase"."comments" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      else null::text
    end);
  v_policy "better_supabase"."sla_policies";
  v_metric text;
  v_minutes integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if not (start_sla_clocks.trusted and pg_trigger_depth() > 0) and not ((auth.role() = 'service_role') or (case start_sla_clocks.subject_type
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(start_sla_clocks.subject_type, start_sla_clocks.subject_id, 'read'))) then
    raise exception 'not allowed to start clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  select * into v_policy from "better_supabase"."sla_policies" x
  where x."tenant_id"::text = v_tenant and x."subject_type" = start_sla_clocks.subject_type and x."archived_at" is null
    and (x."priority" = start_sla_clocks.priority or x."priority" is null)
  order by x."priority" nulls last
  limit 1;
  if v_policy."id" is null then
    return '[]'::jsonb;
  end if;
  foreach v_metric in array array['first_response', 'resolution'] loop
    v_minutes := case v_metric when 'first_response' then v_policy."first_response_minutes" else v_policy."resolution_minutes" end;
    if v_minutes is null then
      continue;
    end if;
    update "better_supabase"."sla_clocks" x set "policy_id" = v_policy."id",
      "due_at" = "better_supabase"."sla_due_at"(x."started_at", v_minutes, v_policy."business_hours") + make_interval(secs => x."paused_seconds")
    where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id
      and x."metric" = v_metric and x."met_at" is null;
    if not found and not exists (
      select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id and x."metric" = v_metric
    ) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", start_sla_clocks.subject_type, start_sla_clocks.subject_id, v_policy."id", v_metric, now(),
        "better_supabase"."sla_due_at"(now(), v_minutes, v_policy."business_hours"));
    end if;
  end loop;
  return "better_supabase"."sla_clocks_of"(start_sla_clocks.subject_type, start_sla_clocks.subject_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_timer (
  tenant        uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  billable      boolean DEFAULT false,
  rate          bigint  DEFAULT NULL::bigint,
  rate_currency text    DEFAULT NULL::text,
  note          text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case start_timer.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.rate is null) <> (start_timer.rate_currency is null) then
    raise exception 'name both rate and rate_currency, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if start_timer.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."rate_currency" := start_timer.rate_currency;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.started', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_tags (
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
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case subject_tags.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant)
    else false
  end) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_title (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case subject_title.subject_type
    when 'comment' then
      return (select s."body"::text from "better_supabase"."comments" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'company' then
      return (select s."name"::text from "better_supabase"."companies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'person' then
      return (select s."name"::text from "better_supabase"."people" s where s."id" = (subject_title.subject_id)::uuid);
    when 'deal' then
      return (select s."name"::text from "better_supabase"."deals" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'engagement' then
      return (select s."title"::text from "better_supabase"."engagements" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_item' then
      return (select s."title"::text from "better_supabase"."work_items" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select s."name"::text from "better_supabase"."employees" s where s."id" = (subject_title.subject_id)::uuid);
    when 'ledger_account' then
      return (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product' then
      return (select s."title"::text from "better_supabase"."products" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product_variant' then
      return (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (subject_title.subject_id)::uuid);
    when 'calendar_event' then
      return (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (subject_title.subject_id)::uuid);
    when 'document' then
      return (select s."name"::text from "better_supabase"."documents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'customer' then
      return (select s."name"::text from "public"."customers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'drive_node' then
      return (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'project' then
      return (select s."name"::text from "public"."projects" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'task' then
      return (select s."title"::text from "public"."tasks" s where s."id" = (subject_title.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_titles (
  refs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > 500 then
    raise exception 'subject_titles takes at most 500 refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'comment', 'id', s."id"::text,
      'title', s."body"::text, 'url', null::text))
    from "better_supabase"."comments" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'comment')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'company', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."companies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'company')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'person', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."people" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'person')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'deal', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/deals'))
    from "better_supabase"."deals" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'deal')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'engagement', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."engagements" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'engagement')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_item', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/work'))
    from "better_supabase"."work_items" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_item')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'employee', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/people'))
    from "better_supabase"."employees" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'employee')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'ledger_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."ledger_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'ledger_account')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/shop'))
    from "better_supabase"."products" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product_variant', 'id', s."id"::text,
      'title', s."sku"::text, 'url', null::text))
    from "better_supabase"."product_variants" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product_variant')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'calendar_event', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."calendar_events" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'calendar_event')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'document', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."documents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'document')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'customer', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/customers/' || s."id"::text))
    from "public"."customers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'customer')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'drive_node', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."drive_nodes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'drive_node')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'application', 'id', s."id"::text,
      'title', null::text, 'url', '/people/hiring'))
    from "better_supabase"."applications" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'application')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'project', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/projects/' || s."id"::text))
    from "public"."projects" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'project')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'task', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/projects/' || s."project_id"::text))
    from "public"."tasks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'task')::uuid[])), '[]'::jsonb);
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_types()
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select '{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,document,customer,drive_node,application,project,task}'::text[]
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_form (
  form_id       uuid,
  answers       jsonb,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  submission_id uuid    DEFAULT NULL::uuid,
  draft         boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = submit_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'forms.submit'), false))) then
    raise exception 'not allowed to submit this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'FORM_SUBJECT_INVALID';
  end if;
  if submit_form.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case submit_form.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant)
    else false
  end) then
    raise exception 'not allowed to link this record' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return "better_supabase"."form_submission_save"(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case tag.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when 'comment' then true
    when 'company' then true
    when 'person' then true
    when 'deal' then true
    when 'engagement' then true
    when 'work_item' then true
    when 'employee' then true
    when 'ledger_account' then true
    when 'product' then true
    when 'product_variant' then true
    when 'calendar_event' then true
    when 'document' then true
    when 'customer' then true
    when 'drive_node' then true
    when 'application' then true
    when 'project' then true
    when 'task' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  perform "better_supabase".emit_event('subject.tagged', jsonb_build_object('organizationId', tag.tenant, 'subjectType', tag.subject_type, 'subjectId', tag.subject_id, 'id', tag.tag_id), 'subjects/' || tag.subject_type || '/' || tag.subject_id, (tag.tenant)::text, null, 'better-supabase/tags');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.target_progress (
  tenant  uuid,
  on_date date,
  owner   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "better_supabase"."targets" x
    cross join lateral (select case x."metric"
        when 'deals.won_amount' then (select coalesce(sum(d."amount"), 0) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_user_id" is null or d."owner_user_id" = x."owner_user_id") and d."currency" = x."currency")
        when 'deals.won_count' then (select count(*) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_user_id" is null or d."owner_user_id" = x."owner_user_id"))
        when 'work_items.completed' then (select count(*) from "better_supabase"."work_items" w
      where w."tenant_id" = x."tenant_id" and w."state" = 'completed' and w."closed_at"::date between x."period_start" and x."period_end"
        and (x."team_id" is null or w."team_id" = x."team_id")
        and (x."owner_user_id" is null or exists (select 1 from "better_supabase"."work_item_assignees" a where a."work_item_id" = w."id" and a."user_id" = x."owner_user_id")))
        when 'invoices.paid_amount' then (select coalesce(sum(e."amount"), 0) from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where a."tenant_id" = x."tenant_id" and a."managed_by" = 'invoices' and a."code" = 'invoices:cash:' || x."currency" and y."effective_at"::date between x."period_start" and x."period_end")
        else x."actual"
      end as value) v
    where x."tenant_id" = target_progress.tenant and x."archived_at" is null
      and coalesce(target_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (target_progress.owner is null or x."owner_user_id" = target_progress.owner)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlink (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', unlink.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to unlink records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = unlink.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := unlink.target_type; v_source_id := unlink.target_id;
    v_target_type := unlink.source_type; v_target_id := unlink.source_id;
  else
    v_source_type := unlink.source_type; v_source_id := unlink.source_id;
    v_target_type := unlink.target_type; v_target_id := unlink.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if not (case unlink.source_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    else false
  end)
     or not (case unlink.target_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    else false
  end) then
    raise exception 'not allowed to unlink these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."relations"
    where "tenant_id" = unlink.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id
    returning * into v_old;
  if v_old."id" is null then
    return jsonb_build_object('removed', false, 'data', null);
  end if;
  perform "better_supabase".emit_event('subject.unlinked', jsonb_build_object('organizationId', unlink.tenant, 'id', v_old."id", 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id), 'subjects/' || v_source_type || '/' || v_source_id, (unlink.tenant)::text, null, 'better-supabase/relations');
  return jsonb_build_object('removed', true, 'data', v_old."data");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.untag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case untag.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  perform "better_supabase".emit_event('subject.untagged', jsonb_build_object('organizationId', untag.tenant, 'subjectType', untag.subject_type, 'subjectId', untag.subject_id, 'id', untag.tag_id), 'subjects/' || untag.subject_type || '/' || untag.subject_id, (untag.tenant)::text, null, 'better-supabase/tags');
  return true;
end;
$function$;

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
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not (case (v_change -> 'value' ->> 'type')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
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
        update "better_supabase"."deals" x set "owner_user_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
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

CREATE OR REPLACE FUNCTION better_supabase.update_engagement (
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
  v_id uuid := update_engagement.engagement;
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
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('engagement.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/engagements');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
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
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_quote (
  quote uuid,
  attrs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not (case coalesce(update_quote.attrs -> 'company' ->> 'type', 'company')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(update_quote.attrs -> 'company' ->> 'type', 'company'), (update_quote.attrs -> 'company' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not (case coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person')
      when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person'), (update_quote.attrs -> 'contact' ->> 'id'), 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_user_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  perform "better_supabase".emit_event('quote.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_time_entry (
  entry_id uuid,
  patch    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case v_row."subject_type"
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' or v_patch ? 'rateCurrency' then
    v_row."rate" := (v_patch ->> 'rate')::bigint;
    v_row."rate_currency" := v_patch ->> 'rateCurrency';
    if (v_row."rate" is null) <> (v_row."rate_currency" is null) then
    raise exception 'name both rate and rate_currency, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if v_row."rate_currency" !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "better_supabase"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "rate_currency" = v_row."rate_currency",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'previousStartedAt', v_previous_started_at), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.void_invoice (
  invoice uuid,
  reason  text
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
  update "better_supabase"."invoices" x set "status" = 'void', "voided_at" = now(),
    "void_reason" = nullif(trim(void_invoice.reason), ''), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
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
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference') order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.write_off_invoice (
  invoice uuid
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
  update "better_supabase"."invoices" x set "status" = 'uncollectible', "updated_at" = now()
  where x."id" = write_off_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.manage'), false)) and x."status" in ('issued', 'partially_paid')
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'only an open invoice you can manage is written off' using errcode = '55000', hint = 'INVOICE_NOT_OPEN';
  end if;
  perform "better_supabase".emit_event('invoice.uncollected', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.uncollected',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice uncollected',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text)
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference') order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

ALTER TABLE "better_supabase"."ledger_balances"
  ADD CONSTRAINT "ledger_balances_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.ledger_accounts(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ledger_entries"
  ADD CONSTRAINT "ledger_entries_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.ledger_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."ledger_holds"
  ADD CONSTRAINT "ledger_holds_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.ledger_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."ledger_entries"
  ADD CONSTRAINT "ledger_entries_transaction_id_fkey" FOREIGN KEY (transaction_id) REFERENCES better_supabase.ledger_transactions(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."ledger_holds"
  ADD CONSTRAINT "ledger_holds_transaction_id_fkey" FOREIGN KEY (transaction_id) REFERENCES better_supabase.ledger_transactions(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."ledger_transactions"
  ADD CONSTRAINT "ledger_transactions_reverses_fkey" FOREIGN KEY (reverses) REFERENCES better_supabase.ledger_transactions(id) ON DELETE RESTRICT;

CREATE INDEX ledger_accounts_holder_idx ON better_supabase.ledger_accounts USING btree (tenant_id, holder_type, holder_id)
  WHERE (holder_type IS NOT NULL);

CREATE INDEX ledger_accounts_kind_idx ON better_supabase.ledger_accounts USING btree (tenant_id, kind);

CREATE INDEX ledger_accounts_owner_idx ON better_supabase.ledger_accounts USING btree (owner_id)
  WHERE (owner_id IS NOT NULL);

CREATE INDEX ledger_accounts_read_permission_idx ON better_supabase.ledger_accounts USING btree (tenant_id, read_permission)
  WHERE (read_permission IS NOT NULL);

CREATE INDEX ledger_balances_tenant_idx ON better_supabase.ledger_balances USING btree (tenant_id);

CREATE INDEX ledger_entries_account_idx ON better_supabase.ledger_entries USING btree (account_id, created_at DESC);

CREATE INDEX ledger_entries_transaction_idx ON better_supabase.ledger_entries USING btree (transaction_id);

CREATE INDEX ledger_holds_account_idx ON better_supabase.ledger_holds USING btree (account_id)
  WHERE (status = 'active'::text);

CREATE INDEX ledger_holds_expiry_idx ON better_supabase.ledger_holds USING btree (expires_at)
  WHERE ((status = 'active'::text) AND (expires_at IS NOT NULL));

CREATE UNIQUE INDEX ledger_transactions_key_idx ON better_supabase.ledger_transactions USING btree (tenant_id, idempotency_key)
  WHERE (idempotency_key IS NOT NULL);

CREATE INDEX ledger_transactions_reference_idx ON better_supabase.ledger_transactions USING btree (tenant_id, reference_type, reference_id)
  WHERE (reference_type IS NOT NULL);

CREATE UNIQUE INDEX ledger_transactions_reverses_idx ON better_supabase.ledger_transactions USING btree (reverses)
  WHERE (reverses IS NOT NULL);

CREATE INDEX ledger_transactions_tenant_idx ON better_supabase.ledger_transactions USING btree (tenant_id, effective_at DESC);

CREATE TRIGGER bs_ledger_entries_append_only
  BEFORE DELETE OR UPDATE ON better_supabase.ledger_entries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_append_only();

CREATE TRIGGER bs_ledger_entries_apply
  AFTER INSERT ON better_supabase.ledger_entries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_apply_entry();

CREATE CONSTRAINT TRIGGER bs_ledger_entries_balanced
  AFTER INSERT ON better_supabase.ledger_entries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_check_balanced();

CREATE TRIGGER bs_ledger_transactions_append_only
  BEFORE DELETE OR UPDATE ON better_supabase.ledger_transactions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_append_only();

CREATE POLICY "activity_entries_read" ON "better_supabase"."activity_entries"
  FOR SELECT
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('activity.read'::text) AS tenant_ids_with)) AND ((subject_type IS NULL) OR (subject_id IS NULL) OR (NOT
    (subject_type = ANY
    ('{comment,company,person,deal,engagement,work_item,employee,ledger_account,product,product_variant,calendar_event,document,customer,drive_node,application,project,task}'::text[]))) OR better_supabase.activity_subject_readable(subject_type, subject_id))));

CREATE POLICY "ledger_accounts_read" ON "better_supabase"."ledger_accounts"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)) OR (owner_id = ( SELECT auth.uid() AS uid)) OR ((tenant_id, read_permission)
    IN ( SELECT g.tenant,
    g.permission
   FROM better_supabase.ledger_read_grants() g(tenant, permission)))));

CREATE POLICY "ledger_balances_read" ON "better_supabase"."ledger_balances"
  FOR SELECT
  TO "authenticated"
  USING ((account_id IN ( SELECT y.id
   FROM better_supabase.ledger_accounts y)));

CREATE POLICY "ledger_entries_read" ON "better_supabase"."ledger_entries"
  FOR SELECT
  TO "authenticated"
  USING ((account_id IN ( SELECT y.id
   FROM better_supabase.ledger_accounts y)));

CREATE POLICY "ledger_holds_read" ON "better_supabase"."ledger_holds"
  FOR SELECT
  TO "authenticated"
  USING ((account_id IN ( SELECT y.id
   FROM better_supabase.ledger_accounts y)));

CREATE POLICY "ledger_transactions_read" ON "better_supabase"."ledger_transactions"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.ledger_entries y
  WHERE (y.transaction_id = y.id)))));

REVOKE ALL ON FUNCTION "better_supabase"."capture_ledger_hold"(uuid, uuid, bigint, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."capture_ledger_hold"(uuid, uuid, bigint, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."close_ledger_account"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."close_ledger_account"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."expire_ledger_holds"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."expire_ledger_holds"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ledger_transaction"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ledger_transaction"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ledger_account_entries"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ledger_account_entries"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ledger_account_for"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, text, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."ledger_append_only"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."ledger_apply_entry"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."ledger_check_balanced"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."ledger_post"(uuid, text, jsonb, text, text, text, text, timestamp WITH time zone, jsonb, uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."ledger_read_grants"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ledger_read_grants"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ledger_unhold"(uuid, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."list_ledger_accounts"(uuid, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ledger_accounts"(uuid, text, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."move_stock"(uuid, uuid, uuid, integer, text, text, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."place_ledger_hold"(uuid, bigint, text, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."place_ledger_hold"(uuid, bigint, text, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamp WITH time zone, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamp WITH time zone, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_ledger_hold"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_ledger_hold"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reverse_ledger_transaction"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reverse_ledger_transaction"(uuid, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."ledger_accounts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ledger_accounts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ledger_balances" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ledger_balances" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ledger_entries" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ledger_entries" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ledger_holds" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ledger_holds" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ledger_transactions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ledger_transactions" TO "service_role";
