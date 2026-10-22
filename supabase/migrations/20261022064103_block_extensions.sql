-- Alters bookings, which already holds rows: fail fast instead of queueing
-- behind long queries (doctor BS233).
SET local lock_timeout = '5s';

SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."booking_series" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"        uuid                     NOT NULL,
  "service_id"       uuid                     NOT NULL,
  "resource_id"      uuid                     NOT NULL,
  "rule"             jsonb                    NOT NULL,
  "starts_at"        timestamp with time zone NOT NULL,
  "tz"               text                     NOT NULL,
  "customer_name"    text,
  "customer_email"   text,
  "customer_user_id" uuid,
  "status"           text                     NOT NULL DEFAULT 'active'::text,
  "ends_at"          timestamp with time zone,
  "created_by"       uuid,
  "created_at"       timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "booking_series_pkey" PRIMARY KEY (id),
  CONSTRAINT "booking_series_rule_check" CHECK ((jsonb_typeof(rule) = 'object'::text)),
  CONSTRAINT "booking_series_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'ended'::text, 'cancelled'::text])))
);

ALTER TABLE "better_supabase"."booking_series"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."engagement_notes" (
  "engagement_id" uuid                     NOT NULL,
  "tenant_id"     uuid                     NOT NULL,
  "summary"       text                     NOT NULL,
  "action_items"  jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "model"         text,
  "source"        text                     NOT NULL DEFAULT 'ai'::text,
  "created_by"    uuid,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "engagement_notes_action_items_check" CHECK ((jsonb_typeof(action_items) = 'array'::text)),
  CONSTRAINT "engagement_notes_pkey" PRIMARY KEY (engagement_id),
  CONSTRAINT "engagement_notes_source_check" CHECK ((source = ANY (ARRAY['ai'::text, 'member'::text]))),
  CONSTRAINT "engagement_notes_summary_check" CHECK (((length(summary) >= 1) AND (length(summary) <= 20000)))
);

ALTER TABLE "better_supabase"."engagement_notes"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."engagement_recordings" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"        uuid                     NOT NULL,
  "engagement_id"    uuid                     NOT NULL,
  "file_id"          uuid                     NOT NULL,
  "filename"         text                     NOT NULL,
  "media_type"       text                     NOT NULL,
  "status"           text                     NOT NULL DEFAULT 'pending'::text,
  "language"         text,
  "duration_seconds" integer,
  "error"            text,
  "model"            text,
  "created_by"       uuid,
  "created_at"       timestamp with time zone NOT NULL DEFAULT now(),
  "transcribed_at"   timestamp with time zone,
  CONSTRAINT "engagement_recordings_duration_seconds_check" CHECK ((duration_seconds >= 0)),
  CONSTRAINT "engagement_recordings_engagement_id_file_id_key" UNIQUE (engagement_id, file_id),
  CONSTRAINT "engagement_recordings_pkey" PRIMARY KEY (id),
  CONSTRAINT "engagement_recordings_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'transcribed'::text, 'failed'::text])))
);

ALTER TABLE "better_supabase"."engagement_recordings"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."engagement_transcript_segments" (
  "recording_id"    uuid    NOT NULL,
  "tenant_id"       uuid    NOT NULL,
  "position"        integer NOT NULL,
  "speaker"         text,
  "speaker_user_id" uuid,
  "starts_ms"       integer NOT NULL,
  "ends_ms"         integer NOT NULL,
  "text"            text    NOT NULL,
  "confidence"      real,
  CONSTRAINT "engagement_transcript_segments_check" CHECK ((ends_ms >= starts_ms)),
  CONSTRAINT "engagement_transcript_segments_confidence_check" CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision))),
  CONSTRAINT "engagement_transcript_segments_pkey" PRIMARY KEY (recording_id, "position"),
  CONSTRAINT "engagement_transcript_segments_position_check" CHECK (("position" >= 1)),
  CONSTRAINT "engagement_transcript_segments_starts_ms_check" CHECK ((starts_ms >= 0))
);

ALTER TABLE "better_supabase"."engagement_transcript_segments"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."kitchen_routes" (
  "product_id" uuid NOT NULL,
  "tenant_id"  uuid NOT NULL,
  "station_id" uuid NOT NULL,
  CONSTRAINT "kitchen_routes_pkey" PRIMARY KEY (product_id)
);

ALTER TABLE "better_supabase"."kitchen_routes"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."kitchen_stations" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "key"        text                     NOT NULL,
  "name"       text                     NOT NULL,
  "position"   integer                  NOT NULL DEFAULT 0,
  "is_default" boolean                  NOT NULL DEFAULT false,
  "active"     boolean                  NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "kitchen_stations_key_check" CHECK ((key ~ '^[a-z][a-z0-9_-]{0,62}$'::text)),
  CONSTRAINT "kitchen_stations_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "kitchen_stations_pkey" PRIMARY KEY (id),
  CONSTRAINT "kitchen_stations_tenant_id_key_key" UNIQUE (tenant_id, key)
);

ALTER TABLE "better_supabase"."kitchen_stations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."order_line_preparations" (
  "order_line_id" uuid                     NOT NULL,
  "tenant_id"     uuid                     NOT NULL,
  "order_id"      uuid                     NOT NULL,
  "station_id"    uuid,
  "state"         text                     NOT NULL DEFAULT 'queued'::text,
  "note"          text,
  "queued_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "started_at"    timestamp with time zone,
  "ready_at"      timestamp with time zone,
  "served_at"     timestamp with time zone,
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "updated_by"    uuid,
  CONSTRAINT "order_line_preparations_note_check" CHECK ((length(note) <= 500)),
  CONSTRAINT "order_line_preparations_pkey" PRIMARY KEY (order_line_id),
  CONSTRAINT "order_line_preparations_state_check" CHECK ((state = ANY (ARRAY['queued'::text, 'preparing'::text, 'ready'::text, 'served'::text])))
);

ALTER TABLE "better_supabase"."order_line_preparations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."pass_credit_entries" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "pass_id"    uuid                     NOT NULL,
  "booking_id" uuid,
  "delta"      integer                  NOT NULL,
  "reason"     text                     NOT NULL,
  "created_by" uuid,
  "created_at" timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "pass_credit_entries_check" CHECK (((reason = 'booking'::text) = (delta = '-1'::integer))),
  CONSTRAINT "pass_credit_entries_delta_check" CHECK ((delta = ANY (ARRAY['-1'::integer, 1]))),
  CONSTRAINT "pass_credit_entries_pkey" PRIMARY KEY (id),
  CONSTRAINT "pass_credit_entries_reason_check" CHECK ((reason = ANY (ARRAY['booking'::text, 'refund'::text])))
);

ALTER TABLE "better_supabase"."pass_credit_entries"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."bookings"
  ADD COLUMN "series_id" uuid;

