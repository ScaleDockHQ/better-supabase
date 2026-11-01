SET local check_function_bodies = off;

DROP POLICY "appraisal_reviews_read" ON "better_supabase"."appraisal_reviews";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."appraisal_reviews";

CREATE TABLE "better_supabase"."appraisal_competencies" (
  "id"        uuid         NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id" uuid         NOT NULL,
  "cycle_id"  uuid         NOT NULL,
  "key"       text         NOT NULL,
  "name"      text         NOT NULL,
  "weight"    numeric(6,2) NOT NULL DEFAULT 1,
  "position"  integer      NOT NULL DEFAULT 0,
  CONSTRAINT "appraisal_competencies_cycle_id_key_key" UNIQUE (cycle_id, key),
  CONSTRAINT "appraisal_competencies_key_check" CHECK ((key ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "appraisal_competencies_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "appraisal_competencies_pkey" PRIMARY KEY (id),
  CONSTRAINT "appraisal_competencies_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "appraisal_competencies_weight_check" CHECK (((weight > (0)::numeric) AND (weight <= (1000)::numeric)))
);

ALTER TABLE "better_supabase"."appraisal_competencies"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."appraisal_review_ratings" (
  "id"            uuid     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid     NOT NULL,
  "review_id"     uuid     NOT NULL,
  "competency_id" uuid     NOT NULL,
  "rating"        smallint NOT NULL,
  "comment"       text,
  CONSTRAINT "appraisal_review_ratings_comment_check" CHECK (((comment IS NULL) OR (length(comment) <= 2000))),
  CONSTRAINT "appraisal_review_ratings_pkey" PRIMARY KEY (id),
  CONSTRAINT "appraisal_review_ratings_rating_check" CHECK (((rating >= 1) AND (rating <= 5))),
  CONSTRAINT "appraisal_review_ratings_review_id_competency_id_key" UNIQUE (review_id, competency_id)
);

ALTER TABLE "better_supabase"."appraisal_review_ratings"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."appraisal_calibrations"
  ADD COLUMN "competency_ratings" jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE "better_supabase"."appraisal_cycles"
  ADD COLUMN "anonymity" text NOT NULL DEFAULT 'subject'::text;

ALTER TABLE "better_supabase"."appraisal_cycles"
  ADD COLUMN "share_feedback" boolean NOT NULL DEFAULT false;

ALTER TABLE "better_supabase"."appraisals"
  ADD COLUMN "calibrated_competencies" jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION api.appraisal_review_hidden (
  review_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."appraisal_review_hidden"($1) $function$;

CREATE OR REPLACE FUNCTION api.calibrate_appraisal_competencies (
  appraisal_id uuid,
  competencies jsonb,
  reason       text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."calibrate_appraisal_competencies"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_appraisal_competencies (
  cycle_id     uuid,
  competencies jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_appraisal_competencies"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.appraisal_json (
  appraisal_id uuid,
  all_reviews  boolean
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cycleId', x."cycle_id",
    'subjectUserId', x."subject_user_id", 'managerId', x."manager_id", 'status', x."status",
    'rating', x."rating"::text, 'calibratedRating', x."calibrated_rating", 'approvalId', x."approval_id",
    'signedOffAt', x."signed_off_at", 'signedOffBy', x."signed_off_by", 'createdAt', x."created_at",
    'rubric', coalesce((
      select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position")
      from "better_supabase"."appraisal_competencies" w where w."cycle_id" = x."cycle_id"
    ), '[]'::jsonb),
    'competencies', case when appraisal_json.all_reviews or (x."subject_user_id" = auth.uid() and x."status" = 'signed_off'
      and (select z."share_feedback" from "better_supabase"."appraisal_cycles" z where z."id" = x."cycle_id")) then coalesce((
      select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight",
        'average', (
          select round(avg(z."rating"), 2)::text from "better_supabase"."appraisal_review_ratings" z join "better_supabase"."appraisal_reviews" v on v."id" = z."review_id"
          where z."competency_id" = w."id" and v."appraisal_id" = x."id" and v."submitted_at" is not null
        ),
        'calibrated', x."calibrated_competencies" -> w."key") order by w."position")
      from "better_supabase"."appraisal_competencies" w where w."cycle_id" = x."cycle_id"
    ), '[]'::jsonb) else '[]'::jsonb end,
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id",
        'reviewerId', case when "better_supabase"."appraisal_review_hidden"(y."id") then null else y."reviewer_id" end,
        'kind', y."kind", 'rating', y."rating", 'comments', y."comments", 'submissionId', y."submission_id", 'submittedAt', y."submitted_at",
        'ratings', coalesce((
          select jsonb_agg(jsonb_build_object('competency', w."key", 'rating', z."rating", 'comment', z."comment") order by w."position")
          from "better_supabase"."appraisal_review_ratings" z join "better_supabase"."appraisal_competencies" w on w."id" = z."competency_id"
          where z."review_id" = y."id"
        ), '[]'::jsonb))
        order by y."kind", y."id")
      from "better_supabase"."appraisal_reviews" y
      where y."appraisal_id" = x."id"
        and (appraisal_json.all_reviews or y."reviewer_id" = auth.uid() or ((x."subject_user_id" = auth.uid() and x."status" = 'signed_off'
      and (select z."share_feedback" from "better_supabase"."appraisal_cycles" z where z."id" = x."cycle_id")) and y."submitted_at" is not null))
    ), '[]'::jsonb),
    'calibrations', coalesce((
      select jsonb_agg(jsonb_build_object('id', z."id", 'fromRating', z."from_rating"::text, 'toRating', z."to_rating",
        'competencyRatings', z."competency_ratings",
        'reason', z."reason", 'calibratedBy', z."calibrated_by", 'calibratedAt', z."calibrated_at")
        order by z."calibrated_at", z."id")
      from "better_supabase"."appraisal_calibrations" z where z."appraisal_id" = x."id" and appraisal_json.all_reviews
    ), '[]'::jsonb),
    'goalIds', coalesce((
      select jsonb_agg(w."goal_id" order by w."goal_id") from "better_supabase"."appraisal_goals" w where w."appraisal_id" = x."id"
    ), '[]'::jsonb))
  from "better_supabase"."appraisals" x where x."id" = appraisal_json.appraisal_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.appraisal_review_hidden (
  review_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_review "better_supabase"."appraisal_reviews";
  v_row "better_supabase"."appraisals";
  v_mode text;
begin
  select * into v_review from "better_supabase"."appraisal_reviews" x where x."id" = appraisal_review_hidden.review_id;
  if not found then
    return true;
  end if;
  if v_review."kind" <> 'peer' or v_review."reviewer_id" is not distinct from auth.uid() or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return false;
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = v_review."appraisal_id";
  select x."anonymity" into v_mode from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  return case v_mode
    when 'none' then false
    when 'subject' then coalesce(v_row."subject_user_id" = auth.uid(), false)
    else true
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.appraisal_score (
  appraisal_id uuid,
  overrides    jsonb DEFAULT '{}'::jsonb
)
  RETURNS numeric
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when exists (select 1 from "better_supabase"."appraisal_competencies" w join "better_supabase"."appraisals" p on p."cycle_id" = w."cycle_id" where p."id" = appraisal_score.appraisal_id) then (
      select round(sum(w."weight" * coalesce((appraisal_score.overrides ->> w."key")::numeric, m.average))
          / sum(w."weight"), 2)
      from "better_supabase"."appraisal_competencies" w
      join "better_supabase"."appraisals" p on p."cycle_id" = w."cycle_id"
      cross join lateral (
        select avg(z."rating") as average
        from "better_supabase"."appraisal_review_ratings" z join "better_supabase"."appraisal_reviews" v on v."id" = z."review_id"
        where z."competency_id" = w."id" and v."appraisal_id" = p."id" and v."submitted_at" is not null
      ) m
      where p."id" = appraisal_score.appraisal_id
        and coalesce((appraisal_score.overrides ->> w."key")::numeric, m.average) is not null
    )
    else (
      select round(avg(v."rating"), 2) from "better_supabase"."appraisal_reviews" v
      where v."appraisal_id" = appraisal_score.appraisal_id and v."submitted_at" is not null
    )
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.appraisal_write_competencies (
  cycle_id uuid,
  items    jsonb
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_cycle "better_supabase"."appraisal_cycles";
  v_item jsonb;
  v_position bigint;
  v_key text;
  v_name text;
  v_weight numeric;
begin
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = appraisal_write_competencies.cycle_id;
  if appraisal_write_competencies.items is null or jsonb_typeof(appraisal_write_competencies.items) = 'null' then
    return;
  end if;
  if jsonb_typeof(appraisal_write_competencies.items) <> 'array' or jsonb_array_length(appraisal_write_competencies.items) > 20 then
    raise exception 'competencies is a list of at most 20 items' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  delete from "better_supabase"."appraisal_competencies" x where x."cycle_id" = v_cycle."id";
  for v_item, v_position in
    select e, o from jsonb_array_elements(appraisal_write_competencies.items) with ordinality as t(e, o)
  loop
    begin
      v_key := trim(v_item ->> 'key');
      v_name := trim(v_item ->> 'name');
      v_weight := coalesce((v_item ->> 'weight')::numeric, 1);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'a competency weight is a number' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end;
    if v_key is null or v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      raise exception 'a competency key is lowercase letters, digits and underscores, starting with a letter' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if coalesce(length(v_name), 0) not between 1 and 200 then
      raise exception 'a competency needs a name of 1 to 200 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_weight <= 0 or v_weight > 1000 then
      raise exception 'a competency weight is above 0 and at most 1000' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    begin
      insert into "better_supabase"."appraisal_competencies" ("tenant_id", "cycle_id", "key", "name", "weight", "position")
      values (v_cycle."tenant_id", v_cycle."id", v_key, v_name, v_weight, v_position);
    exception when unique_violation then
      raise exception 'a competency key appears once' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calibrate_appraisal_competencies (
  appraisal_id uuid,
  competencies jsonb,
  reason       text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_reason text := nullif(trim(calibrate_appraisal_competencies.reason), '');
  v_item record;
  v_merged jsonb;
  v_rating numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = calibrate_appraisal_competencies.appraisal_id for update;
  if not found then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to calibrate appraisals' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if v_cycle."status" <> 'open' or v_row."status" not in ('reviewed', 'calibrated') then
    raise exception 'only a reviewed appraisal in an open cycle is calibrated' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if jsonb_typeof(calibrate_appraisal_competencies.competencies) is distinct from 'object'
    or calibrate_appraisal_competencies.competencies = '{}'::jsonb then
    raise exception 'competencies is an object of competency ratings' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    raise exception 'a calibration needs a reason of up to 2000 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  for v_item in select e.key, e.value from jsonb_each(calibrate_appraisal_competencies.competencies) e loop
    if not exists (select 1 from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id" and w."key" = v_item.key) then
      raise exception 'no such competency in this cycle''s rubric' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if jsonb_typeof(v_item.value) <> 'number' or v_item.value::text !~ '^[1-5]$' then
      raise exception 'a competency rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
  end loop;
  v_merged := v_row."calibrated_competencies" || calibrate_appraisal_competencies.competencies;
  v_rating := "better_supabase"."appraisal_score"(v_row."id", v_merged);
  insert into "better_supabase"."appraisal_calibrations" ("tenant_id", "appraisal_id", "from_rating", "to_rating", "competency_ratings", "reason", "calibrated_by")
  values (v_row."tenant_id", v_row."id", coalesce(v_row."calibrated_rating"::numeric, v_row."rating"), round(v_rating)::integer,
    calibrate_appraisal_competencies.competencies, v_reason, auth.uid());
  update "better_supabase"."appraisals" x
  set "calibrated_competencies" = v_merged, "calibrated_rating" = round(v_rating)::integer,
    "status" = 'calibrated', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('appraisal.calibrated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id", 'status', v_row."status", 'rating', v_row."calibrated_rating"), 'appraisals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.calibrated',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_row."id"::text,
    summary => 'appraisal calibrated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id", 'status', v_row."status", 'rating', v_row."calibrated_rating")
  );
  perform "better_supabase"."appraisal_step"(v_row."id", 'calibration');
  return "better_supabase"."appraisal_json"(v_row."id", true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_appraisal_cycle (
  cycle_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_cycle "better_supabase"."appraisal_cycles";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = close_appraisal_cycle.cycle_id for update;
  if not found then
    raise exception 'no such review cycle' using errcode = 'P0002', hint = 'APPRAISALS_CYCLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_cycle."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_cycle."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_cycle."status" <> 'open' then
    raise exception 'only an open cycle closes' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if exists (select 1 from "better_supabase"."appraisals" x where x."cycle_id" = v_cycle."id" and x."status" <> 'signed_off') then
    raise exception 'every appraisal in the cycle must be signed off first' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  update "better_supabase"."appraisal_cycles" x set "status" = 'closed', "closed_at" = now()
  where x."id" = v_cycle."id"
  returning * into v_cycle;
  perform "better_supabase".emit_event('appraisal_cycle.closed', jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status"), 'appraisal-cycles/' || v_cycle."id"::text, (v_cycle."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal_cycle.closed',
    category => 'data',
    target_type => 'appraisal_cycle',
    record_id => v_cycle."id"::text,
    target_label => v_cycle."name",
    summary => 'review cycle closed',
    tenant => (v_cycle."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status")
  );
  return jsonb_build_object('id', v_cycle."id", 'organizationId', v_cycle."tenant_id", 'name', v_cycle."name", 'startsOn', v_cycle."starts_on", 'endsOn', v_cycle."ends_on", 'program', v_cycle."program", 'status', v_cycle."status", 'anonymity', v_cycle."anonymity", 'shareFeedback', v_cycle."share_feedback", 'openedAt', v_cycle."opened_at", 'closedAt', v_cycle."closed_at", 'createdAt', v_cycle."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_appraisal_cycle (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisal_cycles";
  v_name text;
  v_starts date;
  v_ends date;
  v_program text;
  v_anonymity text;
  v_share boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_appraisal_cycle.tenant is not null and coalesce(better_supabase.can('tenant', create_appraisal_cycle.tenant, 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if jsonb_typeof(create_appraisal_cycle.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  begin
    v_name := trim(create_appraisal_cycle.input ->> 'name');
    v_starts := (create_appraisal_cycle.input ->> 'startsOn')::date;
    v_ends := (create_appraisal_cycle.input ->> 'endsOn')::date;
    v_program := nullif(trim(create_appraisal_cycle.input ->> 'program'), '');
    v_anonymity := coalesce(nullif(trim(create_appraisal_cycle.input ->> 'anonymity'), ''), 'subject');
    v_share := coalesce((create_appraisal_cycle.input ->> 'shareFeedback')::boolean, false);
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'startsOn and endsOn are dates' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  when invalid_text_representation then
    raise exception 'shareFeedback is true or false' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end;
  if v_anonymity not in ('none', 'subject', 'all') then
    raise exception 'anonymity is none, subject or all' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if coalesce(length(v_name), 0) not between 1 and 200 then
    raise exception 'a cycle needs a name of 1 to 200 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_starts is null or v_ends is null or v_ends < v_starts then
    raise exception 'a cycle needs a start date and an end date on or after it' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."enrollment_programs" x
    where x."tenant_id" = create_appraisal_cycle.tenant and x."key" = v_program
  ) then
    raise exception 'no such enrollment program' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_appraisal_cycle_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_appraisal_cycle.tenant, create_appraisal_cycle.input;
    end if;
  end;
  insert into "better_supabase"."appraisal_cycles" ("tenant_id", "name", "starts_on", "ends_on", "program", "anonymity", "share_feedback", "created_by")
  values (create_appraisal_cycle.tenant, v_name, v_starts, v_ends, v_program, v_anonymity, v_share, auth.uid())
  returning * into v_row;
  perform "better_supabase"."appraisal_write_competencies"(v_row."id", create_appraisal_cycle.input -> 'competencies');
  perform "better_supabase".emit_event('appraisal_cycle.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status"), 'appraisal-cycles/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal_cycle.created',
    category => 'data',
    target_type => 'appraisal_cycle',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'review cycle created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_appraisal_cycle_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'program', v_row."program", 'status', v_row."status", 'anonymity', v_row."anonymity", 'shareFeedback', v_row."share_feedback", 'openedAt', v_row."opened_at", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_row."id"), '[]'::jsonb));
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
    ('user', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_chat_participants', '"better_supabase"."ai_chat_participants"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leases', '"better_supabase"."leases"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.courses', '"better_supabase"."courses"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.sequences', '"better_supabase"."sequences"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'subject_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'calibrated_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'assignee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'submitted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'opened_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'counted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'decided_by', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversation_events', '"better_supabase"."inbox_conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_deliveries', '"better_supabase"."inbox_message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_inbound_events', '"better_supabase"."inbox_inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.inbox_message_templates', '"better_supabase"."inbox_message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, array['token_hash', 'password_hash']::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_records', '"better_supabase"."import_records"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_price_lists', '"better_supabase"."catalog_price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_categories', '"better_supabase"."catalog_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_storefronts', '"better_supabase"."catalog_storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_identifiers', '"better_supabase"."product_identifiers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_relations', '"better_supabase"."product_relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_items', '"better_supabase"."supplier_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_item_mappings', '"better_supabase"."supplier_item_mappings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_groups', '"better_supabase"."discount_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_group_parties', '"better_supabase"."discount_group_parties"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_rules', '"better_supabase"."discount_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_event_alarms', '"better_supabase"."calendar_event_alarms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.purchase_requisitions', '"better_supabase"."purchase_requisitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisition_lines', '"better_supabase"."purchase_requisition_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipts', '"better_supabase"."inventory_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipt_lines', '"better_supabase"."inventory_receipt_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_counts', '"better_supabase"."stock_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_count_lines', '"better_supabase"."stock_count_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_shipping_rates', '"better_supabase"."order_shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillments', '"better_supabase"."order_fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillment_lines', '"better_supabase"."order_fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.form_answer_keys', '"better_supabase"."form_answer_keys"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedule_runs', '"better_supabase"."template_schedule_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_kinds', '"better_supabase"."case_kinds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cases', '"better_supabase"."cases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_actions', '"better_supabase"."case_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_terms', '"better_supabase"."payment_terms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_delivery_preferences', '"better_supabase"."document_delivery_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_identities', '"better_supabase"."person_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_levels', '"better_supabase"."invoice_dunning_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_runs', '"better_supabase"."invoice_dunning_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_run_items', '"better_supabase"."invoice_dunning_run_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_history', '"better_supabase"."invoice_dunning_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_allocations', '"better_supabase"."invoice_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_line_sources', '"better_supabase"."invoice_line_sources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_depreciations', '"better_supabase"."asset_depreciations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leases', '"better_supabase"."leases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_charges', '"better_supabase"."lease_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_categories', '"better_supabase"."expense_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_lines', '"better_supabase"."expense_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_funds', '"better_supabase"."donation_funds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pledges', '"better_supabase"."pledges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_receipts', '"better_supabase"."donation_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donations', '"better_supabase"."donations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_route_stops', '"better_supabase"."dispatch_route_stops"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipments', '"better_supabase"."shipments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_packages', '"better_supabase"."shipment_packages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_tracking_events', '"better_supabase"."shipment_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_lines', '"better_supabase"."shipment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.intrastat_lines', '"better_supabase"."intrastat_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.compliance_policies', '"better_supabase"."compliance_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_components', '"better_supabase"."incident_status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_component_history', '"better_supabase"."incident_status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortem_actions', '"better_supabase"."incident_postmortem_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_pages', '"better_supabase"."incident_status_pages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.courses', '"better_supabase"."courses"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_modules', '"better_supabase"."course_modules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lessons', '"better_supabase"."course_lessons"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_summaries', '"better_supabase"."thread_summaries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.mail_threads', '"better_supabase"."mail_threads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_messages', '"better_supabase"."mail_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracked_links', '"better_supabase"."mail_tracked_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracking_events', '"better_supabase"."mail_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segments', '"better_supabase"."segments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segment_members', '"better_supabase"."segment_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queues', '"better_supabase"."assignment_queues"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrichments', '"better_supabase"."enrichments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshots', '"better_supabase"."forecast_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshot_deals', '"better_supabase"."forecast_snapshot_deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_changes', '"better_supabase"."field_changes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequences', '"better_supabase"."sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_types', '"better_supabase"."qualification_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_requirements', '"better_supabase"."qualification_requirements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualifications', '"better_supabase"."qualifications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_matrices', '"better_supabase"."risk_matrices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risks', '"better_supabase"."risks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_templates', '"better_supabase"."shift_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shifts', '"better_supabase"."shifts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_codes', '"better_supabase"."tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_rates', '"better_supabase"."tax_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_tax_lines', '"better_supabase"."invoice_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_returns', '"better_supabase"."tax_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eu_sales_list_lines', '"better_supabase"."eu_sales_list_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_settings', '"better_supabase"."accounting_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_accounts', '"better_supabase"."accounting_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_account_roles', '"better_supabase"."accounting_account_roles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_journals', '"better_supabase"."accounting_journals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_periods', '"better_supabase"."accounting_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entries', '"better_supabase"."accounting_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entry_lines', '"better_supabase"."accounting_entry_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimensions', '"better_supabase"."accounting_dimensions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimension_values', '"better_supabase"."accounting_dimension_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_fx_rates', '"better_supabase"."accounting_fx_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_opening_balances', '"better_supabase"."accounting_opening_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observation_definitions', '"better_supabase"."observation_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observations', '"better_supabase"."observations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medications', '"better_supabase"."medications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_orders', '"better_supabase"."medication_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_administrations', '"better_supabase"."medication_administrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plans', '"better_supabase"."care_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_problems', '"better_supabase"."care_plan_problems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_goals', '"better_supabase"."care_plan_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_actions', '"better_supabase"."care_plan_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_programs', '"better_supabase"."inspection_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspections', '"better_supabase"."inspections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_findings', '"better_supabase"."inspection_findings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.boms', '"better_supabase"."boms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_centers', '"better_supabase"."work_centers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_operations', '"better_supabase"."bom_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_components', '"better_supabase"."bom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_orders', '"better_supabase"."production_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_order_operations', '"better_supabase"."production_order_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_consumptions', '"better_supabase"."production_consumptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_accounts', '"better_supabase"."bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_rules', '"better_supabase"."bank_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_statements', '"better_supabase"."bank_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_transactions', '"better_supabase"."bank_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_matches', '"better_supabase"."bank_matches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batches', '"better_supabase"."payment_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batch_items', '"better_supabase"."payment_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meetings', '"better_supabase"."meetings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_agenda_items', '"better_supabase"."meeting_agenda_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_decisions', '"better_supabase"."meeting_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_action_items', '"better_supabase"."meeting_action_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entities', '"better_supabase"."legal_entities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entity_settings', '"better_supabase"."legal_entity_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_products', '"better_supabase"."funding_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_awards', '"better_supabase"."funding_awards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_deliveries', '"better_supabase"."funding_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claims', '"better_supabase"."funding_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_runs', '"better_supabase"."payroll_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plans', '"better_supabase"."maintenance_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plan_parts', '"better_supabase"."maintenance_plan_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meters', '"better_supabase"."maintenance_meters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_renditions', '"better_supabase"."dam_renditions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_templates', '"better_supabase"."document_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_text_blocks', '"better_supabase"."document_text_blocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_methods', '"better_supabase"."lims_methods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_competencies', '"better_supabase"."appraisal_competencies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_review_ratings', '"better_supabase"."appraisal_review_ratings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_goals', '"better_supabase"."appraisal_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lines', '"better_supabase"."pick_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.count_plans', '"better_supabase"."count_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_lines', '"better_supabase"."rfq_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_suppliers', '"better_supabase"."rfq_suppliers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quote_lines', '"better_supabase"."rfq_quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tills', '"better_supabase"."tills"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_rules', '"better_supabase"."care_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_appraisal_cycles (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_appraisal_cycles.tenant is not null and coalesce(better_supabase.can('tenant', list_appraisal_cycles.tenant, 'appraisals.read'), false))) then
    raise exception 'not allowed to read review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'program', x."program", 'status', x."status", 'anonymity', x."anonymity", 'shareFeedback', x."share_feedback", 'openedAt', x."opened_at", 'closedAt', x."closed_at", 'createdAt', x."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = x."id"), '[]'::jsonb)) order by x."starts_on" desc, x."id")
    from "better_supabase"."appraisal_cycles" x where x."tenant_id" = list_appraisal_cycles.tenant
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_appraisal_cycle (
  cycle_id    uuid,
  assignments jsonb DEFAULT '[]'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_cycle "better_supabase"."appraisal_cycles";
  v_appraisal "better_supabase"."appraisals";
  v_item jsonb;
  v_subject uuid;
  v_manager uuid;
  v_peer text;
  v_peers uuid[];
  v_version integer;
  v_steps text[];
  v_made integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = open_appraisal_cycle.cycle_id for update;
  if not found then
    raise exception 'no such review cycle' using errcode = 'P0002', hint = 'APPRAISALS_CYCLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_cycle."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_cycle."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_cycle."status" = 'closed' then
    raise exception 'a closed cycle can''t be opened again' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if jsonb_typeof(open_appraisal_cycle.assignments) is distinct from 'array' then
    raise exception 'assignments must be a list' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  for v_item in select e from jsonb_array_elements(open_appraisal_cycle.assignments) e loop
    begin
      v_subject := (v_item ->> 'subjectUserId')::uuid;
      v_manager := nullif(v_item ->> 'managerId', '')::uuid;
      v_peers := '{}';
      if v_item ? 'peerIds' then
        for v_peer in select p from jsonb_array_elements_text(v_item -> 'peerIds') p loop
          v_peers := v_peers || v_peer::uuid;
        end loop;
      end if;
    exception when invalid_text_representation or invalid_parameter_value or null_value_not_allowed then
      raise exception 'subjectUserId, managerId and peerIds are user ids' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end;
    if v_subject is null then
      raise exception 'an assignment needs a subjectUserId' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_manager = v_subject then
      raise exception 'a person can''t be their own manager' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_subject = any(v_peers) or v_manager = any(v_peers) then
      raise exception 'a peer is neither the person nor the manager' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    insert into "better_supabase"."appraisals" ("tenant_id", "cycle_id", "subject_user_id", "manager_id")
    values (v_cycle."tenant_id", v_cycle."id", v_subject, v_manager)
    on conflict do nothing
    returning * into v_appraisal;
    if v_appraisal."id" is not null then
      v_made := v_made + 1;
      insert into "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id", "reviewer_id", "kind")
      values (v_appraisal."tenant_id", v_appraisal."id", v_subject, 'self');
      if v_manager is not null then
        insert into "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id", "reviewer_id", "kind")
        values (v_appraisal."tenant_id", v_appraisal."id", v_manager, 'manager');
      end if;
      insert into "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id", "reviewer_id", "kind")
      select distinct v_appraisal."tenant_id", v_appraisal."id", p, 'peer' from unnest(v_peers) p;
      if v_cycle."program" is not null then
        select x."version", array(select s ->> 'id' from jsonb_array_elements(x."steps") s)
        into v_version, v_steps
        from "better_supabase"."enrollment_programs" x
        where x."tenant_id" = v_cycle."tenant_id" and x."key" = v_cycle."program";
        perform "better_supabase"."enrollment_ensure"(v_cycle."tenant_id", v_cycle."program", v_version, v_steps,
          'appraisal', v_appraisal."id"::text, auth.uid());
      end if;
      perform "better_supabase".emit_event('appraisal.created', jsonb_build_object('organizationId', v_appraisal."tenant_id", 'id', v_appraisal."id", 'cycleId', v_appraisal."cycle_id", 'subjectUserId', v_appraisal."subject_user_id", 'status', v_appraisal."status"), 'appraisals/' || v_appraisal."id"::text, (v_appraisal."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.created',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_appraisal."id"::text,
    summary => 'appraisal created',
    tenant => (v_appraisal."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_appraisal."tenant_id", 'id', v_appraisal."id", 'cycleId', v_appraisal."cycle_id", 'subjectUserId', v_appraisal."subject_user_id", 'status', v_appraisal."status")
  );
    end if;
    v_appraisal := null;
  end loop;
  update "better_supabase"."appraisal_cycles" x set "status" = 'open', "opened_at" = coalesce(x."opened_at", now())
  where x."id" = v_cycle."id"
  returning * into v_cycle;
  if v_made > 0 or v_cycle."opened_at" = now() then
    perform "better_supabase".emit_event('appraisal_cycle.opened', jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status"), 'appraisal-cycles/' || v_cycle."id"::text, (v_cycle."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal_cycle.opened',
    category => 'data',
    target_type => 'appraisal_cycle',
    record_id => v_cycle."id"::text,
    target_label => v_cycle."name",
    summary => 'review cycle opened',
    tenant => (v_cycle."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status")
  );
  end if;
  return jsonb_build_object('id', v_cycle."id", 'organizationId', v_cycle."tenant_id", 'name', v_cycle."name", 'startsOn', v_cycle."starts_on", 'endsOn', v_cycle."ends_on", 'program', v_cycle."program", 'status', v_cycle."status", 'anonymity', v_cycle."anonymity", 'shareFeedback', v_cycle."share_feedback", 'openedAt', v_cycle."opened_at", 'closedAt', v_cycle."closed_at", 'createdAt', v_cycle."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id"), '[]'::jsonb)) || jsonb_build_object('appraisalsCreated', v_made);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_appraisal_competencies (
  cycle_id     uuid,
  competencies jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_cycle "better_supabase"."appraisal_cycles";
begin
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = set_appraisal_competencies.cycle_id for update;
  if not found then
    raise exception 'no such review cycle' using errcode = 'P0002', hint = 'APPRAISALS_CYCLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_cycle."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_cycle."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_cycle."status" <> 'draft' then
    raise exception 'the rubric of a cycle is fixed once it is open' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if set_appraisal_competencies.competencies is null or jsonb_typeof(set_appraisal_competencies.competencies) <> 'array' then
    raise exception 'competencies is a list' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  perform "better_supabase"."appraisal_write_competencies"(v_cycle."id", set_appraisal_competencies.competencies);
  return jsonb_build_object('id', v_cycle."id", 'organizationId', v_cycle."tenant_id", 'name', v_cycle."name", 'startsOn', v_cycle."starts_on", 'endsOn', v_cycle."ends_on", 'program', v_cycle."program", 'status', v_cycle."status", 'anonymity', v_cycle."anonymity", 'shareFeedback', v_cycle."share_feedback", 'openedAt', v_cycle."opened_at", 'closedAt', v_cycle."closed_at", 'createdAt', v_cycle."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sign_off_appraisal (
  appraisal_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_payload jsonb;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = sign_off_appraisal.appraisal_id for update;
  if not found then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to sign off appraisals' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if v_cycle."status" <> 'open' or v_row."status" not in ('reviewed', 'calibrated') then
    raise exception 'only a reviewed or calibrated appraisal in an open cycle is signed off' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  v_payload := jsonb_build_object('appraisalId', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id",
    'rating', coalesce(v_row."calibrated_rating"::numeric, v_row."rating")::text,
    'competencies', "better_supabase"."appraisal_json"(v_row."id", true) -> 'competencies');
  v_approval := "better_supabase"."open_approval"(
    v_row."tenant_id", 'appraisal', v_row."id"::text, 'sign_off',
    coalesce("better_supabase"."approval_effective_policy"(v_row."tenant_id", 'appraisal', 'sign_off', v_payload), '{"steps":[{"approvers":{"permission":"appraisals.manage"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb),
    null, v_payload
  );
  update "better_supabase"."appraisals" x
  set "status" = 'awaiting_signoff', "approval_id" = (v_approval ->> 'id')::uuid, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return "better_supabase"."appraisal_json"(v_row."id", true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_appraisal_review (
  review_id uuid,
  input     jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_review "better_supabase"."appraisal_reviews";
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_rating integer;
  v_comments text;
  v_submission uuid;
  v_left integer;
  v_rubric integer;
  v_item jsonb;
  v_key text;
  v_value integer;
  v_note text;
  v_comp "better_supabase"."appraisal_competencies";
  v_keys text[] := '{}';
  v_sum numeric := 0;
  v_weights numeric := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_review from "better_supabase"."appraisal_reviews" x where x."id" = submit_appraisal_review.review_id for update;
  if not found then
    raise exception 'no such review' using errcode = 'P0002', hint = 'APPRAISALS_REVIEW_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = v_review."appraisal_id" for update;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_review."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_review."tenant_id", 'appraisals.review'), false))) and v_review."reviewer_id" = auth.uid(), false) then
    raise exception 'only the assigned reviewer submits this review' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_review."submitted_at" is not null then
    raise exception 'this review is already submitted' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if v_cycle."status" <> 'open' or v_row."status" <> 'pending' then
    raise exception 'reviews are open while the cycle is open and the appraisal is pending' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if jsonb_typeof(submit_appraisal_review.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  select count(*) into v_rubric from "better_supabase"."appraisal_competencies" x where x."cycle_id" = v_cycle."id";
  begin
    v_rating := (submit_appraisal_review.input ->> 'rating')::integer;
    v_comments := nullif(trim(submit_appraisal_review.input ->> 'comments'), '');
    v_submission := nullif(submit_appraisal_review.input ->> 'submissionId', '')::uuid;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'rating is a whole number and submissionId an id' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end;
  if length(v_comments) > 10000 then
    raise exception 'comments are at most 10000 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_rubric = 0 then
    if submit_appraisal_review.input ? 'ratings' then
      raise exception 'this cycle has no rubric; send a rating' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_rating is null or v_rating not between 1 and 5 then
      raise exception 'the rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
  else
    if submit_appraisal_review.input ? 'rating' then
      raise exception 'this cycle has a rubric; send a rating for each competency' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if jsonb_typeof(submit_appraisal_review.input -> 'ratings') is distinct from 'array' then
      raise exception 'ratings is a list of { competency, rating, comment }' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
  end if;
  update "better_supabase"."appraisal_reviews" x
  set "rating" = coalesce(v_rating, 1), "comments" = v_comments, "submission_id" = v_submission, "submitted_at" = now()
  where x."id" = v_review."id"
  returning * into v_review;
  if v_rubric > 0 then
    for v_item in select e from jsonb_array_elements(submit_appraisal_review.input -> 'ratings') e loop
      begin
        v_key := v_item ->> 'competency';
        v_value := (v_item ->> 'rating')::integer;
        v_note := nullif(trim(v_item ->> 'comment'), '');
      exception when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'a competency rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end;
      select * into v_comp from "better_supabase"."appraisal_competencies" x where x."cycle_id" = v_cycle."id" and x."key" = v_key;
      if not found then
        raise exception 'no such competency in this cycle''s rubric' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end if;
      if v_value is null or v_value not between 1 and 5 then
        raise exception 'a competency rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end if;
      if length(v_note) > 2000 then
        raise exception 'a competency comment is at most 2000 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end if;
      if v_key = any(v_keys) then
        raise exception 'rate each competency once' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end if;
      v_keys := v_keys || v_key;
      v_sum := v_sum + v_comp."weight" * v_value;
      v_weights := v_weights + v_comp."weight";
      insert into "better_supabase"."appraisal_review_ratings" ("tenant_id", "review_id", "competency_id", "rating", "comment")
      values (v_review."tenant_id", v_review."id", v_comp."id", v_value, v_note);
    end loop;
    if cardinality(v_keys) <> v_rubric then
      raise exception 'rate every competency of the rubric' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    update "better_supabase"."appraisal_reviews" x
    set "rating" = round(v_sum / v_weights)::integer
    where x."id" = v_review."id"
    returning * into v_review;
  end if;
  perform "better_supabase".emit_event('appraisal_review.submitted', jsonb_build_object('organizationId', v_review."tenant_id", 'id', v_review."id", 'appraisalId', v_review."appraisal_id", 'reviewerId', case when v_review."kind" = 'peer' and (select y."anonymity" from "better_supabase"."appraisal_cycles" y join "better_supabase"."appraisals" p on p."cycle_id" = y."id" where p."id" = v_review."appraisal_id") <> 'none' then null else v_review."reviewer_id" end, 'kind', v_review."kind", 'rating', v_review."rating"), 'appraisals/' || v_review."appraisal_id"::text, (v_review."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal_review.submitted',
    category => 'data',
    target_type => 'appraisal_review',
    record_id => v_review."id"::text,
    summary => 'appraisal review submitted',
    tenant => (v_review."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_review."tenant_id", 'id', v_review."id", 'appraisalId', v_review."appraisal_id", 'reviewerId', case when v_review."kind" = 'peer' and (select y."anonymity" from "better_supabase"."appraisal_cycles" y join "better_supabase"."appraisals" p on p."cycle_id" = y."id" where p."id" = v_review."appraisal_id") <> 'none' then null else v_review."reviewer_id" end, 'kind', v_review."kind", 'rating', v_review."rating")
  );
  perform "better_supabase"."appraisal_step"(v_row."id", case v_review."kind" when 'self' then 'self_review' when 'manager' then 'manager_review' end);
  select count(*) into v_left from "better_supabase"."appraisal_reviews" x
  where x."appraisal_id" = v_row."id" and x."submitted_at" is null;
  update "better_supabase"."appraisals" x
  set "rating" = "better_supabase"."appraisal_score"(x."id", '{}'::jsonb),
    "status" = case when v_left = 0 then 'reviewed' else x."status" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_review."kind" = 'peer' and not exists (
    select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = v_row."id" and z."kind" = 'peer' and z."submitted_at" is null
  ) then
    perform "better_supabase"."appraisal_step"(v_row."id", 'peer_review');
  end if;
  return "better_supabase"."appraisal_json"(v_row."id", (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.read'), false))));
end;
$function$;

ALTER TABLE "better_supabase"."appraisal_calibrations"
  ADD CONSTRAINT "appraisal_calibrations_competency_ratings_check" CHECK ((jsonb_typeof(competency_ratings) = 'object'::text));

ALTER TABLE "better_supabase"."appraisal_competencies"
  ADD CONSTRAINT "appraisal_competencies_tenant_id_cycle_id_fkey" FOREIGN KEY (tenant_id, cycle_id) REFERENCES better_supabase.appraisal_cycles(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."appraisal_cycles"
  ADD CONSTRAINT "appraisal_cycles_anonymity_check" CHECK ((anonymity = ANY (ARRAY['none'::text, 'subject'::text, 'all'::text])));

ALTER TABLE "better_supabase"."appraisal_review_ratings"
  ADD CONSTRAINT "appraisal_review_ratings_tenant_id_competency_id_fkey" FOREIGN KEY (tenant_id, competency_id) REFERENCES better_supabase.appraisal_competencies(tenant_id, id)
    ON DELETE CASCADE;

ALTER TABLE "better_supabase"."appraisal_reviews"
  ADD CONSTRAINT "appraisal_reviews_tenant_id_id_key" UNIQUE (tenant_id, id);

ALTER TABLE "better_supabase"."appraisal_review_ratings"
  ADD CONSTRAINT "appraisal_review_ratings_tenant_id_review_id_fkey" FOREIGN KEY (tenant_id, review_id) REFERENCES better_supabase.appraisal_reviews(tenant_id, id)
    ON DELETE CASCADE;

ALTER TABLE "better_supabase"."appraisals"
  ADD CONSTRAINT "appraisals_calibrated_competencies_check" CHECK ((jsonb_typeof(calibrated_competencies) = 'object'::text));

CREATE INDEX appraisal_competencies_parent_idx ON better_supabase.appraisal_competencies USING btree (tenant_id, cycle_id, "position");

CREATE INDEX appraisal_review_ratings_competency_idx ON better_supabase.appraisal_review_ratings USING btree (tenant_id, competency_id);

CREATE INDEX appraisal_review_ratings_parent_idx ON better_supabase.appraisal_review_ratings USING btree (tenant_id, review_id);

CREATE POLICY "appraisal_competencies_read" ON "better_supabase"."appraisal_competencies"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('appraisals.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."appraisal_competencies"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."appraisal_competencies"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."appraisal_competencies"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('appraisals.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."appraisal_competencies"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "appraisal_review_ratings_read" ON "better_supabase"."appraisal_review_ratings"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('appraisals.read'::text) AS tenant_ids_with)) AND (NOT better_supabase.appraisal_review_hidden(review_id))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."appraisal_review_ratings"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."appraisal_review_ratings"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."appraisal_review_ratings"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('appraisals.read'::text) AS tenant_ids_with)) AND (NOT better_supabase.appraisal_review_hidden(review_id)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."appraisal_review_ratings"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "appraisal_reviews_read" ON "better_supabase"."appraisal_reviews"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('appraisals.read'::text) AS tenant_ids_with)) AND (NOT better_supabase.appraisal_review_hidden(id))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."appraisal_reviews"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('appraisals.read'::text) AS tenant_ids_with)) AND (NOT better_supabase.appraisal_review_hidden(id)))));

REVOKE ALL ON FUNCTION "api"."appraisal_review_hidden"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."appraisal_review_hidden"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."calibrate_appraisal_competencies"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."calibrate_appraisal_competencies"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_appraisal_competencies"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_appraisal_competencies"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."appraisal_review_hidden"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."appraisal_review_hidden"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."appraisal_score"(uuid, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."appraisal_write_competencies"(uuid, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."calibrate_appraisal_competencies"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."calibrate_appraisal_competencies"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_appraisal_competencies"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_appraisal_competencies"(uuid, jsonb) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."appraisal_competencies" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."appraisal_competencies" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."appraisal_review_ratings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."appraisal_review_ratings" TO "service_role";
