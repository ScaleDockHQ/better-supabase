SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.evaluate_segment (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."segments";
  v_fields jsonb;
  v_now timestamptz := now();
  v_ids text[];
  v_entered text[];
  v_left text[];
  v_id text;
begin
  select * into v_row from "better_supabase"."segments" x where x."id" = evaluate_segment.segment for update;
  if v_row."id" is null then
    return null;
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_row."subject_type");
  if v_row."subject_type" = 'message' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."messages" s
      where s."tenant_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'conversation' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."conversations" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'channel' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."channels" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'company' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."companies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'person' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."people" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'deal' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."deals" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'course' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."courses" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'post' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."posts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'engagement' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."engagements" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_item' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_items" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'employee' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."employees" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'ledger_account' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."ledger_accounts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."products" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product_variant' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."product_variants" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'calendar_event' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."calendar_events" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."assets" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset_location' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."asset_locations" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'lease' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."lease_agreements" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'maintenance_request' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."maintenance_requests" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_report' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_reports" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_line' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_lines" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'donation_fund' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."donation_funds" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'shipment' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."shipments" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'contract' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."contracts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'control' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."controls" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'policy' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."policies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'incident' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."incidents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'document' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."documents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'customer' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."customers" s
      where s."organization_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'drive_node' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."drive_nodes" s
      where s."tenant_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'application' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."applications" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'project' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."projects" s
      where s."organization_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'task' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."tasks" s
      where s."organization_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  else
    raise exception 'The segment''s subject type is not registered in config.records' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  if cardinality(v_ids) > 10000 then
    raise exception 'A segment holds at most 10000 records; narrow its conditions' using errcode = '54000', hint = 'SEGMENT_TOO_LARGE';
  end if;
  with gone as (
    delete from "better_supabase"."segment_members" y
    where y."segment_id" = v_row."id" and not (y."subject_id" = any (v_ids))
    returning y."subject_id" as id
  ), added as (
    insert into "better_supabase"."segment_members" ("segment_id", "tenant_id", "subject_id", "entered_at")
    select v_row."id", v_row."tenant_id", z, v_now from unnest(v_ids) z
    on conflict do nothing
    returning "subject_id" as id
  )
  select coalesce((select array_agg(g.id order by g.id) from gone g), '{}'),
    coalesce((select array_agg(a.id order by a.id) from added a), '{}')
  into v_left, v_entered;
  foreach v_id in array v_entered loop
    perform "better_supabase".emit_event('segment.entered', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.entered:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  foreach v_id in array v_left loop
    perform "better_supabase".emit_event('segment.left', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.left:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  update "better_supabase"."segments" x set "member_count" = cardinality(v_ids), "refreshed_at" = v_now
  where x."id" = v_row."id";
  return jsonb_build_object('entered', cardinality(v_entered), 'left', cardinality(v_left), 'memberCount', cardinality(v_ids));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move (
  subject_type text,
  subject_id   text,
  previous_id  text,
  next_id      text,
  to_group     text
)
  RETURNS text
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_tenant text;
  v_group text;
  v_other_tenant text;
  v_other_group text;
  v_previous text;
  v_next text;
  v_key text;
begin
  if not "better_supabase"."can_subject"(move.subject_type, move.subject_id, 'write') then
    raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
  end if;
  case move.subject_type
    when 'deal' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."deals" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."deals" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."deals" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."deals" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."deals", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    when 'work_item' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."work_items" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."work_items" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."work_items" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."work_items" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."work_items", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    when 'application' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."applications" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."applications" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."applications" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."applications" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."applications", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    when 'task' then
      select s."organization_id"::text, s."status"::text
        into v_tenant, v_group
        from "public"."tasks" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."organization_id"::text, s."status"::text
          into v_previous, v_other_tenant, v_other_group
          from "public"."tasks" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."organization_id"::text, s."status"::text
          into v_next, v_other_tenant, v_other_group
          from "public"."tasks" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "public"."tasks" s set "rank" = v_key, "status" = (jsonb_populate_record(null::"public"."tasks", jsonb_build_object('status', v_group)))."status"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    else
      raise exception 'this subject type has no rank column in config.records' using errcode = '22023', hint = 'RANK_SUBJECT_UNKNOWN';
  end case;
  if length(v_key) > 24 then
    perform "better_supabase"."enqueue_job"(queue => 'rank.rebalance', payload => jsonb_build_object('subjectType', move.subject_type, 'tenant', v_tenant, 'group', v_group), dedupe_key => 'rank:' || move.subject_type || ':' || coalesce(v_tenant, '') || ':' || coalesce(v_group, ''), dedupe_running => false);
  end if;
  return v_key;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rebalance_ranks (
  subject_type text,
  tenant       text,
  rank_group   text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer := 0;
begin
  case rebalance_ranks.subject_type
    when 'deal' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."deals" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."deals" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    when 'work_item' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."work_items" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."work_items" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    when 'application' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."applications" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."applications" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    when 'task' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."status" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."status") as total
        from "public"."tasks" s
        where s."organization_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."status"::text = rebalance_ranks.rank_group)
      )
      update "public"."tasks" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    else
      raise exception 'this subject type has no rank column in config.records' using errcode = '22023', hint = 'RANK_SUBJECT_UNKNOWN';
  end case;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_segment (
  tenant  uuid,
  segment jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_old "better_supabase"."segments";
  v_row "better_supabase"."segments";
  v_type text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(better_supabase.can('tenant', save_segment.tenant, 'segments.edit'), false) then
    raise exception 'You need segments.edit to save a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  if jsonb_typeof(segment) is distinct from 'object' then
    raise exception 'segment must be an object' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_id := nullif(segment ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."segments" x
    where x."id" = v_id and x."tenant_id" = save_segment.tenant for update;
    if v_old."id" is null then
      raise exception 'No segment in this organization has this id' using errcode = 'P0002', hint = 'SEGMENT_NOT_FOUND';
    end if;
    if segment ? 'subjectType' and segment ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A segment''s subject type can''t change' using errcode = '22023', hint = 'SEGMENT_INVALID';
    end if;
  end if;
  v_type := coalesce(v_old."subject_type", segment ->> 'subjectType');
  if v_type is null or v_type not in ('message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'engagement', 'work_item', 'employee', 'ledger_account', 'product', 'product_variant', 'calendar_event', 'asset', 'asset_location', 'lease', 'maintenance_request', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'policy', 'incident', 'document', 'customer', 'drive_node', 'application', 'project', 'task') then
    raise exception 'subjectType must be a type in config.records' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  v_name := coalesce(nullif(trim(segment ->> 'name'), ''), v_old."name");
  if v_name is null or length(v_name) > 200 then
    raise exception 'A segment needs a name of at most 200 characters' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_description := case when segment ? 'description' then nullif(trim(segment ->> 'description'), '') else v_old."description" end;
  v_conditions := coalesce(segment -> 'conditions', v_old."conditions");
  if jsonb_typeof(v_conditions) is distinct from 'object' then
    raise exception 'A segment needs conditions, a filter tree' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_type);
  if v_fields = '{}'::jsonb then
    raise exception 'No rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SEGMENT_FIELDS_MISSING';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if v_old."id" is null then
    insert into "better_supabase"."segments" ("tenant_id", "name", "description", "subject_type", "conditions", "created_by")
    values (save_segment.tenant, v_name, v_description, v_type, v_conditions, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."conditions" = v_conditions then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'conditions', v_old."conditions", 'memberCount', v_old."member_count", 'refreshedAt', v_old."refreshed_at", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."segments" x set
      "name" = v_name,
      "description" = v_description,
      "conditions" = v_conditions,
      "refreshed_at" = case when x."conditions" = v_conditions then x."refreshed_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('segment.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.saved',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'conditions', v_row."conditions", 'memberCount', v_row."member_count", 'refreshedAt', v_row."refreshed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'Another segment in this organization has this name' using errcode = '23505', hint = 'SEGMENT_NAME_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'message' then
      select s."tenant_id", s."body"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."messages" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    when 'channel' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."topic"::text, s."purpose"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."channels" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'company' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."domain"::text), ''), '/crm/contacts/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."companies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'person' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."title"::text), ''), '/crm/contacts/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."people" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'deal' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."note"::text), ''), '/crm/deals'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."deals" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'course' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."courses" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'post' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."posts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'engagement' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."engagements" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_item' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."body"::text), ''), '/work'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."work_items" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'employee' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."employees" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."slug"::text), ''), '/shop'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."products" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product_variant' then
      select s."tenant_id", s."sku"::text, nullif(concat_ws(E'\n', s."title"::text, s."barcode"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."product_variants" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'calendar_event' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."location"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."calendar_events" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'drive_node' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."drive_nodes" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.records' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now();
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$function$;
