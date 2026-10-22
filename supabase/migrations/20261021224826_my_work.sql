SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.my_reminders_due (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS TABLE (
    reminder     uuid,
    subject_type text,
    subject_id   text,
    at           timestamp with time zone
  )
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."my_reminders_due"($1) $function$;

CREATE OR REPLACE FUNCTION api.my_work (
  tenant    uuid    DEFAULT NULL::uuid,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_work"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.my_reminders_due (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS TABLE (
    reminder     uuid,
    subject_type text,
    subject_id   text,
    at           timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select r."id", r."subject_type"::text,
    r."subject_id"::text, max(d."occurrence_at")
  from "better_supabase"."reminders" r
  join "better_supabase"."reminder_deliveries" d on d."reminder_id" = r."id"
  where r."user_id" = (select auth.uid())
    and (my_reminders_due.tenant is null or r."tenant_id" = my_reminders_due.tenant)
    and d."sent_at" > now() - interval '7 days'
  group by 1, 2, 3
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_work (
  tenant    uuid    DEFAULT NULL::uuid,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind', w.kind,
      'subject', jsonb_build_object('type', w.subject_type, 'id', w.subject_id),
      'ref', w.ref,
      'title', coalesce(w.title, "better_supabase"."subject_title"(w.subject_type, w.subject_id)),
      'url', "better_supabase"."subject_url"(w.subject_type, w.subject_id),
      'at', w.at
    ) order by w.at desc nulls last, w.kind, w.ref), '[]'::jsonb)
    from (
      select * from (
    select 'assigned'::text, 'work_item'::text, i."id"::text, i."id"::text, i."title"::text,
      coalesce(i."due_at", a."created_at")
    from "better_supabase"."work_item_assignees" a
    join "better_supabase"."work_items" i on i."id" = a."work_item_id"
    where a."user_id" = v_me
      and i."state" not in ('completed', 'canceled')
      and i."archived_at" is null
      and (my_work.tenant is null or i."tenant_id" = my_work.tenant)
    union all
    select 'approval'::text, r."subject_type"::text, r."subject_id"::text, r."id"::text, null::text,
      r."created_at"
    from "better_supabase"."approval_requests" r
    where r."status" = 'pending'
      and (r."expires_at" is null or r."expires_at" > now())
      and (my_work.tenant is null or r."tenant_id" = my_work.tenant)
      and "better_supabase"."approval_eligible"(r."id")
    union all
    select 'reminder'::text, d.subject_type, d.subject_id, d.reminder::text, null::text, d.at
    from "better_supabase"."my_reminders_due"(my_work.tenant) d
    where "better_supabase"."can_subject"(d.subject_type, d.subject_id, 'read')
    union all
    select 'mention'::text, c."subject_type"::text, c."subject_id"::text, c."id"::text, null::text,
      c."created_at"
    from "better_supabase"."comments" c
    where v_me = any (c."mentions")
      and c."deleted_at" is null
      and c."created_at" > now() - interval '30 days'
      and (my_work.tenant is null or c."organization_id" = my_work.tenant)
    union all
    select 'sla'::text, k."subject_type"::text, k."subject_id"::text, k."id"::text, null::text,
      k."due_at"
    from "better_supabase"."sla_clocks" k
    where k."subject_type" = 'work_item'
      and k."warned_at" is not null
      and k."met_at" is null
      and (my_work.tenant is null or k."tenant_id" = my_work.tenant)
      and exists (
        select 1 from "better_supabase"."work_item_assignees" a
        where a."work_item_id"::text = k."subject_id"::text
          and a."user_id" = v_me)
      ) u (kind, subject_type, subject_id, ref, title, at)
      order by u.at desc nulls last, u.kind, u.ref
      limit least(greatest(coalesce(my_work.page_size, 50), 1), 200)
    ) w
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."my_reminders_due"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."my_reminders_due"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."my_work"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."my_work"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."my_reminders_due"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."my_reminders_due"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."my_work"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."my_work"(uuid, integer) TO "authenticated", "service_role";
