SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."shift_assignments" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "shift_id"    uuid                     NOT NULL,
  "user_id"     uuid                     NOT NULL,
  "status"      text                     NOT NULL DEFAULT 'assigned'::text,
  "starts_at"   timestamp with time zone NOT NULL,
  "ends_at"     timestamp with time zone NOT NULL,
  "assigned_by" uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "shift_assignments_pkey" PRIMARY KEY (id),
  CONSTRAINT "shift_assignments_shift_id_user_id_key" UNIQUE (shift_id, user_id),
  CONSTRAINT "shift_assignments_status_check" CHECK ((status = ANY (ARRAY['assigned'::text, 'requested'::text, 'released'::text]))),
  CONSTRAINT "shift_assignments_tenant_id_id_key" UNIQUE (tenant_id, id)
);

ALTER TABLE "better_supabase"."shift_assignments"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."shift_availability" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "on_date"    date                     NOT NULL,
  "from_time"  time without time zone,
  "until_time" time without time zone,
  "kind"       text                     NOT NULL,
  "note"       text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "shift_availability_check1" CHECK (((until_time IS NULL) OR (until_time > from_time))),
  CONSTRAINT "shift_availability_check" CHECK (((from_time IS NULL) = (until_time IS NULL))),
  CONSTRAINT "shift_availability_kind_check" CHECK ((kind = ANY (ARRAY['available'::text, 'unavailable'::text, 'preferred'::text]))),
  CONSTRAINT "shift_availability_note_check" CHECK (((note IS NULL) OR (length(note) <= 500))),
  CONSTRAINT "shift_availability_pkey" PRIMARY KEY (id),
  CONSTRAINT "shift_availability_tenant_id_user_id_on_date_key" UNIQUE (tenant_id, user_id, on_date)
);

ALTER TABLE "better_supabase"."shift_availability"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."shift_swaps" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid                     NOT NULL,
  "assignment_id" uuid                     NOT NULL,
  "from_user_id"  uuid                     NOT NULL,
  "to_user_id"    uuid                     NOT NULL,
  "status"        text                     NOT NULL DEFAULT 'pending'::text,
  "approval_id"   uuid,
  "note"          text,
  "decided_by"    uuid,
  "decided_at"    timestamp with time zone,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "shift_swaps_check" CHECK ((to_user_id <> from_user_id)),
  CONSTRAINT "shift_swaps_note_check" CHECK (((note IS NULL) OR (length(note) <= 2000))),
  CONSTRAINT "shift_swaps_pkey" PRIMARY KEY (id),
  CONSTRAINT "shift_swaps_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'canceled'::text])))
);

ALTER TABLE "better_supabase"."shift_swaps"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."shift_templates" (
  "id"                      uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"               uuid                     NOT NULL,
  "name"                    text                     NOT NULL,
  "team_id"                 uuid,
  "location_id"             uuid,
  "starts_time"             time without time zone   NOT NULL,
  "ends_time"               time without time zone   NOT NULL,
  "break_minutes"           integer                  NOT NULL DEFAULT 0,
  "headcount"               integer                  NOT NULL DEFAULT 1,
  "required_qualifications" text[]                   NOT NULL DEFAULT '{}'::text[],
  "weekdays"                integer[]                NOT NULL DEFAULT '{1,2,3,4,5}'::integer[],
  "archived_at"             timestamp with time zone,
  "created_at"              timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"              timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "shift_templates_break_minutes_check" CHECK (((break_minutes >= 0) AND (break_minutes <= 720))),
  CONSTRAINT "shift_templates_headcount_check" CHECK (((headcount >= 1) AND (headcount <= 500))),
  CONSTRAINT "shift_templates_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "shift_templates_pkey" PRIMARY KEY (id),
  CONSTRAINT "shift_templates_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "shift_templates_weekdays_check" CHECK ((weekdays <@ ARRAY[1, 2, 3, 4, 5, 6, 7]))
);

ALTER TABLE "better_supabase"."shift_templates"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."shifts" (
  "id"                      uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"               uuid                     NOT NULL,
  "template_id"             uuid,
  "team_id"                 uuid,
  "location_id"             uuid,
  "starts_at"               timestamp with time zone NOT NULL,
  "ends_at"                 timestamp with time zone NOT NULL,
  "break_minutes"           integer                  NOT NULL DEFAULT 0,
  "headcount"               integer                  NOT NULL DEFAULT 1,
  "required_qualifications" text[]                   NOT NULL DEFAULT '{}'::text[],
  "status"                  text                     NOT NULL DEFAULT 'draft'::text,
  "note"                    text,
  "published_at"            timestamp with time zone,
  "canceled_at"             timestamp with time zone,
  "created_by"              uuid,
  "created_at"              timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"              timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "shifts_break_minutes_check" CHECK (((break_minutes >= 0) AND (break_minutes <= 720))),
  CONSTRAINT "shifts_check1" CHECK (((ends_at - starts_at) <= '24:00:00'::interval)),
  CONSTRAINT "shifts_check" CHECK ((ends_at > starts_at)),
  CONSTRAINT "shifts_headcount_check" CHECK (((headcount >= 1) AND (headcount <= 500))),
  CONSTRAINT "shifts_note_check" CHECK (((note IS NULL) OR (length(note) <= 2000))),
  CONSTRAINT "shifts_pkey" PRIMARY KEY (id),
  CONSTRAINT "shifts_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'canceled'::text]))),
  CONSTRAINT "shifts_tenant_id_id_key" UNIQUE (tenant_id, id)
);

