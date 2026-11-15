SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_announcement"(uuid);

DROP FUNCTION "api"."list_announcements"();

DROP FUNCTION "better_supabase"."delete_announcement"(uuid);

DROP FUNCTION "better_supabase"."list_announcements"();

ALTER TABLE "better_supabase"."announcements"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_announcement (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_announcement"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_announcements (
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_announcements"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_announcement (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_announcement"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_announcement (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_announcement"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.active_announcements (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and x."archived_at" is null
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        when 'plan' then v_tenant is not null and x."targets" && better_supabase.tenant_entitlements(v_tenant)
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_announcement (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = archive_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', archive_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('announcement.archived', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.archived',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_announcements (
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where list_announcements.include_archived or x."archived_at" is null
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_announcement (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = purge_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform "better_supabase".emit_event('announcement.purged', jsonb_build_object('announcementId', purge_announcement.id), 'announcements/' || purge_announcement.id::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.purged',
    category => 'configuration',
    target_type => 'announcement',
    record_id => purge_announcement.id::text,
    metadata => jsonb_build_object('announcementId', purge_announcement.id)
  );
  end if;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_announcement (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."announcements" x where x."id" = restore_announcement.id for update;
  if v_row."id" is null then
    raise exception 'No announcement %', restore_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is null then
    return to_jsonb(v_row);
  end if;
  update "better_supabase"."announcements" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('announcement.restored', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.restored',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_announcement (
  id     uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'archived_at' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if save_announcement.id is null then
    perform "better_supabase".emit_event('announcement.created', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.created',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  else
    perform "better_supabase".emit_event('announcement.updated', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.updated',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  end if;
  return to_jsonb(v_row);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_announcements"(boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_announcements"(boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_announcements"(boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_announcements"(boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_announcement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_announcement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_announcement"(uuid) TO "authenticated", "service_role";