CREATE OR REPLACE FUNCTION api.attach_engagement_recording (
  engagement uuid,
  file       uuid,
  language   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."attach_engagement_recording"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.book_series (
  service        uuid,
  resource       uuid,
  starts_at      timestamp with time zone,
  rule           jsonb,
  customer       jsonb,
  skip_conflicts boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."book_series"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.book_with_credit (
  pass_id   uuid,
  service   uuid,
  resource  uuid,
  starts_at timestamp with time zone,
  customer  jsonb                    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."book_with_credit"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.booking_series_starts (
  rule        jsonb,
  first_start timestamp with time zone,
  tz          text
)
  RETURNS SETOF timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."booking_series_starts"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.bump_kitchen_ticket (
  order_id uuid,
  station  uuid,
  state    text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."bump_kitchen_ticket"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.cancel_booking_series (
  booking uuid,
  scope   text DEFAULT 'following'::text,
  reason  text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_booking_series"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.delete_kitchen_station (
  station uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_kitchen_station"($1) $function$;

CREATE OR REPLACE FUNCTION api.engagement_notes (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."engagement_notes"($1) $function$;

CREATE OR REPLACE FUNCTION api.engagement_recordings (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."engagement_recordings"($1) $function$;

CREATE OR REPLACE FUNCTION api.engagement_transcript (
  recording uuid,
  after     integer,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."engagement_transcript"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.engagement_with_transcripts (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."engagement_with_transcripts"($1) $function$;

CREATE OR REPLACE FUNCTION api.fail_engagement_recording (
  recording uuid,
  error     text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."fail_engagement_recording"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_booking_series (
  series_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_booking_series"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_engagement_recording (
  recording uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_engagement_recording"($1) $function$;

CREATE OR REPLACE FUNCTION api.kitchen_queue (
  tenant    uuid,
  station   uuid,
  states    text[],
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."kitchen_queue"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.kitchen_stations (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."kitchen_stations"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_pass_credits (
  pass_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pass_credits"($1) $function$;

CREATE OR REPLACE FUNCTION api.move_booking (
  booking   uuid,
  starts_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."move_booking"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.order_board (
  tenant    uuid,
  since     timestamp with time zone,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."order_board"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.pending_engagement_recordings (
  batch integer
)
  RETURNS uuid[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_engagement_recordings"($1) $function$;

CREATE OR REPLACE FUNCTION api.reschedule_booking (
  booking   uuid,
  starts_at timestamp with time zone,
  scope     text                     DEFAULT 'one'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reschedule_booking"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_engagement_notes (
  engagement uuid,
  notes      jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_engagement_notes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_engagement_transcript (
  recording uuid,
  segments  jsonb,
  attrs     jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_engagement_transcript"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_kitchen_station (
  tenant  uuid,
  station uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_kitchen_station"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.send_order_to_kitchen (
  order_id uuid,
  notes    jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."send_order_to_kitchen"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_line_preparation (
  line  uuid,
  state text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_line_preparation"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.attach_engagement_recording (
  engagement uuid,
  file       uuid,
  language   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_recording uuid;
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type" into v_tenant, v_type
  from "better_supabase"."engagements" x where x."id" = attach_engagement_recording.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if not exists (
    select 1 from "better_supabase"."ai_files" fx
    where fx."id" = attach_engagement_recording.file
      and fx."organization_id"::text = v_tenant::text
      and fx."status" = 'ready'
      and (auth.role() = 'service_role' or fx."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_tenant, 'engagements.manage'), false))
  ) then
    raise exception 'no such ready file in this organization' using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  insert into "better_supabase"."engagement_recordings" ("tenant_id", "engagement_id", "file_id", "filename", "media_type", "language", "created_by")
  select v_tenant, attach_engagement_recording.engagement, fx."id", fx."filename", fx."media_type", nullif(trim(attach_engagement_recording.language), ''), auth.uid()
  from "better_supabase"."ai_files" fx where fx."id" = attach_engagement_recording.file
  on conflict ("engagement_id", "file_id") do nothing
  returning "id" into v_recording;
  if v_recording is null then
    raise exception 'the file is already a recording of this engagement' using errcode = '23505', hint = 'ENGAGEMENT_RECORDING_EXISTS';
  end if;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = attach_engagement_recording.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.recorded', jsonb_build_object('organizationId', v_tenant, 'engagementId', attach_engagement_recording.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || attach_engagement_recording.engagement::text, (v_tenant::text)::text, null, 'better-supabase/engagements');
  perform "better_supabase"."enqueue_job"(queue => 'engagements.transcribe', payload => jsonb_build_object('recordingId', v_recording), dedupe_key => 'engagements.transcribe:' || v_recording::text, dedupe_running => false);
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.book_series (
  service        uuid,
  resource       uuid,
  starts_at      timestamp with time zone,
  rule           jsonb,
  customer       jsonb,
  skip_conflicts boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(book_series.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
  v_tenant uuid;
  v_tz text;
  v_series "better_supabase"."booking_series"%rowtype;
  v_at timestamptz;
  v_booking jsonb;
  v_booked jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = book_series.service and "active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    v_user := coalesce(nullif(v_customer ->> 'userId', '')::uuid, v_user);
  elsif not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false)) then
    raise exception 'not allowed to book' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  else
    v_customer := v_customer || jsonb_build_object('email', coalesce(v_customer ->> 'email', auth.email()));
  end if;
  select "tz" into v_tz from "better_supabase"."booking_resources" where "id" = book_series.resource and "tenant_id" = v_tenant and "active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_tz := coalesce(nullif(book_series.rule ->> 'tz', ''), v_tz);
  insert into "better_supabase"."booking_series" ("tenant_id", "service_id", "resource_id", "rule", "starts_at", "tz", "customer_name", "customer_email", "customer_user_id", "created_by")
  values (v_tenant, book_series.service, book_series.resource, book_series.rule - 'tz', book_series.starts_at, v_tz, v_customer ->> 'name', lower(v_customer ->> 'email'), v_user, auth.uid())
  returning * into v_series;
  for v_at in select t from "better_supabase"."booking_series_starts"(book_series.rule, book_series.starts_at, v_tz) t loop
    begin
      v_booking := "better_supabase"."place_booking"(book_series.service, book_series.resource, v_at, v_customer, true, v_user);
      update "better_supabase"."bookings" set "series_id" = v_series."id" where "id" = (v_booking ->> 'id')::uuid;
      v_booked := v_booked || jsonb_build_array((v_booking - 'accessToken') || jsonb_build_object('seriesId', v_series."id"));
    exception when sqlstate '23P01' then
      if not coalesce(book_series.skip_conflicts, false) then
        raise exception 'an occurrence is not an open slot' using errcode = '23P01', hint = 'BOOKING_SERIES_CONFLICT';
      end if;
      v_skipped := v_skipped || jsonb_build_array(v_at);
    end;
  end loop;
  if jsonb_array_length(v_booked) = 0 then
    raise exception 'no occurrence is an open slot' using errcode = '23P01', hint = 'BOOKING_SERIES_CONFLICT';
  end if;
  update "better_supabase"."booking_series" set "ends_at" = ((v_booked -> -1) ->> 'endsAt')::timestamptz where "id" = v_series."id"
  returning * into v_series;
  return jsonb_build_object('series', jsonb_build_object('id', v_series."id", 'organizationId', v_series."tenant_id"::text, 'serviceId', v_series."service_id", 'resourceId', v_series."resource_id", 'rule', v_series."rule", 'startsAt', v_series."starts_at", 'tz', v_series."tz", 'customerName', v_series."customer_name", 'customerEmail', v_series."customer_email", 'customerUserId', v_series."customer_user_id", 'status', v_series."status", 'endsAt', v_series."ends_at", 'createdAt', v_series."created_at"), 'bookings', v_booked, 'skipped', v_skipped);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.book_with_credit (
  pass_id   uuid,
  service   uuid,
  resource  uuid,
  starts_at timestamp with time zone,
  customer  jsonb                    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
  v_tenant uuid;
  v_booking jsonb;
  v_entry "better_supabase"."pass_credit_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_pass from "better_supabase"."passes" x where x."id" = book_with_credit.pass_id for update;
  if not found or not (v_pass."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.manage'), false))) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  if v_pass."status" <> 'active' then
    raise exception 'the pass is revoked' using errcode = '55000', hint = 'PASS_REVOKED';
  end if;
  if v_pass."uses_allowed" is null or v_pass."booking_id" is not null then
    raise exception 'only a pass with a number of uses and no booking of its own pays for bookings' using errcode = '22023', hint = 'PASS_NOT_CREDITS';
  end if;
  if v_pass."resource_id" is not null and v_pass."resource_id" <> book_with_credit.resource then
    raise exception 'the pass is for another resource' using errcode = '22023', hint = 'PASS_WRONG_RESOURCE';
  end if;
  if book_with_credit.starts_at < v_pass."valid_from" or (v_pass."valid_until" is not null and book_with_credit.starts_at >= v_pass."valid_until") then
    raise exception 'the pass is not valid when the class starts' using errcode = '22023', hint = 'PASS_NOT_VALID';
  end if;
  if v_pass."uses" >= v_pass."uses_allowed" then
    raise exception 'the pass has no credits left' using errcode = '55000', hint = 'PASS_CREDITS_USED_UP';
  end if;
  select sv."tenant_id" into v_tenant from "better_supabase"."booking_services" sv where sv."id" = book_with_credit.service;
  if v_tenant is distinct from v_pass."tenant_id" then
    raise exception 'the service does not exist in the pass''s organization' using errcode = 'P0002', hint = 'PASS_BOOKING_NOT_FOUND';
  end if;
  v_booking := "better_supabase"."hold_booking"(book_with_credit.service, book_with_credit.resource, book_with_credit.starts_at,
    coalesce(book_with_credit.customer, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('userId', v_pass."holder_user_id", 'name', v_pass."holder_name", 'email', v_pass."holder_email")), true);
  insert into "better_supabase"."pass_credit_entries" ("tenant_id", "pass_id", "booking_id", "delta", "reason", "created_by")
  values (v_pass."tenant_id", v_pass."id", (v_booking ->> 'id')::uuid, -1, 'booking', auth.uid())
  returning * into v_entry;
  update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
  where x."id" = v_pass."id";
  perform "better_supabase".emit_event('pass.credit_used', jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id"), 'passes/' || v_entry."pass_id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_used',
    category => 'access',
    target_type => 'pass',
    record_id => v_entry."pass_id"::text,
    summary => 'booked with a credit of pass',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id")
  );
  return (v_booking - 'accessToken') || jsonb_build_object('passId', v_pass."id", 'creditsLeft', v_pass."uses_allowed" - v_pass."uses" - 1);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.booking_series_starts (
  rule        jsonb,
  first_start timestamp with time zone,
  tz          text
)
  RETURNS SETOF timestamp WITH time zone
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_freq text := booking_series_starts.rule ->> 'freq';
  v_interval integer;
  v_days integer[];
  v_count integer;
  v_until timestamptz;
  v_local timestamp;
  v_week0 date;
  v_date date;
  v_at timestamptz;
  v_n integer := 0;
begin
  if jsonb_typeof(booking_series_starts.rule) is distinct from 'object' or v_freq is null or v_freq not in ('daily', 'weekly') then
    raise exception 'rule.freq is daily or weekly' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = booking_series_starts.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  begin
    v_interval := coalesce((booking_series_starts.rule ->> 'interval')::integer, 1);
    v_count := (booking_series_starts.rule ->> 'count')::integer;
    v_until := (booking_series_starts.rule ->> 'until')::timestamptz;
    v_days := array(select jsonb_array_elements_text(coalesce(booking_series_starts.rule -> 'weekdays', '[]'::jsonb))::integer);
  exception when others then
    raise exception 'rule.interval and rule.count are integers, rule.until a timestamp and rule.weekdays a list of 1 to 7' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end;
  if v_interval not between 1 and 52 then
    raise exception 'rule.interval is between 1 and 52' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if v_count is null and v_until is null then
    raise exception 'a rule needs count or until' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if v_count is not null and v_count not between 1 and 366 then
    raise exception 'rule.count is between 1 and 366' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if v_until is not null and v_until < booking_series_starts.first_start then
    raise exception 'rule.until is before the first occurrence' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if exists (select 1 from unnest(v_days) d where d not between 1 and 7) then
    raise exception 'rule.weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  v_local := booking_series_starts.first_start at time zone booking_series_starts.tz;
  if cardinality(v_days) = 0 then
    v_days := array[extract(isodow from v_local)::integer];
  end if;
  v_week0 := v_local::date - (extract(isodow from v_local)::integer - 1);
  for v_offset in 0..730 loop
    v_date := v_local::date + v_offset;
    if (v_freq = 'daily' and v_offset % v_interval = 0)
      or (v_freq = 'weekly' and extract(isodow from v_date)::integer = any (v_days) and ((v_date - v_week0) / 7) % v_interval = 0) then
      v_at := (v_date + v_local::time) at time zone booking_series_starts.tz;
      exit when v_until is not null and v_at > v_until;
      return next v_at;
      v_n := v_n + 1;
      exit when v_n >= coalesce(v_count, 366);
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bump_kitchen_ticket (
  order_id uuid,
  station  uuid,
  state    text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order record;
  v_least integer;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = bump_kitchen_ticket.order_id;
  if v_order.id is null then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.prepare'), false) or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to run this kitchen' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if array_position(array['queued', 'preparing', 'ready', 'served'], bump_kitchen_ticket.state) is null then
    raise exception 'state must be queued, preparing, ready or served' using errcode = '22023', hint = 'ORDERS_PREPARATION_STATE_INVALID';
  end if;
  update "better_supabase"."order_line_preparations" p set
    "started_at" = case when array_position(array['queued', 'preparing', 'ready', 'served'], bump_kitchen_ticket.state) >= 2 then coalesce(p."started_at", now()) end,
    "ready_at" = case when array_position(array['queued', 'preparing', 'ready', 'served'], bump_kitchen_ticket.state) >= 3 then coalesce(p."ready_at", now()) end,
    "served_at" = case when array_position(array['queued', 'preparing', 'ready', 'served'], bump_kitchen_ticket.state) >= 4 then coalesce(p."served_at", now()) end,
    "state" = bump_kitchen_ticket.state,
    "updated_at" = now(),
    "updated_by" = auth.uid()
  where p."order_id" = v_order.id
    and (bump_kitchen_ticket.station is null or p."station_id" = bump_kitchen_ticket.station)
    and array_position(array['queued', 'preparing', 'ready', 'served'], p."state") < array_position(array['queued', 'preparing', 'ready', 'served'], bump_kitchen_ticket.state);
  get diagnostics v_count = row_count;
  if v_count > 0 then
    select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_order.id;
  select min(array_position(array['queued', 'preparing', 'ready', 'served'], p."state")) into v_least from "better_supabase"."order_line_preparations" p where p."order_id" = v_order.id;
  if v_least >= array_position(array['queued', 'preparing', 'ready', 'served'], 'ready') then
    perform "better_supabase".emit_event('order.prepared', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer), 'orders/' || v_order.id::text, (v_order.tenant)::text, 'order.prepared:' || v_order.id::text, 'better-supabase/orders');
  end if;
  if v_least = array_position(array['queued', 'preparing', 'ready', 'served'], 'served') then
    perform "better_supabase".emit_event('order.served', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer), 'orders/' || v_order.id::text, (v_order.tenant)::text, 'order.served:' || v_order.id::text, 'better-supabase/orders');
  end if;
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_booking_series (
  booking uuid,
  scope   text DEFAULT 'following'::text,
  reason  text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = cancel_booking_series.booking;
  if not found or not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) or (v_booking."customer_user_id" = auth.uid() and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if cancel_booking_series.scope is null or cancel_booking_series.scope not in ('one', 'following') then
    raise exception 'scope is one or following' using errcode = '22023', hint = 'BOOKING_SCOPE_INVALID';
  end if;
  for v_id in
    select bk."id" from "better_supabase"."bookings" bk
    where bk."status" <> 'cancelled'
      and (bk."id" = v_booking."id"
        or (cancel_booking_series.scope = 'following' and bk."series_id" = v_booking."series_id"
          and lower(bk."during") >= lower(v_booking."during")))
    order by lower(bk."during")
  loop
    perform "better_supabase"."change_booking"(v_id, 'cancelled', cancel_booking_series.reason, null);
    v_count := v_count + 1;
  end loop;
  if cancel_booking_series.scope = 'following' and v_booking."series_id" is not null then
    update "better_supabase"."booking_series" sr set
      "status" = case when exists (
        select 1 from "better_supabase"."bookings" bk where bk."series_id" = sr."id" and bk."status" <> 'cancelled'
      ) then 'ended' else 'cancelled' end,
      "ends_at" = (select max(upper(bk."during")) from "better_supabase"."bookings" bk where bk."series_id" = sr."id" and bk."status" <> 'cancelled'),
      "updated_at" = now()
    where sr."id" = v_booking."series_id";
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.change_booking (
  booking      uuid,
  to_status    text,
  reason       text,
  access_token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid := change_booking.booking;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_id for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false))
    or (change_booking.access_token is not null and v_booking."access_hash" = encode(extensions.digest(convert_to(change_booking.access_token, 'utf8'), 'sha256'), 'hex'))
    or (change_booking.access_token is null and v_booking."customer_user_id" = auth.uid() and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    if v_booking."status" <> 'hold' or v_booking."hold_expires_at" <= now() then
      raise exception 'the hold has expired or was cancelled' using errcode = '22023', hint = 'BOOKING_HOLD_EXPIRED';
    end if;
    update "better_supabase"."bookings" bk set "status" = 'confirmed', "hold_expires_at" = null, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_start") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_user_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  elsif change_booking.to_status = 'cancelled' then
    if v_booking."status" = 'cancelled' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = change_booking.reason, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    if v_booking."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_booking."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    perform "better_supabase".emit_event('booking.cancelled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  else
    raise exception 'change a booking to confirmed or cancelled' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_kitchen_station (
  station uuid
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
  select s."tenant_id" into v_tenant from "better_supabase"."kitchen_stations" s where s."id" = delete_kitchen_station.station;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to run this kitchen' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  delete from "better_supabase"."kitchen_stations" s where s."id" = delete_kitchen_station.station;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.engagement_notes (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('engagementId', nx."engagement_id", 'organizationId', nx."tenant_id", 'summary', nx."summary", 'actionItems', nx."action_items", 'model', nx."model", 'source', nx."source", 'createdBy', nx."created_by", 'createdAt', nx."created_at", 'updatedAt', nx."updated_at") from "better_supabase"."engagement_notes" nx where nx."engagement_id" = engagement_notes.engagement
$function$;

CREATE OR REPLACE FUNCTION better_supabase.engagement_recordings (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") order by rx."created_at", rx."id"), '[]'::jsonb)
  from "better_supabase"."engagement_recordings" rx
  where rx."engagement_id" = engagement_recordings.engagement
$function$;

CREATE OR REPLACE FUNCTION better_supabase.engagement_transcript (
  recording uuid,
  after     integer,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(p.value order by p.position), '[]'::jsonb)
  from (
    select jsonb_build_object('position', sx."position", 'speaker', sx."speaker", 'speakerUserId', sx."speaker_user_id", 'startMs', sx."starts_ms", 'endMs', sx."ends_ms", 'text', sx."text", 'confidence', sx."confidence") as value, sx."position" as position
    from "better_supabase"."engagement_transcript_segments" sx
    where sx."recording_id" = engagement_transcript.recording
      and sx."position" > coalesce(engagement_transcript.after, 0)
    order by sx."position"
    limit least(greatest(coalesce(engagement_transcript.page_size, 500), 1), 5000)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.engagement_with_transcripts (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'engagement', to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()),
    'segments', coalesce((
      select jsonb_agg(jsonb_build_object('position', sx."position", 'speaker', sx."speaker", 'speakerUserId', sx."speaker_user_id", 'startMs', sx."starts_ms", 'endMs', sx."ends_ms", 'text', sx."text", 'confidence', sx."confidence") || jsonb_build_object('recordingId', rx."id") order by rx."created_at", rx."id", sx."position")
      from "better_supabase"."engagement_recordings" rx
      join "better_supabase"."engagement_transcript_segments" sx on sx."recording_id" = rx."id"
      where rx."engagement_id" = x."id"
    ), '[]'::jsonb)
  )
  from "better_supabase"."engagements" x
  where x."id" = engagement_with_transcripts.engagement
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fail_engagement_recording (
  recording uuid,
  error     text
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with failed as (
    update "better_supabase"."engagement_recordings" rx set "status" = 'failed', "error" = left(fail_engagement_recording.error, 2000)
    where rx."id" = fail_engagement_recording.recording and rx."status" <> 'transcribed'
    returning 1
  )
  select exists (select 1 from failed)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_booking_series (
  series_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', sr."id", 'organizationId', sr."tenant_id"::text, 'serviceId', sr."service_id", 'resourceId', sr."resource_id", 'rule', sr."rule", 'startsAt', sr."starts_at", 'tz', sr."tz", 'customerName', sr."customer_name", 'customerEmail', sr."customer_email", 'customerUserId', sr."customer_user_id", 'status', sr."status", 'endsAt', sr."ends_at", 'createdAt', sr."created_at") || jsonb_build_object('bookings', coalesce((
    select jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_user_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") order by lower(bk."during"))
    from "better_supabase"."bookings" bk where bk."series_id" = sr."id"
  ), '[]'::jsonb))
  from "better_supabase"."booking_series" sr
  where sr."id" = get_booking_series.series_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_engagement_recording (
  recording uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at")
  from "better_supabase"."engagement_recordings" rx
  where rx."id" = get_engagement_recording.recording
$function$;

CREATE OR REPLACE FUNCTION better_supabase.kitchen_queue (
  tenant    uuid,
  station   uuid,
  states    text[],
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(ticket order by ticket ->> 'sentAt', ticket ->> 'orderId'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'orderId', o."id",
      'number', o."number",
      'sentAt', min(p."queued_at"),
      'lines', jsonb_agg(jsonb_build_object('lineId', p."order_line_id", 'orderId', p."order_id", 'stationId', p."station_id", 'title', l."title", 'sku', l."sku", 'quantity', l."quantity", 'position', l."position", 'state', p."state", 'note', p."note", 'queuedAt', p."queued_at", 'startedAt', p."started_at", 'readyAt', p."ready_at", 'servedAt', p."served_at") order by l."position", l."id")
    ) as ticket
    from "better_supabase"."order_line_preparations" p
    join "better_supabase"."order_lines" l on l."id" = p."order_line_id"
    join "better_supabase"."orders" o on o."id" = p."order_id"
    where p."tenant_id" = kitchen_queue.tenant
      and (kitchen_queue.station is null or p."station_id" = kitchen_queue.station)
      and p."state" = any (coalesce(kitchen_queue.states, array['queued', 'preparing', 'ready']))
    group by o."id", o."number"
    order by min(p."queued_at"), o."id"
    limit least(greatest(coalesce(kitchen_queue.page_size, 100), 1), 500)
  ) tickets
$function$;

CREATE OR REPLACE FUNCTION better_supabase.kitchen_stations (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', s."id", 'organizationId', s."tenant_id", 'key', s."key", 'name', s."name", 'position', s."position", 'isDefault', s."is_default", 'active', s."active", 'productIds', coalesce((select jsonb_agg(r."product_id" order by r."product_id") from "better_supabase"."kitchen_routes" r where r."station_id" = s."id"), '[]'::jsonb), 'createdAt', s."created_at", 'updatedAt', s."updated_at") order by s."position", s."name"), '[]'::jsonb)
  from "better_supabase"."kitchen_stations" s
  where s."tenant_id" = kitchen_stations.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_bookings (
  tenant      uuid,
  range_start timestamp with time zone,
  range_end   timestamp with time zone,
  resource    uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_user_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") order by lower(bk."during"), bk."id"), '[]'::jsonb)
  from "better_supabase"."bookings" bk
  where bk."tenant_id" = list_bookings.tenant
    and bk."during" && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk."resource_id" = list_bookings.resource)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_pass_credits (
  pass_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
begin
  select * into v_pass from "better_supabase"."passes" x where x."id" = list_pass_credits.pass_id;
  if not found or not (v_pass."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.read'), false))) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', e."id", 'organizationId', e."tenant_id"::text, 'passId', e."pass_id", 'bookingId', e."booking_id", 'delta', e."delta", 'reason', e."reason", 'createdBy', e."created_by", 'createdAt', e."created_at") order by e."created_at" desc, e."id")
    from "better_supabase"."pass_credit_entries" e where e."pass_id" = v_pass."id"
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_booking (
  booking   uuid,
  starts_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."bookings"%rowtype;
  v_booking "better_supabase"."bookings"%rowtype;
  v_capacity integer;
  v_length interval;
  v_before interval;
  v_after interval;
  v_moved boolean := false;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_old from "better_supabase"."bookings" bk where bk."id" = move_booking.booking for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if v_old."status" = 'cancelled' then
    raise exception 'a cancelled booking can''t move' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  v_booking := v_old;
  if lower(v_old."during") = move_booking.starts_at then
    return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
  end if;
  v_length := upper(v_old."during") - lower(v_old."during");
  v_before := lower(v_old."during") - lower(v_old."blocked");
  v_after := upper(v_old."blocked") - upper(v_old."during");
  update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'bs:moving'
  where bk."id" = v_old."id";
  if not exists (
    select 1 from "better_supabase"."booking_slots"(v_old."service_id", move_booking.starts_at, move_booking.starts_at + v_length, null, v_old."resource_id") t
    where t.starts_at = move_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs where rs."id" = v_old."resource_id";
  for v_seat in 1..v_capacity loop
    begin
      update "better_supabase"."bookings" bk set "status" = v_old."status", "hold_expires_at" = v_old."hold_expires_at", "cancelled_at" = null, "cancel_reason" = null,
        "seat" = v_seat,
        "during" = tstzrange(move_booking.starts_at, move_booking.starts_at + v_length),
        "blocked" = tstzrange(move_booking.starts_at - v_before, move_booking.starts_at + v_length + v_after),
        "updated_at" = now()
      where bk."id" = v_old."id"
      returning * into v_booking;
      v_moved := true;
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if not v_moved then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_booking."status" = 'confirmed' then
    if v_old."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_old."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_start") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_user_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
  end if;
  perform "better_supabase".emit_event('booking.rescheduled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.order_board (
  tenant    uuid,
  since     timestamp with time zone,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(card order by card ->> 'sentAt', card ->> 'orderId'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'orderId', o."id",
      'number', o."number",
      'customerId', o."customer_id",
      'status', o."status",
      'state', (array['queued', 'preparing', 'ready', 'served'])[min(array_position(array['queued', 'preparing', 'ready', 'served'], p."state"))],
      'sentAt', min(p."queued_at"),
      'readyAt', case when bool_and(p."ready_at" is not null) then max(p."ready_at") end,
      'servedAt', case when bool_and(p."served_at" is not null) then max(p."served_at") end,
      'counts', jsonb_build_object(
        'queued', count(*) filter (where p."state" = 'queued'),
        'preparing', count(*) filter (where p."state" = 'preparing'),
        'ready', count(*) filter (where p."state" = 'ready'),
        'served', count(*) filter (where p."state" = 'served')
      )
    ) as card
    from "better_supabase"."order_line_preparations" p
    join "better_supabase"."orders" o on o."id" = p."order_id"
    where p."tenant_id" = order_board.tenant
    group by o."id", o."number", o."customer_id", o."status"
    having min(p."queued_at") >= coalesce(order_board.since, now() - interval '1 day')
    order by min(p."queued_at"), o."id"
    limit least(greatest(coalesce(order_board.page_size, 200), 1), 1000)
  ) cards
$function$;

CREATE OR REPLACE FUNCTION better_supabase.order_line_preparations_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'UPDATE' and old."state" = new."state" and old."station_id" is not distinct from new."station_id" then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('lineId', new."order_line_id", 'orderId', new."order_id", 'stationId', new."station_id", 'state', new."state"), 'preparation', 'kitchen:' || new."tenant_id"::text, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_engagement_recordings (
  batch integer
)
  RETURNS uuid[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(array_agg(p.id order by p.at), '{}')
  from (
    select rx."id" as id, rx."created_at" as at
    from "better_supabase"."engagement_recordings" rx
    where rx."status" = 'pending'
    order by rx."created_at"
    limit least(greatest(coalesce(pending_engagement_recordings.batch, 20), 1), 200)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.place_booking (
  service       uuid,
  resource      uuid,
  starts_at     timestamp with time zone,
  customer      jsonb,
  confirm       boolean,
  customer_user uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service "better_supabase"."booking_services"%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking "better_supabase"."bookings"%rowtype;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_service from "better_supabase"."booking_services" sv where sv."id" = place_booking.service and sv."active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
    where rs."id" = place_booking.resource and rs."tenant_id" = v_service."tenant_id" and rs."active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service."duration");
  v_blocked := tstzrange(place_booking.starts_at - v_service."buffer_before", upper(v_during) + v_service."buffer_after");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_booking_reserve"(uuid, uuid, uuid, tstzrange, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid, $4::tstzrange, $5::jsonb)', v_hook::oid::regproc)
        using v_service."tenant_id", place_booking.service, place_booking.resource, v_during, v_customer;
    end if;
  end;
  perform "better_supabase"."expire_booking_holds_in"(place_booking.resource, v_blocked);
  if not exists (
    select 1 from "better_supabase"."booking_slots"(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service."hold_for";
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into "better_supabase"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_user_id", "notes", "access_hash", "created_by")
      values (v_service."tenant_id", place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, v_status, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user, v_customer ->> 'notes', encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid())
      returning * into v_booking;
      v_id := v_booking."id";
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  perform "better_supabase".emit_event('booking.reserved', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  if v_status = 'confirmed' then
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_start") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_user_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  if v_status = 'hold' then
    perform "better_supabase"."enqueue_job"(queue => 'bookings.expire-holds', payload => jsonb_build_object('bookingId', v_id), delay => ceil(extract(epoch from (v_expires - now())))::integer + 1, dedupe_key => 'bookings:expire:' || v_id::text, dedupe_running => false);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_user_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason") || jsonb_build_object('accessToken', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refund_pass_credit()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_entry "better_supabase"."pass_credit_entries"%rowtype;
begin
  if new."status" <> 'cancelled' or old."status" = 'cancelled'
    or new."cancel_reason" is not distinct from 'bs:moving'
    or now() > lower(new."during") - '12 hours'::interval then
    return null;
  end if;
  for v_entry in
    insert into "better_supabase"."pass_credit_entries" ("tenant_id", "pass_id", "booking_id", "delta", "reason", "created_by")
    select spent."tenant_id", spent."pass_id", spent."booking_id", 1, 'refund', auth.uid()
    from "better_supabase"."pass_credit_entries" spent
    where spent."booking_id" = new."id" and spent."reason" = 'booking'
    on conflict ("booking_id", "reason") do nothing
    returning *
  loop
    update "better_supabase"."passes" x set "uses" = greatest(x."uses" - 1, 0), "updated_at" = now()
    where x."id" = v_entry."pass_id";
    perform "better_supabase".emit_event('pass.credit_refunded', jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id"), 'passes/' || v_entry."pass_id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_refunded',
    category => 'access',
    target_type => 'pass',
    record_id => v_entry."pass_id"::text,
    summary => 'refunded a credit to pass',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id")
  );
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reschedule_booking (
  booking   uuid,
  starts_at timestamp with time zone,
  scope     text                     DEFAULT 'one'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_shift interval;
  v_id uuid;
  v_moved jsonb := '[]'::jsonb;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = reschedule_booking.booking;
  if not found or not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) or (v_booking."customer_user_id" = auth.uid() and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if reschedule_booking.scope is null or reschedule_booking.scope not in ('one', 'following') then
    raise exception 'scope is one or following' using errcode = '22023', hint = 'BOOKING_SCOPE_INVALID';
  end if;
  if reschedule_booking.scope = 'one' or v_booking."series_id" is null then
    return jsonb_build_array("better_supabase"."move_booking"(v_booking."id", reschedule_booking.starts_at));
  end if;
  v_shift := reschedule_booking.starts_at - lower(v_booking."during");
  -- Later occurrences move first when the shift is positive, so a series never
  -- collides with itself.
  for v_id in
    select bk."id" from "better_supabase"."bookings" bk
    where bk."series_id" = v_booking."series_id" and bk."status" <> 'cancelled'
      and lower(bk."during") >= lower(v_booking."during")
    order by case when v_shift > interval '0' then lower(bk."during") end desc, lower(bk."during")
  loop
    v_moved := v_moved || jsonb_build_array("better_supabase"."move_booking"(v_id, (select lower(x."during") from "better_supabase"."bookings" x where x."id" = v_id) + v_shift));
  end loop;
  return (select jsonb_agg(m order by (m ->> 'startsAt')::timestamptz) from jsonb_array_elements(v_moved) m);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_permissions (
  role text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case role
    when 'owner' then array['*']
    when 'admin' then array[
      'customers.read', 'customers.write', 'reports.read',
      'organization.read', 'organization.update',
      'members.read', 'members.invite', 'members.remove', 'members.update_role',
      'billing.read', 'billing.manage', 'audit.read',
      'settings.read', 'settings.update', 'settings.manage',
      'api_keys.manage', 'api_keys.own',
      'comments.read', 'comments.create', 'comments.moderate', 'activity.read',
      'tags.read', 'tags.apply', 'tags.manage',
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish', 'workflow.admin',
      'inbox.read', 'inbox.reply', 'inbox.assign', 'inbox.manage',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_chat.admin',
      'ai.read', 'ai.create', 'ai.share', 'ai.admin',
      'attachments.read', 'attachments.upload', 'attachments.manage', 'sso.manage',
      'waitlist.manage', 'teams.read', 'teams.manage', 'catalog.read', 'catalog.manage',
      'inventory.read', 'inventory.manage', 'inventory.reserve', 'inventory.purchase',
      'orders.read', 'orders.manage', 'orders.prepare', 'promotions.read', 'promotions.manage', 'custom_fields.read',
      'custom_fields.manage', 'custom_fields.sensitive.read', 'share_links.read',
      'share_links.create', 'reminders.read', 'reminders.manage', 'imports.manage',
      'views.read', 'views.share', 'relations.read', 'relations.manage', 'bulk.run',
      'calendar.read', 'calendar.write', 'calendar.manage', 'bookings.read', 'bookings.create',
      'bookings.manage', 'versions.read', 'versions.create', 'versions.restore',
      'versions.manage', 'trash.read', 'trash.create', 'trash.restore', 'trash.manage',
      'reactions.read', 'reactions.create', 'reactions.manage', 'approvals.read',
      'approvals.request', 'approvals.manage', 'access_requests.read', 'access_requests.create',
      'access_requests.manage', 'documents.read', 'documents.write', 'documents.manage',
      'drive.read', 'drive.create', 'drive.manage', 'forms.read', 'forms.submit',
      'forms.review', 'forms.manage', 'templates.read', 'templates.apply', 'templates.manage',
      'time_tracking.read', 'time_tracking.track', 'time_tracking.approve', 'time_tracking.manage',
      'service_principals.read', 'service_principals.manage', 'pipelines.read',
      'pipelines.manage', 'parties.read', 'parties.write', 'parties.manage', 'engagements.read',
      'engagements.write', 'engagements.manage', 'deals.read', 'deals.write', 'deals.manage',
      'work_items.read', 'work_items.write', 'work_items.manage', 'quotes.read',
      'quotes.write', 'quotes.manage', 'invoices.read', 'invoices.write', 'invoices.manage',
      'sla.read', 'sla.manage', 'targets.read', 'targets.manage', 'hiring.read',
      'hiring.write', 'hiring.manage', 'employees.read', 'employees.write', 'employees.view_sensitive',
      'webhooks.read', 'webhooks.manage', 'organization.export',
      'rules.read', 'rules.edit', 'rules.publish', 'rules.admin',
      'assets.read', 'assets.manage', 'assets.assign',
      'scores.read', 'scores.manage', 'scores.compute',
      'moderation.read', 'moderation.report', 'moderation.manage', 'moderation.ban',
      'enrollments.read', 'enrollments.enroll', 'enrollments.manage',
      'dispatch.read', 'dispatch.manage', 'dispatch.work', 'shipments.read', 'shipments.manage',
      'signatures.read', 'signatures.request', 'signatures.manage',
      'contracts.read', 'contracts.write', 'contracts.manage',
      'controls.read', 'controls.manage', 'controls.collect', 'controls.acknowledge',
      'incidents.read', 'incidents.write', 'incidents.manage',
      'courses.read', 'courses.enroll', 'courses.manage'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'tags.read', 'tags.apply', 'onboarding.read', 'usage.read', 'usage.record', 'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'inbox.read', 'inbox.reply',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share',
      'ai.read', 'ai.create', 'ai.share',
      'attachments.read', 'attachments.upload', 'teams.read', 'catalog.read', 'inventory.read',
      'orders.read', 'orders.prepare', 'promotions.read', 'custom_fields.read', 'share_links.read',
      'share_links.create', 'reminders.read', 'reminders.manage', 'views.read',
      'views.share', 'relations.read', 'relations.manage', 'calendar.read', 'calendar.write',
      'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'trash.read',
      'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read',
      'approvals.request', 'access_requests.read', 'access_requests.create', 'documents.read',
      'documents.write', 'drive.read', 'drive.create', 'forms.read', 'forms.submit',
      'templates.read', 'templates.apply', 'time_tracking.read', 'time_tracking.track',
      'pipelines.read', 'parties.read', 'parties.write', 'engagements.read', 'engagements.write',
      'deals.read', 'deals.write', 'work_items.read', 'work_items.write', 'quotes.read',
      'quotes.write', 'invoices.read', 'sla.read', 'targets.read', 'hiring.read',
      'employees.read', 'rules.read', 'assets.read', 'scores.read',
      'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit',
      'dispatch.read', 'dispatch.work', 'shipments.read', 'signatures.read',
      'contracts.read', 'contracts.write', 'controls.read', 'controls.collect',
      'controls.acknowledge', 'incidents.read', 'incidents.write', 'courses.read'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_engagement_notes (
  engagement uuid,
  notes      jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_summary text := nullif(trim(save_engagement_notes.notes ->> 'summary'), '');
  v_items jsonb := coalesce(save_engagement_notes.notes -> 'actionItems', '[]'::jsonb);
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type" into v_tenant, v_type
  from "better_supabase"."engagements" x where x."id" = save_engagement_notes.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if v_summary is null or length(v_summary) > 20000 then
    raise exception 'notes need a summary of at most 20000 characters' using errcode = '22023', hint = 'ENGAGEMENT_NOTES_INVALID';
  end if;
  if jsonb_typeof(v_items) <> 'array' or exists (
    select 1 from jsonb_array_elements(v_items) i
    where jsonb_typeof(i.value) <> 'object' or jsonb_typeof(i.value -> 'text') is distinct from 'string'
  ) then
    raise exception 'actionItems must be a list of { text }' using errcode = '22023', hint = 'ENGAGEMENT_NOTES_INVALID';
  end if;
  insert into "better_supabase"."engagement_notes" ("engagement_id", "tenant_id", "summary", "action_items", "model", "source", "created_by")
  values (save_engagement_notes.engagement, v_tenant, v_summary, v_items, nullif(save_engagement_notes.notes ->> 'model', ''),
    case when save_engagement_notes.notes ->> 'source' = 'member' then 'member' else 'ai' end, auth.uid())
  on conflict ("engagement_id") do update set
    "summary" = excluded."summary", "action_items" = excluded."action_items",
    "model" = excluded."model", "source" = excluded."source", "updated_at" = now();
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = save_engagement_notes.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.summarized', jsonb_build_object('organizationId', v_tenant, 'engagementId', save_engagement_notes.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || save_engagement_notes.engagement::text, (v_tenant::text)::text, 'engagement.summarized:' || save_engagement_notes.engagement::text || ':' || md5(save_engagement_notes.notes::text), 'better-supabase/engagements');
  return (select jsonb_build_object('engagementId', nx."engagement_id", 'organizationId', nx."tenant_id", 'summary', nx."summary", 'actionItems', nx."action_items", 'model', nx."model", 'source', nx."source", 'createdBy', nx."created_by", 'createdAt', nx."created_at", 'updatedAt', nx."updated_at") from "better_supabase"."engagement_notes" nx where nx."engagement_id" = save_engagement_notes.engagement);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_engagement_transcript (
  recording uuid,
  segments  jsonb,
  attrs     jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_recording uuid := save_engagement_transcript.recording;
  v_engagement uuid;
  v_tenant uuid;
  v_type text;
  v_item jsonb;
  v_position integer;
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select rx."engagement_id", rx."tenant_id", x."type" into v_engagement, v_tenant, v_type
  from "better_supabase"."engagement_recordings" rx
  join "better_supabase"."engagements" x on x."id" = rx."engagement_id"
  where rx."id" = v_recording and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false))
  for update of rx;
  if v_engagement is null then
    raise exception 'no such recording you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_RECORDING_NOT_FOUND';
  end if;
  if jsonb_typeof(save_engagement_transcript.segments) is distinct from 'array'
    or jsonb_array_length(save_engagement_transcript.segments) > 20000 then
    raise exception 'segments must be a list of at most 20000 { startMs, endMs, text }' using errcode = '22023', hint = 'ENGAGEMENT_TRANSCRIPT_INVALID';
  end if;
  for v_item, v_position in select value, ordinality from jsonb_array_elements(save_engagement_transcript.segments) with ordinality loop
    if jsonb_typeof(v_item) is distinct from 'object'
      or jsonb_typeof(v_item -> 'text') is distinct from 'string'
      or jsonb_typeof(v_item -> 'startMs') is distinct from 'number'
      or jsonb_typeof(v_item -> 'endMs') is distinct from 'number'
      or (v_item ->> 'startMs')::numeric < 0
      or (v_item ->> 'endMs')::numeric < (v_item ->> 'startMs')::numeric
      or jsonb_typeof(coalesce(v_item -> 'confidence', 'null')) not in ('number', 'null') then
      raise exception 'segment % needs startMs <= endMs and a text', v_position using errcode = '22023', hint = 'ENGAGEMENT_TRANSCRIPT_INVALID';
    end if;
  end loop;
  delete from "better_supabase"."engagement_transcript_segments" sx where sx."recording_id" = v_recording;
  insert into "better_supabase"."engagement_transcript_segments" ("recording_id", "tenant_id", "position", "speaker", "speaker_user_id", "starts_ms", "ends_ms", "text", "confidence")
  select v_recording, v_tenant, i.ordinality::integer, nullif(i.value ->> 'speaker', ''), nullif(i.value ->> 'speakerUserId', '')::uuid,
    round((i.value ->> 'startMs')::numeric)::integer, round((i.value ->> 'endMs')::numeric)::integer, i.value ->> 'text', (i.value ->> 'confidence')::real
  from jsonb_array_elements(save_engagement_transcript.segments) with ordinality i;
  update "better_supabase"."engagement_recordings" rx set
    "status" = 'transcribed',
    "error" = null,
    "language" = coalesce(nullif(save_engagement_transcript.attrs ->> 'language', ''), rx."language"),
    "duration_seconds" = coalesce((save_engagement_transcript.attrs ->> 'durationSeconds')::integer, rx."duration_seconds"),
    "model" = coalesce(nullif(save_engagement_transcript.attrs ->> 'model', ''), rx."model"),
    "transcribed_at" = now()
  where rx."id" = v_recording;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.transcribed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || v_engagement::text, (v_tenant::text)::text, 'engagement.transcribed:' || v_recording::text || ':' || md5(save_engagement_transcript.segments::text), 'better-supabase/engagements');
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_kitchen_station (
  tenant  uuid,
  station uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_kitchen_station.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to run this kitchen' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if jsonb_typeof(attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'ORDERS_KITCHEN_STATION_INVALID';
  end if;
  if attrs ? 'productIds' and jsonb_typeof(attrs -> 'productIds') is distinct from 'array' then
    raise exception 'productIds must be a list' using errcode = '22023', hint = 'ORDERS_KITCHEN_STATION_INVALID';
  end if;
  if coalesce((attrs ->> 'default')::boolean, false) then
    update "better_supabase"."kitchen_stations" s set "is_default" = false
    where s."tenant_id" = save_kitchen_station.tenant and s."is_default" and s."id" is distinct from save_kitchen_station.station;
  end if;
  if save_kitchen_station.station is null then
    insert into "better_supabase"."kitchen_stations" ("tenant_id", "key", "name", "position", "is_default", "active")
    values (save_kitchen_station.tenant, attrs ->> 'key', coalesce(attrs ->> 'name', attrs ->> 'key'), coalesce((attrs ->> 'position')::integer, 0), coalesce((attrs ->> 'default')::boolean, false), coalesce((attrs ->> 'active')::boolean, true))
    returning "id" into v_id;
  else
    update "better_supabase"."kitchen_stations" s set
      "key" = coalesce(attrs ->> 'key', s."key"),
      "name" = coalesce(attrs ->> 'name', s."name"),
      "position" = coalesce((attrs ->> 'position')::integer, s."position"),
      "is_default" = coalesce((attrs ->> 'default')::boolean, s."is_default"),
      "active" = coalesce((attrs ->> 'active')::boolean, s."active"),
      "updated_at" = now()
    where s."id" = save_kitchen_station.station and s."tenant_id" = save_kitchen_station.tenant
    returning s."id" into v_id;
    if v_id is null then
      raise exception 'no such kitchen station' using errcode = 'P0002', hint = 'ORDERS_KITCHEN_STATION_NOT_FOUND';
    end if;
  end if;
  if attrs ? 'productIds' then
    if exists (
      select 1 from jsonb_array_elements_text(attrs -> 'productIds') e(value)
      where not exists (
        select 1 from "better_supabase"."products" p
        where p."id"::text = e.value and p."tenant_id"::text = save_kitchen_station.tenant::text
      )
    ) then
      raise exception 'productIds must name products of this organization' using errcode = '22023', hint = 'ORDERS_KITCHEN_STATION_INVALID';
    end if;
    delete from "better_supabase"."kitchen_routes" r where r."station_id" = v_id;
    insert into "better_supabase"."kitchen_routes" ("product_id", "tenant_id", "station_id")
    select distinct e.value::uuid, save_kitchen_station.tenant, v_id
    from jsonb_array_elements_text(attrs -> 'productIds') e(value)
    on conflict ("product_id") do update set "station_id" = excluded."station_id";
  end if;
  return (select jsonb_build_object('id', s."id", 'organizationId', s."tenant_id", 'key', s."key", 'name', s."name", 'position', s."position", 'isDefault', s."is_default", 'active', s."active", 'productIds', coalesce((select jsonb_agg(r."product_id" order by r."product_id") from "better_supabase"."kitchen_routes" r where r."station_id" = s."id"), '[]'::jsonb), 'createdAt', s."created_at", 'updatedAt', s."updated_at") from "better_supabase"."kitchen_stations" s where s."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_order_to_kitchen (
  order_id uuid,
  notes    jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order record;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = send_order_to_kitchen.order_id;
  if v_order.id is null then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.prepare'), false) or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to run this kitchen' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_order.status in ('cancelled', 'refunded') then
    raise exception 'a cancelled or refunded order can''t go to the kitchen' using errcode = '22023', hint = 'ORDERS_KITCHEN_CLOSED';
  end if;
  if notes is not null and jsonb_typeof(notes) <> 'object' then
    raise exception 'notes must map line ids to text' using errcode = '22023', hint = 'ORDERS_KITCHEN_NOTES_INVALID';
  end if;
  insert into "better_supabase"."order_line_preparations" ("order_line_id", "tenant_id", "order_id", "station_id", "note", "updated_by")
  select l."id", v_order.tenant, v_order.id,
    coalesce(
      (select s."id" from "better_supabase"."kitchen_routes" r join "better_supabase"."kitchen_stations" s on s."id" = r."station_id" where r."product_id" = l."product_id" and s."active"),
      (select s."id" from "better_supabase"."kitchen_stations" s where s."tenant_id" = v_order.tenant and s."is_default" and s."active")
    ),
    left(nullif(trim(send_order_to_kitchen.notes ->> l."id"::text), ''), 500),
    auth.uid()
  from "better_supabase"."order_lines" l
  where l."order_id" = v_order.id
  on conflict ("order_line_id") do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_line_preparation (
  line  uuid,
  state text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_order_id uuid;
  v_order record;
  v_least integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select p."tenant_id", p."order_id" into v_tenant, v_order_id
  from "better_supabase"."order_line_preparations" p where p."order_line_id" = set_line_preparation.line;
  if v_tenant is null then
    raise exception 'the line was not sent to the kitchen' using errcode = 'P0002', hint = 'ORDERS_PREPARATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'orders.prepare'), false) or coalesce(better_supabase.can('tenant', v_tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to run this kitchen' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if array_position(array['queued', 'preparing', 'ready', 'served'], set_line_preparation.state) is null then
    raise exception 'state must be queued, preparing, ready or served' using errcode = '22023', hint = 'ORDERS_PREPARATION_STATE_INVALID';
  end if;
  update "better_supabase"."order_line_preparations" p set
    "started_at" = case when array_position(array['queued', 'preparing', 'ready', 'served'], set_line_preparation.state) >= 2 then coalesce(p."started_at", now()) end,
    "ready_at" = case when array_position(array['queued', 'preparing', 'ready', 'served'], set_line_preparation.state) >= 3 then coalesce(p."ready_at", now()) end,
    "served_at" = case when array_position(array['queued', 'preparing', 'ready', 'served'], set_line_preparation.state) >= 4 then coalesce(p."served_at", now()) end,
    "state" = set_line_preparation.state,
    "updated_at" = now(),
    "updated_by" = auth.uid()
  where p."order_line_id" = set_line_preparation.line;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_order_id;
  select min(array_position(array['queued', 'preparing', 'ready', 'served'], p."state")) into v_least from "better_supabase"."order_line_preparations" p where p."order_id" = v_order_id;
  if v_least >= array_position(array['queued', 'preparing', 'ready', 'served'], 'ready') then
    perform "better_supabase".emit_event('order.prepared', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer), 'orders/' || v_order.id::text, (v_order.tenant)::text, 'order.prepared:' || v_order.id::text, 'better-supabase/orders');
  end if;
  if v_least = array_position(array['queued', 'preparing', 'ready', 'served'], 'served') then
    perform "better_supabase".emit_event('order.served', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer), 'orders/' || v_order.id::text, (v_order.tenant)::text, 'order.served:' || v_order.id::text, 'better-supabase/orders');
  end if;
  return (
    select jsonb_build_object('lineId', p."order_line_id", 'orderId', p."order_id", 'stationId', p."station_id", 'title', l."title", 'sku', l."sku", 'quantity', l."quantity", 'position', l."position", 'state', p."state", 'note', p."note", 'queuedAt', p."queued_at", 'startedAt', p."started_at", 'readyAt', p."ready_at", 'servedAt', p."served_at")
    from "better_supabase"."order_line_preparations" p join "better_supabase"."order_lines" l on l."id" = p."order_line_id"
    where p."order_line_id" = set_line_preparation.line
  );
end;
$function$;

ALTER TABLE "better_supabase"."booking_series"
  ADD CONSTRAINT "booking_series_resource_id_fkey" FOREIGN KEY (resource_id) REFERENCES better_supabase.booking_resources(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."booking_series"
  ADD CONSTRAINT "booking_series_service_id_fkey" FOREIGN KEY (service_id) REFERENCES better_supabase.booking_services(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."bookings"
  ADD CONSTRAINT "bookings_series_id_fkey" FOREIGN KEY (series_id) REFERENCES better_supabase.booking_series(id) ON DELETE SET NULL NOT VALID;

ALTER TABLE "better_supabase"."bookings"
  VALIDATE CONSTRAINT "bookings_series_id_fkey";

ALTER TABLE "better_supabase"."engagement_notes"
  ADD CONSTRAINT "engagement_notes_engagement_id_fkey" FOREIGN KEY (engagement_id) REFERENCES better_supabase.engagements(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."engagement_recordings"
  ADD CONSTRAINT "engagement_recordings_engagement_id_fkey" FOREIGN KEY (engagement_id) REFERENCES better_supabase.engagements(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."engagement_recordings"
  ADD CONSTRAINT "engagement_recordings_file_id_fkey" FOREIGN KEY (file_id) REFERENCES better_supabase.ai_files(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."engagement_transcript_segments"
  ADD CONSTRAINT "engagement_transcript_segments_recording_id_fkey" FOREIGN KEY (recording_id) REFERENCES better_supabase.engagement_recordings(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."kitchen_routes"
  ADD CONSTRAINT "kitchen_routes_product_id_fkey" FOREIGN KEY (product_id) REFERENCES better_supabase.products(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."kitchen_routes"
  ADD CONSTRAINT "kitchen_routes_station_id_fkey" FOREIGN KEY (station_id) REFERENCES better_supabase.kitchen_stations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."order_line_preparations"
  ADD CONSTRAINT "order_line_preparations_order_id_fkey" FOREIGN KEY (order_id) REFERENCES better_supabase.orders(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."order_line_preparations"
  ADD CONSTRAINT "order_line_preparations_order_line_id_fkey" FOREIGN KEY (order_line_id) REFERENCES better_supabase.order_lines(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."order_line_preparations"
  ADD CONSTRAINT "order_line_preparations_station_id_fkey" FOREIGN KEY (station_id) REFERENCES better_supabase.kitchen_stations(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."pass_credit_entries"
  ADD CONSTRAINT "pass_credit_entries_booking_id_fkey" FOREIGN KEY (booking_id) REFERENCES better_supabase.bookings(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."pass_credit_entries"
  ADD CONSTRAINT "pass_credit_entries_pass_id_fkey" FOREIGN KEY (pass_id) REFERENCES better_supabase.passes(id) ON DELETE CASCADE;

CREATE INDEX booking_series_customer_idx ON better_supabase.booking_series USING btree (customer_user_id);

CREATE INDEX booking_series_resource_idx ON better_supabase.booking_series USING btree (resource_id);

CREATE INDEX booking_series_service_idx ON better_supabase.booking_series USING btree (service_id);

CREATE INDEX booking_series_tenant_idx ON better_supabase.booking_series USING btree (tenant_id, starts_at);

CREATE INDEX engagement_recordings_file_idx ON better_supabase.engagement_recordings USING btree (file_id);

CREATE INDEX engagement_recordings_pending_idx ON better_supabase.engagement_recordings USING btree (created_at)
  WHERE (status = 'pending'::text);

CREATE INDEX kitchen_routes_station_idx ON better_supabase.kitchen_routes USING btree (station_id);

CREATE UNIQUE INDEX kitchen_stations_default_idx ON better_supabase.kitchen_stations USING btree (tenant_id)
  WHERE is_default;

CREATE INDEX order_line_preparations_open_idx ON better_supabase.order_line_preparations USING btree (tenant_id, queued_at)
  WHERE (state <> 'served'::text);

CREATE INDEX order_line_preparations_order_idx ON better_supabase.order_line_preparations USING btree (order_id);

CREATE INDEX order_line_preparations_station_idx ON better_supabase.order_line_preparations USING btree (station_id);

CREATE INDEX pass_credit_entries_booking_idx ON better_supabase.pass_credit_entries USING btree (booking_id);

CREATE UNIQUE INDEX pass_credit_entries_once_idx ON better_supabase.pass_credit_entries USING btree (booking_id, reason);

CREATE INDEX pass_credit_entries_pass_idx ON better_supabase.pass_credit_entries USING btree (pass_id, created_at DESC);

CREATE TRIGGER pass_credit_entries_refund
  AFTER UPDATE OF status ON better_supabase.bookings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.refund_pass_credit();

CREATE TRIGGER bs_order_line_preparations_broadcast
  AFTER INSERT OR UPDATE ON better_supabase.order_line_preparations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.order_line_preparations_changed();

CREATE POLICY "booking_series_read" ON "better_supabase"."booking_series"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)) OR (customer_user_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "engagement_notes_read" ON "better_supabase"."engagement_notes"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.engagements ex
  WHERE (ex.id = engagement_notes.engagement_id))));

CREATE POLICY "engagement_recordings_read" ON "better_supabase"."engagement_recordings"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.engagements ex
  WHERE (ex.id = engagement_recordings.engagement_id))));

CREATE POLICY "engagement_transcript_segments_read" ON "better_supabase"."engagement_transcript_segments"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.engagement_recordings rx
  WHERE (rx.id = engagement_transcript_segments.recording_id))));

CREATE POLICY "kitchen_routes_read" ON "better_supabase"."kitchen_routes"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('orders.prepare'::text) AS tenant_ids_with))));

CREATE POLICY "kitchen_stations_read" ON "better_supabase"."kitchen_stations"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('orders.prepare'::text) AS tenant_ids_with))));

CREATE POLICY "order_line_preparations_read" ON "better_supabase"."order_line_preparations"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('orders.prepare'::text) AS tenant_ids_with))));

CREATE POLICY "bs_kitchen_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'kitchen:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 9) IN ( SELECT (t.t)::text AS
    t
   FROM better_supabase.tenant_ids_with('orders.read'::text) t(t)
UNION ALL
 SELECT (t.t)::text AS t
   FROM better_supabase.tenant_ids_with('orders.prepare'::text) t(t)))));

REVOKE ALL ON FUNCTION "api"."attach_engagement_recording"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."attach_engagement_recording"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."book_series"(uuid, uuid, timestamp WITH time zone, jsonb, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."book_series"(uuid, uuid, timestamp WITH time zone, jsonb, jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."book_with_credit"(uuid, uuid, uuid, timestamp WITH time zone, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."book_with_credit"(uuid, uuid, uuid, timestamp WITH time zone, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."booking_series_starts"(jsonb, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."booking_series_starts"(jsonb, timestamp WITH time zone, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."bump_kitchen_ticket"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."bump_kitchen_ticket"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."cancel_booking_series"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_booking_series"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_kitchen_station"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_kitchen_station"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."engagement_notes"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."engagement_notes"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."engagement_recordings"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."engagement_recordings"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."engagement_transcript"(uuid, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."engagement_transcript"(uuid, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."engagement_with_transcripts"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."engagement_with_transcripts"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."fail_engagement_recording"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."fail_engagement_recording"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_booking_series"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_booking_series"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_engagement_recording"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_engagement_recording"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."kitchen_queue"(uuid, uuid, text[], integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."kitchen_queue"(uuid, uuid, text[], integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."kitchen_stations"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."kitchen_stations"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_pass_credits"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_pass_credits"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."move_booking"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."move_booking"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."order_board"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."order_board"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."pending_engagement_recordings"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pending_engagement_recordings"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."reschedule_booking"(uuid, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reschedule_booking"(uuid, timestamp WITH time zone, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_engagement_notes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_engagement_notes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_engagement_transcript"(uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_engagement_transcript"(uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_kitchen_station"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_kitchen_station"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."send_order_to_kitchen"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."send_order_to_kitchen"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_line_preparation"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_line_preparation"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attach_engagement_recording"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attach_engagement_recording"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."book_series"(uuid, uuid, timestamp WITH time zone, jsonb, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."book_series"(uuid, uuid, timestamp WITH time zone, jsonb, jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."book_with_credit"(uuid, uuid, uuid, timestamp WITH time zone, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."book_with_credit"(uuid, uuid, uuid, timestamp WITH time zone, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."booking_series_starts"(jsonb, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."booking_series_starts"(jsonb, timestamp WITH time zone, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."bump_kitchen_ticket"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."bump_kitchen_ticket"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."cancel_booking_series"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_booking_series"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_kitchen_station"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_kitchen_station"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."engagement_notes"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."engagement_notes"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."engagement_recordings"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."engagement_recordings"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."engagement_transcript"(uuid, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."engagement_transcript"(uuid, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."engagement_with_transcripts"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."engagement_with_transcripts"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."fail_engagement_recording"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."fail_engagement_recording"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_booking_series"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_booking_series"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_engagement_recording"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_engagement_recording"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."kitchen_queue"(uuid, uuid, text[], integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."kitchen_queue"(uuid, uuid, text[], integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."kitchen_stations"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."kitchen_stations"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_pass_credits"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_pass_credits"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."move_booking"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."move_booking"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."order_board"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."order_board"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."order_line_preparations_changed"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."pending_engagement_recordings"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pending_engagement_recordings"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."refund_pass_credit"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."reschedule_booking"(uuid, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reschedule_booking"(uuid, timestamp WITH time zone, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_engagement_notes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_engagement_notes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_engagement_transcript"(uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_engagement_transcript"(uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_kitchen_station"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_kitchen_station"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."send_order_to_kitchen"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."send_order_to_kitchen"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_line_preparation"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_line_preparation"(uuid, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."booking_series" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."booking_series" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."engagement_notes" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."engagement_notes" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."engagement_recordings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."engagement_recordings" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."engagement_transcript_segments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."engagement_transcript_segments" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."kitchen_routes" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."kitchen_routes" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."kitchen_stations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."kitchen_stations" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."order_line_preparations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."order_line_preparations" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."pass_credit_entries" TO "service_role";
