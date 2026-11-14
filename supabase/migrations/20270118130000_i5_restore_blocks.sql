SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.restore_asset_location (
  location_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_asset_location"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_compliance_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_compliance_policy"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_content_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_content_entry"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_medication (
  medication_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_medication"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_option_set_item (
  item uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_option_set_item"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_pipeline (
  pipeline uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_pipeline"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_pipeline_stage (
  stage uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_pipeline_stage"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_asset_location (
  location_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = restore_asset_location.location_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    if v_row."parent_id" is not null and exists (select 1 from "better_supabase"."asset_locations" y where y."id" = v_row."parent_id" and y."archived_at" is not null) then
      raise exception 'restore the parent location first' using errcode = '55000', hint = 'ASSETS_LOCATION_IN_USE';
    end if;
    update "better_supabase"."asset_locations" x set "archived_at" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('asset_location.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'parentId', v_row."parent_id"), 'asset-locations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset_location.restored',
    category => 'data',
    target_type => 'asset_location',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'restored location',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'parentId', v_row."parent_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', extensions.st_asgeojson(v_row.area::extensions.geometry)::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_compliance_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."compliance_policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."compliance_policies" x where x."id" = restore_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    update "better_supabase"."compliance_policies" x set "archived_at" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    if v_row."requires_acknowledgement" then
      perform "better_supabase"."place_acknowledgement_assignment"(v_row."tenant_id", 'compliance_policy', v_row."id"::text, 'role', '*', null);
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_content_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."content_entries";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."content_entries" x where x."id" = restore_content_entry.entry_id for update;
  if not found then
    raise exception 'no such content entry' using errcode = 'P0002', hint = 'CONTENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.write'), false))) then
    raise exception 'not allowed to restore this entry' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
  end if;
  if v_row."status" <> 'archived' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."content_entries" x set
    "status" = 'draft',
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('content_entry.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id"), 'content-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/content');
  perform better_supabase.audit_event(
    event_type => 'content_entry.restored',
    category => 'data',
    target_type => 'content_entry',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'restored a content entry',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_medication (
  medication_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_medication "better_supabase"."medications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_medication from "better_supabase"."medications" x where x."id" = restore_medication.medication_id;
  if not found then
    raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_medication."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to change the medication catalog' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  update "better_supabase"."medications" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_medication."id"
  returning x.* into v_medication;
  return jsonb_build_object('id', v_medication."id", 'organizationId', v_medication."tenant_id", 'name', v_medication."name", 'codeSystem', v_medication."code_system", 'code', v_medication."code", 'form', v_medication."form", 'strength', v_medication."strength", 'unit', v_medication."unit", 'highRisk', v_medication."high_risk", 'archivedAt', v_medication."archived_at", 'createdAt', v_medication."created_at", 'updatedAt', v_medication."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_option_set_item (
  item uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_set uuid;
  v_item uuid := restore_option_set_item.item;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."option_set_id" into v_tenant, v_set
  from "better_supabase"."option_set_items" x
  where x."id" = restore_option_set_item.item and x."archived_at" is not null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'option_sets.manage'), false)) then
    raise exception 'not allowed to manage option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  update "better_supabase"."option_set_items" x set "archived_at" = null, "updated_at" = now() where x."id" = restore_option_set_item.item;
  perform "better_supabase".emit_event('option_set_item.restored', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set_item.restored',
    category => 'configuration',
    target_type => 'option_set_item',
    record_id => v_item::text,
    summary => 'restored an option set item',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_pipeline (
  pipeline uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_subject_type text;
  v_pipeline uuid := restore_pipeline.pipeline;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = restore_pipeline.pipeline and x."archived_at" is not null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  update "better_supabase"."pipelines" x set "archived_at" = null, "updated_at" = now()
  where x."id" = restore_pipeline.pipeline;
  perform "better_supabase".emit_event('pipeline.restored', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'subjectType', v_subject_type), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline.restored',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'restored a pipeline',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'subjectType', v_subject_type)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_pipeline_stage (
  stage uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_pipeline_archived timestamptz;
  v_stage uuid := restore_pipeline_stage.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", y."archived_at"
    into v_tenant, v_pipeline, v_pipeline_archived
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = restore_pipeline_stage.stage and x."archived_at" is not null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if v_pipeline_archived is not null then
    raise exception 'restore the pipeline first' using errcode = '55000', hint = 'PIPELINE_ARCHIVED';
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = null, "updated_at" = now() where x."id" = restore_pipeline_stage.stage;
  perform "better_supabase".emit_event('pipeline_stage.restored', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.restored',
    category => 'configuration',
    target_type => 'pipeline_stage',
    record_id => v_stage::text,
    summary => 'restored a pipeline stage',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage)
  );
  return true;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."restore_asset_location"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_asset_location"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_compliance_policy"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_compliance_policy"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_content_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_content_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_medication"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_medication"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_option_set_item"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_option_set_item"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_pipeline"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_pipeline"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_pipeline_stage"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_pipeline_stage"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_asset_location"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_asset_location"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_compliance_policy"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_compliance_policy"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_content_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_content_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_medication"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_medication"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_option_set_item"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_option_set_item"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_pipeline"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_pipeline"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_pipeline_stage"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_pipeline_stage"(uuid) TO "authenticated", "service_role";
