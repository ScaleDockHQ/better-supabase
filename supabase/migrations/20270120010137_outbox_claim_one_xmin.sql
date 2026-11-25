SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.outbox_claim (
  consumer   text,
  owner      text,
  max_events integer  DEFAULT 100,
  lease      interval DEFAULT '00:01:00'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  c "better_supabase"."outbox_consumers";
  events jsonb;
  v_xmin xid8 := pg_snapshot_xmin(pg_current_snapshot());
begin
  update "better_supabase"."outbox_consumers" k
  set "lease_owner" = owner, "lease_expires_at" = now() + lease, "updated_at" = now()
  where k."name" = consumer
    and (k."lease_expires_at" is null or k."lease_expires_at" < now() or k."lease_owner" = owner)
    and (k."retry_at" is null or k."retry_at" <= now())
  returning k.* into c;
  if not found then
    if not exists (select 1 from "better_supabase"."outbox_consumers" k where k."name" = consumer) then
      raise exception 'Unknown outbox consumer %', consumer using errcode = 'P0002', hint = 'OUTBOX_UNKNOWN_CONSUMER';
    end if;
    return '[]';
  end if;
  select jsonb_agg(x.event order by x.n) into events
  from (
    select jsonb_build_object(
    'position', e."position",
    'id', e."id",
    'type', e."type",
    'payload', e."payload",
    'created_at', e."created_at",
    'source', e."source",
    'subject', e."subject",
    'tenant', e."tenant_id",
    'key', e."key",
    'actor_id', e."actor_id"
  ) as event, row_number() over (order by e."xid", e."position") as n
    from "better_supabase"."outbox_events" e
    where (e."xid", e."position") > (c."cursor_xid", c."cursor_position")
      and e."xid" < v_xmin
      and (c."types" is null or exists (
        select 1 from unnest(c."types") p
        where p = '*' or p = e."type"
          or (right(p, 2) = '.*' and starts_with(e."type", left(p, -1)))
      ))
    order by e."xid", e."position"
    limit case when c."attempts" > 0 then 1 else max_events end
  ) x;
  if events is null then
    update "better_supabase"."outbox_consumers" k
    set ("cursor_xid", "cursor_position") = (
      select e."xid", e."position" from "better_supabase"."outbox_events" e
      where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < v_xmin
      order by e."xid" desc, e."position" desc
      limit 1
    )
    where k."name" = consumer
      and exists (select 1 from "better_supabase"."outbox_events" e where (e."xid", e."position") > (c."cursor_xid", c."cursor_position") and e."xid" < v_xmin);
  end if;
  return coalesce(events, '[]');
end;
$function$;
