SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.restore_case_kind (
  kind_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_case_kind"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_consent_purpose (
  purpose_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_consent_purpose"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_lims_method (
  method_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_lims_method"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_observation_definition (
  definition_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_observation_definition"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_shift_template (
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_shift_template"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_company (
  id       uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_name text;
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."name", x."archived_at" into v_tenant, v_name, v_was from "better_supabase"."companies" x where x."id" = archive_company.id;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."companies" x set "archived_at" = case when archive_company.archived then coalesce(x."archived_at", now()) end, "updated_at" = now()
    where x."id" = archive_company.id;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  if archive_company.archived then
    perform "better_supabase".emit_event('company.archived', jsonb_build_object('organizationId', v_tenant, 'companyId', archive_company.id, 'name', v_name), 'companies/' || archive_company.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  elsif v_was is not null then
    perform "better_supabase".emit_event('company.restored', jsonb_build_object('organizationId', v_tenant, 'companyId', archive_company.id, 'name', v_name), 'companies/' || archive_company.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_person (
  id       uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_name text;
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."name", x."archived_at" into v_tenant, v_name, v_was from "better_supabase"."people" x where x."id" = archive_person.id;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."people" x set "archived_at" = case when archive_person.archived then coalesce(x."archived_at", now()) end, "updated_at" = now()
    where x."id" = archive_person.id;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  if archive_person.archived then
    perform "better_supabase".emit_event('person.archived', jsonb_build_object('organizationId', v_tenant, 'personId', archive_person.id, 'name', v_name), 'persons/' || archive_person.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  elsif v_was is not null then
    perform "better_supabase".emit_event('person.restored', jsonb_build_object('organizationId', v_tenant, 'personId', archive_person.id, 'name', v_name), 'persons/' || archive_person.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_case_kind (
  kind_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."case_kinds";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."case_kinds" x where x."id" = restore_case_kind.kind_id for update;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.manage'), false))) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    update "better_supabase"."case_kinds" x set "archived_at" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('case_kind.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'caseKindId', v_row."id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix"), 'case-kinds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case_kind.restored',
    category => 'data',
    target_type => 'case_kind',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'case kind restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseKindId', v_row."id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'pipelineId', v_row."pipeline_id", 'investigationFormId', v_row."investigation_form_id", 'effectivenessFormId', v_row."effectiveness_form_id", 'effectivenessAfterDays', v_row."effectiveness_after_days", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'requiresRevisions', v_row."requires_revisions", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_consent_purpose (
  purpose_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."consent_purposes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."consent_purposes" x where x."id" = restore_consent_purpose.purpose_id for update;
  if not found then
    raise exception 'no such consent purpose' using errcode = 'P0002', hint = 'CONSENT_PURPOSE_NOT_FOUND';
  end if;
  if v_row."tenant_id" is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'only the service role restores a system purpose' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.manage'), false))) then
    raise exception 'not allowed to manage consent purposes' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'legalBasis', v_row."legal_basis", 'version', v_row."version", 'requiresSignature', v_row."requires_signature", 'validMonths', v_row."valid_months", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."consent_purposes" x set
    "updated_at" = now(),
    "archived_at" = null
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('consent_purpose.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'purposeId', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'consent-purposes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/consents');
  perform better_supabase.audit_event(
    event_type => 'consent_purpose.updated',
    category => 'data',
    target_type => 'consent_purpose',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'restored a consent purpose',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'purposeId', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'legalBasis', v_row."legal_basis", 'version', v_row."version", 'requiresSignature', v_row."requires_signature", 'validMonths', v_row."valid_months", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_lims_method (
  method_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."lims_methods";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."lims_methods" x where x."id" = restore_lims_method.method_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.read'), false))) then
    raise exception 'no such test method' using errcode = 'P0002', hint = 'LIMS_METHOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.manage'), false))) then
    raise exception 'not allowed to restore test methods' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    update "better_supabase"."lims_methods" x set "archived_at" = null, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
    perform "better_supabase".emit_event('lims_method.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key"), 'lims-methods/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/lims');
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'lowerLimit', v_row."lower_limit", 'upperLimit', v_row."upper_limit", 'formId', v_row."form_id", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_observation_definition (
  definition_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."observation_definitions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."observation_definitions" x where x."id" = restore_observation_definition.definition_id;
  if not found then
    raise exception 'observation definition not found' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
  end if;
  if v_row."tenant_id" is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'only the service role restores system definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'observations.manage'), false)) then
    raise exception 'not allowed to manage observation definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    update "better_supabase"."observation_definitions" x set "archived_at" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('observation_definition.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title"), 'observation-definitions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation_definition.updated',
    category => 'configuration',
    target_type => 'observation_definition',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'Observation definition restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title")
  );
  end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'system', v_row."tenant_id" is null, 'key', v_row."key", 'title', v_row."title", 'valueType', v_row."value_type", 'unit', v_row."unit", 'codeSystem', v_row."code_system", 'code', v_row."code", 'components', coalesce(v_row."components", '[]'::jsonb), 'decimals', v_row."decimals", 'validLow', v_row."valid_low", 'validHigh', v_row."valid_high", 'referenceLow', v_row."reference_low", 'referenceHigh', v_row."reference_high", 'criticalLow', v_row."critical_low", 'criticalHigh', v_row."critical_high", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_shift_template (
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_templates" x where x."id" = restore_shift_template.template_id;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  update "better_supabase"."shift_templates" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

REVOKE ALL ON FUNCTION "api"."restore_case_kind"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_case_kind"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_consent_purpose"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_consent_purpose"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_lims_method"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_lims_method"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_observation_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_observation_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_shift_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_shift_template"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_case_kind"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_case_kind"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_consent_purpose"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_consent_purpose"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_lims_method"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_lims_method"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_observation_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_observation_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_shift_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_shift_template"(uuid) TO "authenticated", "service_role";
