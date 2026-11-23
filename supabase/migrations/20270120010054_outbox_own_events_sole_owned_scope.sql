SET local check_function_bodies = off;

DROP FUNCTION "api"."sole_owned_organizations"(uuid);

DROP FUNCTION "better_supabase"."sole_owned_organizations"(uuid);

CREATE OR REPLACE FUNCTION api.sole_owned_organizations (
  member       uuid DEFAULT NULL::uuid,
  organization uuid DEFAULT NULL::uuid
)
  RETURNS uuid[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."sole_owned_organizations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.outbox_register (
  consumer   text,
  types      text[]  DEFAULT NULL::text[],
  from_start boolean DEFAULT false
)
  RETURNS bigint
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."outbox_consumers" ("name", "cursor_xid", "cursor_position", "types")
  select consumer, start.xid, start.position, types
  from (select 1) one
  left join lateral (
    select e."xid" as xid, e."position" as position from "better_supabase"."outbox_events" e
    where not from_start
    order by e."xid" desc, e."position" desc
    limit 1
  ) latest on true
  left join lateral (
    select e."xid" as xid, e."position" as position from "better_supabase"."outbox_events" e
    where not from_start and e."xid" = pg_current_xact_id_if_assigned()
    order by e."position" desc
    limit 1
  ) mine on true
  cross join lateral (
    select v.xid, v.position from (values (least(coalesce(latest.xid, '0'), pg_snapshot_xmax(pg_current_snapshot())), coalesce(latest.position, 0)), (mine.xid, mine.position)) v (xid, position)
    where v.xid is not null
    order by v.xid desc, v.position desc
    limit 1
  ) start
  on conflict ("name") do update set "types" = excluded."types", "updated_at" = now()
  returning "cursor_position"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sole_owned_organizations (
  member       uuid DEFAULT NULL::uuid,
  organization uuid DEFAULT NULL::uuid
)
  RETURNS uuid[]
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_member uuid := coalesce(member, auth.uid());
  v_all boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_member = auth.uid();
  v_ids uuid[];
begin
  if v_member is null then
    raise exception 'Only the member or the service role can read this' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not v_all and (case when organization is null then not exists (select 1 from "public"."memberships" m
    where m."user_id" = v_member
      and coalesce(better_supabase.member_can(auth.uid(), m."organization_id", 'members.remove'), false)) else not coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false) end) then
    raise exception 'Not allowed to read this member''s organizations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  v_ids := coalesce((
    select array_agg(m."organization_id" order by m."organization_id")
    from "public"."memberships" m
    where m."user_id" = v_member and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = 'owner'
      and (organization is null or m."organization_id" = organization)
      and exists (select 1 from "public"."organizations" o where o."id" = m."organization_id")
      and not exists (
        select 1 from "public"."memberships" y
        where y."organization_id" = m."organization_id" and y."user_id" <> v_member and (select r."key" from "better_supabase"."roles" r where r."id" = y."role") = 'owner'
      )
  ), '{}');
  if not v_all and exists (
    select 1 from unnest(v_ids) t (id)
    where not coalesce(better_supabase.member_can(auth.uid(), t.id, 'members.remove'), false)
  ) then
    raise exception 'Not allowed to read this member''s organizations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return v_ids;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."sole_owned_organizations"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."sole_owned_organizations"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sole_owned_organizations"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sole_owned_organizations"(uuid, uuid) TO "authenticated", "service_role";