ALTER TABLE "better_supabase"."shifts"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.archive_shift_template (
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_shift_template"($1) $function$;

CREATE OR REPLACE FUNCTION api.assign_shift (
  shift_id uuid,
  user_id  uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."assign_shift"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.cancel_shift (
  shift_id uuid,
  reason   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_shift"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.decide_shift_request (
  assignment_id uuid,
  approve       boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."decide_shift_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.decide_shift_swap (
  swap_id     uuid,
  approve     boolean,
  approval_id uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."decide_shift_swap"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.generate_shifts (
  tenant      uuid,
  template_id uuid,
  from_date   date,
  until_date  date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."generate_shifts"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_shift_availability (
  tenant     uuid,
  from_date  date,
  until_date date,
  user_id    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_shift_availability"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_shift_templates (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_shift_templates"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.my_shifts (
  since timestamp with time zone DEFAULT now(),
  until timestamp with time zone DEFAULT (now() + '30 days'::interval)
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_shifts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.publish_shifts (
  tenant     uuid,
  from_date  date,
  until_date date,
  team_id    uuid DEFAULT NULL::uuid
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."publish_shifts"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.request_open_shift (
  shift_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."request_open_shift"($1) $function$;

CREATE OR REPLACE FUNCTION api.request_shift_swap (
  assignment_id uuid,
  to_user_id    uuid,
  note          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."request_shift_swap"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.roster (
  tenant     uuid,
  from_date  date,
  until_date date,
  team_id    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."roster"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.save_shift (
  tenant                  uuid,
  starts_at               timestamp with time zone,
  ends_at                 timestamp with time zone,
  team_id                 uuid                     DEFAULT NULL::uuid,
  location_id             uuid                     DEFAULT NULL::uuid,
  break_minutes           integer                  DEFAULT 0,
  headcount               integer                  DEFAULT 1,
  required_qualifications text[]                   DEFAULT '{}'::text[],
  note                    text                     DEFAULT NULL::text,
  shift_id                uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_shift"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION api.save_shift_template (
  tenant                  uuid,
  name                    text,
  starts_time             time without time zone,
  ends_time               time without time zone,
  weekdays                integer[]              DEFAULT '{1,2,3,4,5}'::integer[],
  team_id                 uuid                   DEFAULT NULL::uuid,
  location_id             uuid                   DEFAULT NULL::uuid,
  break_minutes           integer                DEFAULT 0,
  headcount               integer                DEFAULT 1,
  required_qualifications text[]                 DEFAULT '{}'::text[],
  template_id             uuid                   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_shift_template"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) $function$;

CREATE OR REPLACE FUNCTION api.set_shift_availability (
  tenant     uuid,
  on_date    date,
  kind       text,
  from_time  time without time zone DEFAULT NULL::time WITHOUT time zone,
  until_time time without time zone DEFAULT NULL::time WITHOUT time zone,
  note       text                   DEFAULT NULL::text,
  user_id    uuid                   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_shift_availability"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.shift_hours (
  tenant     uuid,
  week_start date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."shift_hours"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.shifts_to_time_entries (
  tenant uuid,
  until  timestamp with time zone DEFAULT now()
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."shifts_to_time_entries"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.unassign_shift (
  assignment_id uuid,
  reason        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."unassign_shift"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_shift_template (
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
  select * into v_row from "better_supabase"."shift_templates" x where x."id" = archive_shift_template.template_id;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  update "better_supabase"."shift_templates" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
    ('user', 'better_supabase.contacts', '"better_supabase"."contacts"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ai_document_versions', '"better_supabase"."ai_document_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'enrolled_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.contacts', '"better_supabase"."contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contact_identities', '"better_supabase"."contact_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.price_lists', '"better_supabase"."price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.categories', '"better_supabase"."categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.person_inbox_contacts', '"better_supabase"."person_inbox_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagements', '"better_supabase"."engagements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policies', '"better_supabase"."policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_components', '"better_supabase"."status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_component_history', '"better_supabase"."status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_pages', '"better_supabase"."status_pages"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
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
  if v_status = 'approved' then
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
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.generate_shifts (
  tenant      uuid,
  template_id uuid,
  from_date   date,
  until_date  date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_template "better_supabase"."shift_templates"%rowtype;
  v_row "better_supabase"."shifts"%rowtype;
  v_day date;
  v_starts timestamptz;
  v_ends timestamptz;
  v_created jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', generate_shifts.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_template from "better_supabase"."shift_templates" x
  where x."id" = generate_shifts.template_id and x."tenant_id" = generate_shifts.tenant and x."archived_at" is null;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if generate_shifts.from_date is null or generate_shifts.until_date is null or generate_shifts.until_date < generate_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if generate_shifts.until_date - generate_shifts.from_date >= 92 then
    raise exception 'generate_shifts covers at most 92 days' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_day in select d::date from generate_series(generate_shifts.from_date::timestamp, generate_shifts.until_date::timestamp, interval '1 day') d loop
    continue when not (extract(isodow from v_day)::integer = any(v_template."weekdays"));
    v_starts := (v_day + v_template."starts_time") at time zone 'UTC';
    v_ends := (v_day + v_template."ends_time" + case when v_template."ends_time" <= v_template."starts_time" then interval '1 day' else interval '0' end) at time zone 'UTC';
    continue when exists (
      select 1 from "better_supabase"."shifts" x
      where x."tenant_id" = v_template."tenant_id" and x."template_id" = v_template."id" and x."starts_at" = v_starts
    );
    insert into "better_supabase"."shifts" ("tenant_id", "template_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "created_by")
    values (v_template."tenant_id", v_template."id", v_template."team_id", v_template."location_id", v_starts, v_ends, v_template."break_minutes", v_template."headcount", v_template."required_qualifications", (select auth.uid()))
    returning * into v_row;
    perform "better_supabase".emit_event('shift.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status"), 'shifts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift.created',
    category => 'data',
    target_type => 'shift',
    record_id => v_row."id"::text,
    summary => 'Shift created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status")
  );
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at"));
  end loop;
  return v_created;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_shift_availability (
  tenant     uuid,
  from_date  date,
  until_date date,
  user_id    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'onDate', x."on_date", 'fromTime', to_char(x."from_time", 'HH24:MI'), 'untilTime', to_char(x."until_time", 'HH24:MI'), 'kind', x."kind", 'note', x."note", 'createdAt', x."created_at") order by x."on_date", x."user_id"), '[]'::jsonb)
  from "better_supabase"."shift_availability" x
  where x."tenant_id" = list_shift_availability.tenant
    and x."on_date" between list_shift_availability.from_date and list_shift_availability.until_date
    and (list_shift_availability.user_id is null or x."user_id" = list_shift_availability.user_id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_shift_templates (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'teamId', x."team_id", 'locationId', x."location_id", 'startsTime', to_char(x."starts_time", 'HH24:MI'), 'endsTime', to_char(x."ends_time", 'HH24:MI'), 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'weekdays', to_jsonb(x."weekdays"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."shift_templates" x
  where x."tenant_id" = list_shift_templates.tenant
    and (coalesce(list_shift_templates.include_archived, false) or x."archived_at" is null)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_shifts (
  since timestamp with time zone DEFAULT now(),
  until timestamp with time zone DEFAULT (now() + '30 days'::interval)
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignment', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_at"), '[]'::jsonb)
  from "better_supabase"."shift_assignments" y
  join "better_supabase"."shifts" x on x."id" = y."shift_id"
  where y."user_id" = (select auth.uid())
    and y."status" in ('assigned', 'requested')
    and x."status" <> 'draft'
    and x."starts_at" >= coalesce(my_shifts.since, now())
    and x."starts_at" < coalesce(my_shifts.until, now() + interval '30 days')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'activities.manage' then 'engagements.manage'
    when 'activities.read' then 'engagements.read'
    when 'activities.write' then 'engagements.write'
    when 'agents.create' then 'ai.create'
    when 'agents.moderate' then 'ai.moderate'
    when 'agents.publish' then 'ai.share'
    when 'agents.read' then 'ai.read'
    when 'ai-chat.admin' then 'ai_chat.admin'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai.admin'
    when 'ai-files.upload' then 'ai.create'
    when 'ai-keys.manage' then 'ai.admin'
    when 'ai-keys.use' then 'ai.create'
    when 'ai-schedules.create' then 'ai.create'
    when 'ai-schedules.manage' then 'ai.admin'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.revert' then 'audit.revert'
    when 'audit.view' then 'audit.read'
    when 'audit.viewAll' then 'audit.read'
    when 'automations.admin' then 'rules.admin'
    when 'automations.edit' then 'rules.edit'
    when 'automations.publish' then 'rules.publish'
    when 'automations.read' then 'rules.read'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk.run' then 'bulk.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.acknowledge' then 'controls.acknowledge'
    when 'compliance.collect' then 'controls.collect'
    when 'compliance.manage' then 'controls.manage'
    when 'compliance.read' then 'controls.read'
    when 'connectors.manage' then 'ai.admin'
    when 'connectors.read' then 'ai.read'
    when 'connectors.use' then 'ai.create'
    when 'contacts.manage' then 'parties.manage'
    when 'contacts.read' then 'parties.read'
    when 'contacts.write' then 'parties.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.sensitive.read'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'organization.export'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'employees.read' then 'employees.read'
    when 'employees.viewSensitive' then 'employees.view_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-history.read' then 'history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'goals.manage' then 'targets.manage'
    when 'goals.read' then 'targets.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'ai.admin'
    when 'knowledge.read' then 'ai.read'
    when 'knowledge.write' then 'ai.create'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'mail-sync.connect' then 'mail.connect'
    when 'mail-sync.manage' then 'mail.manage'
    when 'mail-sync.read' then 'mail.read'
    when 'mail-sync.send' then 'mail.send'
    when 'memory.manage' then 'ai.admin'
    when 'memory.read' then 'ai.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'number_sequences.assign'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'views.read'
    when 'saved-views.share' then 'views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.edit' then 'segments.edit'
    when 'segments.read' then 'segments.read'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_principals.manage'
    when 'service-accounts.read' then 'service_principals.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'work_items.manage'
    when 'tasks.read' then 'work_items.read'
    when 'tasks.write' then 'work_items.write'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
    when 'timeline.read' then 'activity.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'members.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow.admin'
    when 'workflow-editor.edit' then 'workflow.edit'
    when 'workflow-editor.publish' then 'workflow.publish'
    when 'workflow-editor.read' then 'workflow.read'
    when 'workflow-editor.run' then 'workflow.run'
    when 'workflows.admin' then 'workflow.admin'
    when 'workflows.read' then 'workflow.read'
    when 'workflows.run' then 'workflow.run'
  end
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
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_open_shift (
  shift_id uuid
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
  v_user uuid := (select auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = request_open_shift.shift_id;
  if not found or v_shift."status" = 'draft' then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if v_user is null or not coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.request'), false) then
    raise exception 'not allowed to request shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  if v_shift."starts_at" <= now() then
    raise exception 'the shift has started' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = v_user;
  if found and v_row."status" <> 'released' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  perform "better_supabase"."shift_assignment_check"(v_shift."id", v_user, v_row."id");
  insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_user, 'requested', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'requested', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.roster (
  tenant     uuid,
  from_date  date,
  until_date date,
  team_id    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."status", y."user_id")
    from "better_supabase"."shift_assignments" y
    where y."shift_id" = x."id" and y."status" <> 'released'
  ), '[]'::jsonb)) order by x."starts_at", x."id"), '[]'::jsonb)
  from "better_supabase"."shifts" x
  where x."tenant_id" = roster.tenant
    and x."starts_at" >= (roster.from_date)::timestamp at time zone 'UTC'
    and x."starts_at" < (roster.until_date + 1)::timestamp at time zone 'UTC'
    and (roster.team_id is null or x."team_id" = roster.team_id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_shift (
  tenant                  uuid,
  starts_at               timestamp with time zone,
  ends_at                 timestamp with time zone,
  team_id                 uuid                     DEFAULT NULL::uuid,
  location_id             uuid                     DEFAULT NULL::uuid,
  break_minutes           integer                  DEFAULT 0,
  headcount               integer                  DEFAULT 1,
  required_qualifications text[]                   DEFAULT '{}'::text[],
  note                    text                     DEFAULT NULL::text,
  shift_id                uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift.required_qualifications, '{}')) k where k is not null order by k);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if save_shift.starts_at is null or save_shift.ends_at is null or save_shift.ends_at <= save_shift.starts_at then
    raise exception 'a shift ends after it starts' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.ends_at - save_shift.starts_at > interval '24 hours' then
    raise exception 'a shift lasts at most 24 hours' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.note is not null and length(save_shift.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift.team_id and o."tenant_id" = save_shift.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.location_id is not null and not exists (
    select 1 from "better_supabase"."assets" o where o."id" = save_shift.location_id and o."tenant_id" = save_shift.tenant
  ) then
    raise exception 'the location isn''t an asset in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if exists (
    select 1 from unnest(coalesce(v_required, '{}')) k
    where not exists (
      select 1 from "better_supabase"."qualification_types" o
      where o."tenant_id" = save_shift.tenant and o."key" = k and o."archived_at" is null
    )
  ) then
    raise exception 'every required qualification is a qualification type key of this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_save"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using save_shift.tenant, save_shift.shift_id;
    end if;
  end;
  if save_shift.shift_id is null then
    insert into "better_supabase"."shifts" ("tenant_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "note", "created_by")
    values (save_shift.tenant, save_shift.team_id, save_shift.location_id, save_shift.starts_at, save_shift.ends_at, coalesce(save_shift.break_minutes, 0), coalesce(save_shift.headcount, 1), v_required, nullif(trim(save_shift.note), ''), (select auth.uid()))
    returning * into v_row;
    perform "better_supabase".emit_event('shift.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status"), 'shifts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift.created',
    category => 'data',
    target_type => 'shift',
    record_id => v_row."id"::text,
    summary => 'Shift created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status")
  );
  else
    select * into v_row from "better_supabase"."shifts" x
    where x."id" = save_shift.shift_id and x."tenant_id" = save_shift.tenant
    for update;
    if not found then
      raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
    end if;
    if v_row."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    update "better_supabase"."shifts" x set
      "starts_at" = save_shift.starts_at,
      "ends_at" = save_shift.ends_at,
      "team_id" = save_shift.team_id,
      "location_id" = save_shift.location_id,
      "break_minutes" = coalesce(save_shift.break_minutes, 0),
      "headcount" = coalesce(save_shift.headcount, 1),
      "required_qualifications" = v_required,
      "note" = nullif(trim(save_shift.note), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    begin
      update "better_supabase"."shift_assignments" x set "starts_at" = v_row."starts_at", "ends_at" = v_row."ends_at", "updated_at" = now()
      where x."shift_id" = v_row."id" and (x."starts_at" <> v_row."starts_at" or x."ends_at" <> v_row."ends_at");
    exception when exclusion_violation then
      raise exception 'an assigned member has another shift at the new time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_shift_template (
  tenant                  uuid,
  name                    text,
  starts_time             time without time zone,
  ends_time               time without time zone,
  weekdays                integer[]              DEFAULT '{1,2,3,4,5}'::integer[],
  team_id                 uuid                   DEFAULT NULL::uuid,
  location_id             uuid                   DEFAULT NULL::uuid,
  break_minutes           integer                DEFAULT 0,
  headcount               integer                DEFAULT 1,
  required_qualifications text[]                 DEFAULT '{}'::text[],
  template_id             uuid                   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
  v_name text := nullif(trim(save_shift_template.name), '');
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift_template.required_qualifications, '{}')) k where k is not null order by k);
  v_weekdays integer[] := array(select distinct d from unnest(coalesce(save_shift_template.weekdays, '{}')) d where d is not null order by d);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift_template.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a shift template needs a name of at most 200 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.starts_time is null or save_shift_template.ends_time is null then
    raise exception 'a shift template needs a start and an end time' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if not (v_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]) then
    raise exception 'weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift_template.team_id and o."tenant_id" = save_shift_template.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.location_id is not null and not exists (
    select 1 from "better_supabase"."assets" o where o."id" = save_shift_template.location_id and o."tenant_id" = save_shift_template.tenant
  ) then
    raise exception 'the location isn''t an asset in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if exists (
    select 1 from unnest(coalesce(v_required, '{}')) k
    where not exists (
      select 1 from "better_supabase"."qualification_types" o
      where o."tenant_id" = save_shift_template.tenant and o."key" = k and o."archived_at" is null
    )
  ) then
    raise exception 'every required qualification is a qualification type key of this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.template_id is null then
    insert into "better_supabase"."shift_templates" ("tenant_id", "name", "team_id", "location_id", "starts_time", "ends_time", "break_minutes", "headcount", "required_qualifications", "weekdays")
    values (save_shift_template.tenant, v_name, save_shift_template.team_id, save_shift_template.location_id, save_shift_template.starts_time, save_shift_template.ends_time, coalesce(save_shift_template.break_minutes, 0), coalesce(save_shift_template.headcount, 1), v_required, v_weekdays)
    returning * into v_row;
  else
    update "better_supabase"."shift_templates" x set
      "name" = v_name,
      "team_id" = save_shift_template.team_id,
      "location_id" = save_shift_template.location_id,
      "starts_time" = save_shift_template.starts_time,
      "ends_time" = save_shift_template.ends_time,
      "break_minutes" = coalesce(save_shift_template.break_minutes, 0),
      "headcount" = coalesce(save_shift_template.headcount, 1),
      "required_qualifications" = v_required,
      "weekdays" = v_weekdays,
      "updated_at" = now(),
      "archived_at" = null
    where x."id" = save_shift_template.template_id and x."tenant_id" = save_shift_template.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_shift_availability (
  tenant     uuid,
  on_date    date,
  kind       text,
  from_time  time without time zone DEFAULT NULL::time WITHOUT time zone,
  until_time time without time zone DEFAULT NULL::time WITHOUT time zone,
  note       text                   DEFAULT NULL::text,
  user_id    uuid                   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_availability"%rowtype;
  v_user uuid := coalesce(set_shift_availability.user_id, (select auth.uid()));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_user = (select auth.uid()) then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.request'), false)) then
      raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to set another member''s availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if set_shift_availability.on_date is null then
    raise exception 'on_date is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.kind is null then
    delete from "better_supabase"."shift_availability" x
    where x."tenant_id" = set_shift_availability.tenant and x."user_id" = v_user and x."on_date" = set_shift_availability.on_date;
    return null;
  end if;
  if set_shift_availability.kind not in ('available', 'unavailable', 'preferred') then
    raise exception 'kind is one of available, unavailable, preferred' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if (set_shift_availability.from_time is null) <> (set_shift_availability.until_time is null)
    or set_shift_availability.until_time <= set_shift_availability.from_time then
    raise exception 'from_time and until_time are both set, with until_time after from_time, or both null' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.note is not null and length(set_shift_availability.note) > 500 then
    raise exception 'a note is at most 500 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  insert into "better_supabase"."shift_availability" ("tenant_id", "user_id", "on_date", "from_time", "until_time", "kind", "note")
  values (set_shift_availability.tenant, v_user, set_shift_availability.on_date, set_shift_availability.from_time, set_shift_availability.until_time, set_shift_availability.kind, nullif(trim(set_shift_availability.note), ''))
  on conflict ("tenant_id", "user_id", "on_date") do update set
    "from_time" = excluded."from_time",
    "until_time" = excluded."until_time",
    "kind" = excluded."kind",
    "note" = excluded."note"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'onDate', v_row."on_date", 'fromTime', to_char(v_row."from_time", 'HH24:MI'), 'untilTime', to_char(v_row."until_time", 'HH24:MI'), 'kind', v_row."kind", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.shift_assignment_check (
  shift_id      uuid,
  user_id       uuid,
  assignment_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_key text;
begin
  select * into v_shift from "better_supabase"."shifts" x where x."id" = shift_assignment_check.shift_id;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if shift_assignment_check.user_id is null or not exists (select 1 from "public"."memberships" mm where mm."organization_id" = v_shift."tenant_id" and mm."user_id" = shift_assignment_check.user_id) then
    raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at", v_shift."ends_at")
  ) then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end if;
  foreach v_key in array v_shift."required_qualifications" loop
    if not coalesce("better_supabase"."qualified_holders"(v_shift."tenant_id", v_key, 'member', (v_shift."starts_at" at time zone 'UTC')::date) ? shift_assignment_check.user_id::text, false) then
      raise exception 'the member doesn''t hold a qualification the shift requires' using errcode = '23514', hint = 'SHIFT_ASSIGNMENT_UNQUALIFIED';
    end if;
  end loop;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at" - interval '11 hours', v_shift."ends_at" + interval '11 hours')
  ) then
    raise exception 'the member would have less than 11 hours between shifts' using errcode = '23514', hint = 'SHIFT_ASSIGNMENT_REST_TOO_SHORT';
  end if;
  return v_warnings;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.shift_hours (
  tenant     uuid,
  week_start date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', shift_hours.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to read planned hours' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if shift_hours.week_start is null then
    raise exception 'week_start is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'shifts', u.assigned,
      'plannedHours', u.planned,
      'contractHours', u.contract,
      'differenceHours', u.planned - u.contract
    ) order by u.planned desc, u.user_id), '[]'::jsonb)
    from (
      select p.user_id, p.assigned, p.planned, (select k."hours_per_week" from "better_supabase"."employee_contracts" k
        join "better_supabase"."employees" e on e."id" = k."employee_id"
        where e."user_id" = p.user_id and k."tenant_id" = shift_hours.tenant
          and k."starts_on" <= shift_hours.week_start and (k."ends_on" is null or k."ends_on" >= shift_hours.week_start)
        order by k."starts_on" desc
        limit 1)::numeric as contract
      from (
        select y."user_id" as user_id, count(*)::integer as assigned, round((extract(epoch from sum(x."ends_at" - make_interval(mins => x."break_minutes") - x."starts_at")) / 3600)::numeric, 2) as planned
        from "better_supabase"."shift_assignments" y
        join "better_supabase"."shifts" x on x."id" = y."shift_id"
        where y."tenant_id" = shift_hours.tenant
          and y."status" = 'assigned'
          and x."status" <> 'canceled'
          and x."starts_at" >= (shift_hours.week_start)::timestamp at time zone 'UTC'
          and x."starts_at" < (shift_hours.week_start + 7)::timestamp at time zone 'UTC'
        group by y."user_id"
      ) p
    ) u
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.shifts_to_time_entries (
  tenant uuid,
  until  timestamp with time zone DEFAULT now()
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item record;
  v_count integer := 0;
begin
  for v_item in
    select y."id" as id, y."tenant_id" as tenant, y."user_id" as user_id, x."starts_at" as starts_at,
      greatest(x."ends_at" - make_interval(mins => x."break_minutes"), x."starts_at" + interval '1 minute') as ends_at,
      (select o."id" from "better_supabase"."employees" o where o."tenant_id" = y."tenant_id" and o."user_id" = y."user_id" limit 1) as employee_id
    from "better_supabase"."shift_assignments" y
    join "better_supabase"."shifts" x on x."id" = y."shift_id"
    where y."tenant_id" = shifts_to_time_entries.tenant
      and y."status" = 'assigned'
      and x."status" <> 'canceled'
      and x."ends_at" <= least(coalesce(shifts_to_time_entries.until, now()), now())
      and not exists (
        select 1 from "better_supabase"."time_entries" t
        where t."tenant_id" = y."tenant_id" and t."subject_type" = 'shift_assignment' and t."subject_id" = y."id"::text
      )
    order by x."starts_at"
  loop
    begin
      insert into "better_supabase"."time_entries" ("tenant_id", "user_id", "employee_id", "subject_type", "subject_id", "started_at", "ended_at")
      values (v_item.tenant, v_item.user_id, v_item.employee_id, 'shift_assignment', v_item.id::text, v_item.starts_at, v_item.ends_at);
      v_count := v_count + 1;
    exception when exclusion_violation or not_null_violation or sqlstate '55000' then
      null;
    end;
  end loop;
  return v_count;
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."shift_assignments"
  ADD CONSTRAINT "shift_assignments_no_overlap" EXCLUDE USING gist (tenant_id WITH =, user_id WITH =, tstzrange(starts_at, ends_at) WITH &&) WHERE ((status = 'assigned'::text));

ALTER TABLE "better_supabase"."shift_swaps"
  ADD CONSTRAINT "shift_swaps_approval_id_fkey" FOREIGN KEY (approval_id) REFERENCES better_supabase.approval_requests(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."shift_swaps"
  ADD CONSTRAINT "shift_swaps_tenant_id_assignment_id_fkey" FOREIGN KEY (tenant_id, assignment_id) REFERENCES better_supabase.shift_assignments(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."shift_templates"
  ADD CONSTRAINT "shift_templates_location_id_fkey" FOREIGN KEY (location_id) REFERENCES better_supabase.assets(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."shift_templates"
  ADD CONSTRAINT "shift_templates_team_id_fkey" FOREIGN KEY (team_id) REFERENCES better_supabase.teams(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."shifts"
  ADD CONSTRAINT "shifts_location_id_fkey" FOREIGN KEY (location_id) REFERENCES better_supabase.assets(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."shifts"
  ADD CONSTRAINT "shifts_team_id_fkey" FOREIGN KEY (team_id) REFERENCES better_supabase.teams(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."shift_assignments"
  ADD CONSTRAINT "shift_assignments_tenant_id_shift_id_fkey" FOREIGN KEY (tenant_id, shift_id) REFERENCES better_supabase.shifts(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."shifts"
  ADD CONSTRAINT "shifts_tenant_id_template_id_fkey" FOREIGN KEY (tenant_id, template_id) REFERENCES better_supabase.shift_templates(tenant_id, id) ON DELETE SET NULL (template_id);

CREATE INDEX shift_assignments_tenant_idx ON better_supabase.shift_assignments USING btree (tenant_id, shift_id);

CREATE INDEX shift_assignments_user_idx ON better_supabase.shift_assignments USING btree (user_id, starts_at);

CREATE INDEX shift_availability_day_idx ON better_supabase.shift_availability USING btree (tenant_id, on_date);

CREATE INDEX shift_swaps_approval_idx ON better_supabase.shift_swaps USING btree (approval_id)
  WHERE (approval_id IS NOT NULL);

CREATE UNIQUE INDEX shift_swaps_pending_idx ON better_supabase.shift_swaps USING btree (assignment_id)
  WHERE (status = 'pending'::text);

CREATE INDEX shift_swaps_tenant_idx ON better_supabase.shift_swaps USING btree (tenant_id, assignment_id);

CREATE INDEX shift_swaps_to_user_idx ON better_supabase.shift_swaps USING btree (to_user_id);

CREATE INDEX shift_templates_location_idx ON better_supabase.shift_templates USING btree (location_id)
  WHERE (location_id IS NOT NULL);

CREATE INDEX shift_templates_team_idx ON better_supabase.shift_templates USING btree (team_id)
  WHERE (team_id IS NOT NULL);

CREATE INDEX shift_templates_tenant_idx ON better_supabase.shift_templates USING btree (tenant_id, name);

CREATE INDEX shifts_location_idx ON better_supabase.shifts USING btree (location_id)
  WHERE (location_id IS NOT NULL);

CREATE INDEX shifts_team_idx ON better_supabase.shifts USING btree (team_id)
  WHERE (team_id IS NOT NULL);

CREATE INDEX shifts_template_idx ON better_supabase.shifts USING btree (tenant_id, template_id)
  WHERE (template_id IS NOT NULL);

CREATE INDEX shifts_tenant_idx ON better_supabase.shifts USING btree (tenant_id, starts_at);

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."shift_assignments"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."shift_assignments"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."shift_assignments"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('shifts.read'::text) AS tenant_ids_with)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."shift_assignments"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "shift_assignments_read" ON "better_supabase"."shift_assignments"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shifts.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."shift_availability"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."shift_availability"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."shift_availability"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('shifts.write'::text) AS tenant_ids_with)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."shift_availability"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "shift_availability_read" ON "better_supabase"."shift_availability"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shifts.write'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."shift_swaps"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."shift_swaps"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."shift_swaps"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((from_user_id = ( SELECT auth.uid() AS uid)) OR (to_user_id = ( SELECT
    auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shifts.manage'::text) AS tenant_ids_with)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."shift_swaps"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "shift_swaps_read" ON "better_supabase"."shift_swaps"
  FOR SELECT
  TO "authenticated"
  USING
    (((from_user_id = ( SELECT auth.uid() AS uid)) OR (to_user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shifts.manage'::text) AS
    tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."shift_templates"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."shift_templates"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."shift_templates"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shifts.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."shift_templates"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "shift_templates_read" ON "better_supabase"."shift_templates"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('shifts.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."shifts"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."shifts"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."shifts"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('shifts.write'::text)
    AS tenant_ids_with)) OR ((status <> 'draft'::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shifts.read'::text) AS tenant_ids_with))))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."shifts"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "shifts_read" ON "better_supabase"."shifts"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('shifts.write'::text) AS tenant_ids_with)) OR ((status <> 'draft'::text) AND (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('shifts.read'::text) AS tenant_ids_with)))));

REVOKE ALL ON FUNCTION "api"."archive_shift_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_shift_template"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."assign_shift"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."assign_shift"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."cancel_shift"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_shift"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."decide_shift_request"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."decide_shift_request"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."decide_shift_swap"(uuid, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."decide_shift_swap"(uuid, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."generate_shifts"(uuid, uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."generate_shifts"(uuid, uuid, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_shift_availability"(uuid, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_shift_availability"(uuid, date, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_shift_templates"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_shift_templates"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."my_shifts"(timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."my_shifts"(timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."publish_shifts"(uuid, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."publish_shifts"(uuid, date, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."request_open_shift"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."request_open_shift"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."request_shift_swap"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."request_shift_swap"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."roster"(uuid, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."roster"(uuid, date, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_shift"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid, uuid, integer, integer, text[], text, uuid) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."save_shift"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid, uuid, integer, integer, text[], text, uuid)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_shift_template"(uuid, text, time WITHOUT time zone, time WITHOUT time zone, integer[], uuid, uuid, integer, integer, text[], uuid) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."save_shift_template"(uuid, text, time WITHOUT time zone, time WITHOUT time zone, integer[], uuid, uuid, integer, integer, text[], uuid)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_shift_availability"(uuid, date, text, time WITHOUT time zone, time WITHOUT time zone, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_shift_availability"(uuid, date, text, time WITHOUT time zone, time WITHOUT time zone, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."shift_hours"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."shift_hours"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."shifts_to_time_entries"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."shifts_to_time_entries"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."unassign_shift"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."unassign_shift"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_shift_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_shift_template"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."assign_shift"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."assign_shift"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."cancel_shift"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_shift"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."decide_shift_request"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."decide_shift_request"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."generate_shifts"(uuid, uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."generate_shifts"(uuid, uuid, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_shift_availability"(uuid, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_shift_availability"(uuid, date, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_shift_templates"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_shift_templates"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."my_shifts"(timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."my_shifts"(timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."publish_shifts"(uuid, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."publish_shifts"(uuid, date, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."request_open_shift"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."request_open_shift"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."request_shift_swap"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."request_shift_swap"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."roster"(uuid, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."roster"(uuid, date, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_shift"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid, uuid, integer, integer, text[], text, uuid) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."save_shift"(uuid, timestamp WITH time zone, timestamp WITH time zone, uuid, uuid, integer, integer, text[], text, uuid)
  TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."save_shift_template"(uuid, text, time WITHOUT time zone, time WITHOUT time zone, integer[], uuid, uuid, integer, integer, text[], uuid)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."save_shift_template"(uuid, text, time WITHOUT time zone, time WITHOUT time zone, integer[], uuid, uuid, integer, integer, text[], uuid)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_shift_availability"(uuid, date, text, time WITHOUT time zone, time WITHOUT time zone, text, uuid) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."set_shift_availability"(uuid, date, text, time WITHOUT time zone, time WITHOUT time zone, text, uuid)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."shift_assignment_check"(uuid, uuid, uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."shift_hours"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."shift_hours"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."shifts_to_time_entries"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."shifts_to_time_entries"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unassign_shift"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unassign_shift"(uuid, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."shift_assignments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."shift_assignments" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."shift_availability" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."shift_availability" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."shift_swaps" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."shift_swaps" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."shift_templates" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."shift_templates" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."shifts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."shifts" TO "service_role";
