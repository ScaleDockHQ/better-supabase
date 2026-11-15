SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_form_submission"(uuid);

DROP FUNCTION "api"."list_form_submissions"(uuid, text, integer, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."delete_form_submission"(uuid);

DROP FUNCTION "better_supabase"."list_form_submissions"(uuid, text, integer, timestamp WITH time zone);

ALTER TABLE "better_supabase"."form_submissions"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_form_submission (
  submission_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_form_submission"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_form_submissions (
  form_id          uuid,
  status           text                     DEFAULT NULL::text,
  page_size        integer                  DEFAULT 50,
  before           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  include_archived boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_form_submissions"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.purge_form_submission (
  submission_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_form_submission"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_form_submission (
  submission_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_form_submission"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_form_submission (
  submission_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = archive_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'not allowed to archive submissions' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at", 'score', v_row."score", 'maxScore', v_row."max_score", 'passed', v_row."passed");
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft isn''t submitted yet' using errcode = '55000', hint = 'FORM_SUBMISSION_DRAFT';
  end if;
  update "better_supabase"."form_submissions" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('form_submission.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id"), 'form-submissions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
  perform better_supabase.audit_event(
    event_type => 'form_submission.archived',
    category => 'data',
    target_type => 'form_submission',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at", 'score', v_row."score", 'maxScore', v_row."max_score", 'passed', v_row."passed");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.form_nps (
  form_id uuid,
  field   text                     DEFAULT NULL::text,
  since   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  bucket  text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_field text := form_nps.field;
  v_total jsonb;
  v_periods jsonb;
begin
  select * into v_form from "better_supabase"."forms" x where x."id" = form_nps.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_form."tenant_id", 'forms.review'), false)) then
    raise exception 'not allowed to read this form''s results' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if form_nps.bucket is not null and form_nps.bucket not in ('day', 'week', 'month', 'quarter', 'year') then
    raise exception 'bucket is day, week, month, quarter, year' using errcode = '22023', hint = 'FORM_NPS_BUCKET_INVALID';
  end if;
  if v_field is null then
    select q.field ->> 'key' into v_field
    from "better_supabase"."form_versions" x
    cross join lateral jsonb_array_elements(x."definition" -> 'steps') with ordinality as p(step, step_ord)
    cross join lateral jsonb_array_elements(p.step -> 'fields') with ordinality as q(field, field_ord)
    where x."id" = v_form."current_version_id" and q.field ->> 'type' = 'nps'
    order by p.step_ord, q.field_ord
    limit 1;
    if v_field is null then
      raise exception 'the form has no nps field' using errcode = '22023', hint = 'FORM_NPS_FIELD_MISSING';
    end if;
  end if;
  with answered as (
    select r.answer, r.answered_at from (
      select case when jsonb_typeof(x."answers" -> v_field) = 'number' then (x."answers" ->> v_field)::numeric end as answer,
        x."submitted_at" as answered_at
      from "better_supabase"."form_submissions" x
      where x."form_id" = form_nps.form_id
        and x."status" in ('submitted', 'accepted')
        and x."archived_at" is null
        and (form_nps.since is null or x."submitted_at" >= form_nps.since)
        and (form_nps.until is null or x."submitted_at" < form_nps.until)
    ) r
    where r.answer between 0 and 10
  )
  select jsonb_build_object('responses', count(*), 'promoters', count(*) filter (where a.answer >= 9), 'passives', count(*) filter (where a.answer >= 7 and a.answer < 9), 'detractors', count(*) filter (where a.answer < 7), 'score', case when count(*) = 0 then null else round((count(*) filter (where a.answer >= 9) - count(*) filter (where a.answer < 7)) * 100.0 / count(*), 1) end),
    case when form_nps.bucket is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('start', g.start) || g.counts order by g.start)
      from (
        select date_trunc(form_nps.bucket, b.answered_at, 'UTC') as start, jsonb_build_object('responses', count(*), 'promoters', count(*) filter (where b.answer >= 9), 'passives', count(*) filter (where b.answer >= 7 and b.answer < 9), 'detractors', count(*) filter (where b.answer < 7), 'score', case when count(*) = 0 then null else round((count(*) filter (where b.answer >= 9) - count(*) filter (where b.answer < 7)) * 100.0 / count(*), 1) end) as counts
        from answered b
        group by 1
      ) g), '[]'::jsonb) end
  into v_total, v_periods
  from answered a;
  return jsonb_build_object('field', v_field) || v_total || jsonb_build_object('periods', v_periods);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.form_submission_save (
  form_id       uuid,
  answers       jsonb,
  subject_type  text,
  subject_id    text,
  respondent    uuid,
  source        text,
  draft         boolean,
  submission_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_schema jsonb;
  v_definition jsonb;
  v_grade jsonb;
  v_errors text[];
  v_row "better_supabase"."form_submissions"%rowtype;
  v_link jsonb;
begin
  select * into v_form from "better_supabase"."forms" x where x."id" = form_submission_save.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if v_form."status" <> 'open' then
    raise exception 'this form isn''t taking submissions' using errcode = '55000', hint = 'FORM_CLOSED';
  end if;
  if jsonb_typeof(form_submission_save.answers) is distinct from 'object' then
    raise exception 'answers must be an object' using errcode = '22023', hint = 'FORM_ANSWERS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_submission"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using form_submission_save.form_id, form_submission_save.answers;
    end if;
  end;
  if not form_submission_save.draft then
    select x."schema", x."definition" into v_schema, v_definition from "better_supabase"."form_versions" x where x."id" = v_form."current_version_id";
    v_errors := extensions.jsonschema_validation_errors(v_schema::json, form_submission_save.answers::json);
    if cardinality(v_errors) > 0 then
      raise exception '%.answers does not match its JSON Schema: %', 'form_submissions', array_to_string(v_errors, '; ')
      using errcode = '23514', column = 'answers', detail = to_jsonb(v_errors)::text, hint = 'JSON_SCHEMA_INVALID';
    end if;
    v_grade := "better_supabase"."form_score"(v_definition, (select a."answers" from "better_supabase"."form_answer_keys" a where a."version_id" = v_form."current_version_id"), form_submission_save.answers);
  end if;
  if form_submission_save.submission_id is not null then
    select * into v_row from "better_supabase"."form_submissions" x where x."id" = form_submission_save.submission_id for update;
    if not found or v_row."form_id" <> form_submission_save.form_id or v_row."respondent_id" is distinct from form_submission_save.respondent then
      raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
    end if;
    if v_row."status" <> 'draft' then
      raise exception 'only a draft submission can change' using errcode = '55000', hint = 'FORM_SUBMISSION_LOCKED';
    end if;
    update "better_supabase"."form_submissions" x set
      "version_id" = v_form."current_version_id",
      "answers" = form_submission_save.answers,
      "status" = case when form_submission_save.draft then 'draft' else 'submitted' end,
      "submitted_at" = case when form_submission_save.draft then null else now() end,
      "subject_type" = coalesce(form_submission_save.subject_type, x."subject_type"),
      "subject_id" = coalesce(form_submission_save.subject_id, x."subject_id"),
      "score" = (v_grade ->> 'score')::numeric,
      "max_score" = (v_grade ->> 'maxScore')::numeric,
      "passed" = (v_grade ->> 'passed')::boolean,
      "updated_at" = now()
    where x."id" = form_submission_save.submission_id
    returning * into v_row;
  else
    insert into "better_supabase"."form_submissions" ("tenant_id", "form_id", "version_id", "subject_type", "subject_id", "respondent_id", "answers", "status", "source", "submitted_at", "score", "max_score", "passed")
    values (v_form."tenant_id", v_form."id", v_form."current_version_id", form_submission_save.subject_type, form_submission_save.subject_id, form_submission_save.respondent, form_submission_save.answers,
      case when form_submission_save.draft then 'draft' else 'submitted' end, form_submission_save.source,
      case when form_submission_save.draft then null else now() end, (v_grade ->> 'score')::numeric, (v_grade ->> 'maxScore')::numeric, (v_grade ->> 'passed')::boolean)
    returning * into v_row;
  end if;
  if not form_submission_save.draft then
    perform "better_supabase".emit_event('form_submission.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'source', v_row."source", 'score', v_row."score", 'maxScore', v_row."max_score", 'passed', v_row."passed"), 'form-submissions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_submission"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at", 'score', v_row."score", 'maxScore', v_row."max_score", 'passed', v_row."passed");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_form_submission (
  submission_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = get_form_submission.submission_id;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."respondent_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at", 'score', v_row."score", 'maxScore', v_row."max_score", 'passed', v_row."passed");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_form_submissions (
  form_id          uuid,
  status           text                     DEFAULT NULL::text,
  page_size        integer                  DEFAULT 50,
  before           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  include_archived boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_all boolean;
  v_rows jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = list_form_submissions.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  v_all := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'forms.review'), false);
  select coalesce(jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'formId', r."form_id", 'versionId', r."version_id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'respondentId', r."respondent_id", 'answers', r."answers", 'status', r."status", 'source', r."source", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at", 'archivedAt', r."archived_at", 'createdAt', r."created_at", 'submittedAt', r."submitted_at", 'updatedAt', r."updated_at", 'score', r."score", 'maxScore', r."max_score", 'passed', r."passed") order by r."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."form_submissions" x
    where x."form_id" = list_form_submissions.form_id
      and (v_all or x."respondent_id" = auth.uid())
      and (list_form_submissions.status is null or x."status"::text = list_form_submissions.status)
      and (list_form_submissions.before is null or x."created_at" < list_form_submissions.before)
      and (coalesce(list_form_submissions.include_archived, false) or x."archived_at" is null)
    order by x."created_at" desc
    limit least(greatest(coalesce(list_form_submissions.page_size, 50), 1), 200)
  ) r;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_form_submission (
  submission_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = purge_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)
    or (coalesce(v_row."respondent_id" = auth.uid(), false) and v_row."status" = 'draft')) then
    raise exception 'not allowed to purge this submission' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  delete from "better_supabase"."form_submissions" x where x."id" = purge_form_submission.submission_id;
  perform "better_supabase".emit_event('form_submission.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id"), 'form-submissions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
  perform better_supabase.audit_event(
    event_type => 'form_submission.purged',
    category => 'data',
    target_type => 'form_submission',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_form_submission (
  submission_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = restore_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'not allowed to restore submissions' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at", 'score', v_row."score", 'maxScore', v_row."max_score", 'passed', v_row."passed");
  end if;
  update "better_supabase"."form_submissions" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('form_submission.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id"), 'form-submissions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
  perform better_supabase.audit_event(
    event_type => 'form_submission.restored',
    category => 'data',
    target_type => 'form_submission',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at", 'score', v_row."score", 'maxScore', v_row."max_score", 'passed', v_row."passed");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.review_form_submission (
  submission_id uuid,
  status        text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = review_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'not allowed to review submissions' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if review_form_submission.status is null or review_form_submission.status not in ('submitted', 'accepted', 'rejected') then
    raise exception 'status is submitted, accepted or rejected' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft isn''t submitted yet' using errcode = '55000', hint = 'FORM_SUBMISSION_DRAFT';
  end if;
  update "better_supabase"."form_submissions" x set
    "status" = review_form_submission.status,
    "reviewed_by" = auth.uid(),
    "reviewed_at" = now(),
    "updated_at" = now()
  where x."id" = review_form_submission.submission_id
  returning * into v_row;
  perform "better_supabase".emit_event('form_submission.reviewed', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id", 'status', v_row."status"), 'form-submissions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
  perform better_supabase.audit_event(
    event_type => 'form_submission.reviewed',
    category => 'data',
    target_type => 'form_submission',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at", 'score', v_row."score", 'maxScore', v_row."max_score", 'passed', v_row."passed");
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_form_submission"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_form_submission"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_form_submissions"(uuid, text, integer, timestamp WITH time zone, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_form_submissions"(uuid, text, integer, timestamp WITH time zone, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_form_submission"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_form_submission"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_form_submission"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_form_submission"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_form_submission"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_form_submission"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_form_submissions"(uuid, text, integer, timestamp WITH time zone, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_form_submissions"(uuid, text, integer, timestamp WITH time zone, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_form_submission"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_form_submission"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_form_submission"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_form_submission"(uuid) TO "authenticated", "service_role";
