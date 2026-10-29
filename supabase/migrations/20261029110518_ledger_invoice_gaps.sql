SET local check_function_bodies = off;

DROP TRIGGER "bsb_ledger_entries_append_only" ON "better_supabase"."ledger_entries";

DROP TRIGGER "bsb_ledger_transactions_append_only" ON "better_supabase"."ledger_transactions";

CREATE OR REPLACE FUNCTION api.list_invoice_payments (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_invoice_payments"($1) $function$;

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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.read'), false) or coalesce(v_account."owner_id" = auth.uid(), false) or (v_account."read_permission" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", v_account."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit",
        'transactionId', r."id", 'kind', r."kind", 'referenceType', r."reference_type", 'referenceId', r."reference_id",
        'memo', r."memo", 'reverses', r."reverses", 'metadata', r."metadata", 'effectiveAt', r."effective_at", 'actorId', r."actor_id", 'createdAt', y."created_at") as item,
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

CREATE OR REPLACE FUNCTION better_supabase.ledger_append_only()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'DELETE' and current_setting('better_supabase.purge_tenant', true) = to_jsonb(old) ->> tg_argv[0] then
    if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and exists (
      select 1 from "better_supabase"."organization_deletions" x
      where x."organization_id"::text = to_jsonb(old) ->> tg_argv[0]
        and x."cancelled_at" is null and x."purged_at" is null and x."purge_after" <= now()
    ) then
      return old;
    end if;
  end if;
  raise exception 'ledger entries and transactions can''t be changed or deleted; post a reversal' using errcode = '55000', hint = 'LEDGER_APPEND_ONLY';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_invoice_payments (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = list_invoice_payments.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false));
  if v_row."id" is null then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return jsonb_build_object('currency', v_row."currency", 'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_organization (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_deletions";
  v_table record;
  v_type text;
  v_count bigint;
  v_deleted jsonb := '{}'::jsonb;
  v_pending text[];
  v_left text[];
  v_name text;
  v_pass integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = purge_organization.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null or v_row."purge_after" > now() then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = purge_organization.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."on_organization_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using purge_organization.tenant;
    end if;
  end;
  -- Tables go in reverse order; a table whose rows another table still
  -- references (a restricting foreign key) waits for a later pass.
  v_pending := array(
    select t.name from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = 'organization' and t.purge and to_regclass(t.tbl) is not null
      and to_regclass(t.tbl) <> to_regclass('"better_supabase"."organization_deletions"') and to_regclass(t.tbl) is distinct from to_regclass('"public"."organizations"')
    order by (row_number() over ()) desc
  );
  perform set_config('better_supabase.purge_tenant', purge_organization.tenant::text, true);
  for v_pass in 1..10 loop
    exit when cardinality(v_pending) = 0;
    v_left := '{}';
    foreach v_name in array v_pending loop
      select * into v_table from "better_supabase"."data_lifecycle_tables"() t
      where t.subject = 'organization' and t.name = v_name;
      select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
      begin
        execute format('delete from %s t where t.%I = $1::%s', v_table.tbl, v_table.col, v_type)
          using purge_organization.tenant::text;
        get diagnostics v_count = row_count;
        v_deleted := v_deleted || jsonb_build_object(v_name, coalesce((v_deleted ->> v_name)::bigint, 0) + v_count);
      exception when foreign_key_violation or restrict_violation or check_violation then
        -- Another table's rows still point here (or a set null action breaks
        -- a check on them): try again after the other tables.
        v_left := v_left || v_name;
      end;
    end loop;
    if v_left = v_pending then
      raise exception 'Rows in % still have references the purge does not delete', array_to_string(v_left, ', ')
        using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
    end if;
    v_pending := v_left;
  end loop;
  perform set_config('better_supabase.purge_tenant', '', true);
  update "better_supabase"."organization_deletions" x set "purged_at" = now() where x."organization_id" = v_row."organization_id" returning * into v_row;
  begin
    delete from "public"."organizations" where "id" = purge_organization.tenant;
  exception when foreign_key_violation or restrict_violation then
    raise exception 'Rows still reference the organization: %', sqlerrm
      using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
  end;
  perform "better_supabase".emit_event('organization.purged', jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', null::uuid, 'purgeAfter', v_row."purge_after"), 'organizations/' || v_row."organization_id"::text, (null)::text, 'organization.purged:' || v_row."organization_id"::text, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'organization.purged',
    category => 'data',
    target_type => 'organization',
    record_id => v_row."organization_id"::text,
    tenant => (null)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', null::uuid, 'purgeAfter', v_row."purge_after"),
    idempotency_key => 'organization.purged:' || v_row."organization_id"::text
  );
  return jsonb_build_object('organizationId', v_row."organization_id"::text, 'deleted', v_deleted);
end;
$function$;

CREATE TRIGGER bsb_ledger_entries_append_only
  BEFORE DELETE OR UPDATE ON better_supabase.ledger_entries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_append_only('tenant_id');

CREATE TRIGGER bsb_ledger_transactions_append_only
  BEFORE DELETE OR UPDATE ON better_supabase.ledger_transactions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ledger_append_only('tenant_id');

REVOKE ALL ON FUNCTION "api"."list_invoice_payments"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_invoice_payments"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_invoice_payments"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_invoice_payments"(uuid) TO "authenticated", "service_role";
