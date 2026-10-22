-- better-supabase module: rank
-- @bsb-block rank@1 managed
-- Fractional rank keys: rank_between, move() for every config.records entry with a rank column (through the caller's policies and any state-machine trigger), and a rebalance job.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Fractional rank keys (ADR 0021). Keys are base-62 text compared with
-- collate "C"; the steps match rankBetween in better-supabase/blocks/rank.
create or replace function "better_supabase"."rank_between"(previous text, next text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_alphabet constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  v_low text := coalesce(rank_between.previous, '');
  v_key text := '';
  v_bounded boolean := rank_between.next is not null;
  v_index integer := 1;
  v_low_digit integer;
  v_high_digit integer;
begin
  if rank_between.previous is not null and rank_between.previous !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'RANK_KEY_INVALID';
  end if;
  if rank_between.next is not null and rank_between.next !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'RANK_KEY_INVALID';
  end if;
  if rank_between.previous is not null and rank_between.next is not null
    and rank_between.previous collate "C" >= rank_between.next collate "C" then
    raise exception 'previous must sort before next' using errcode = '22023', hint = 'RANK_KEY_ORDER';
  end if;
  loop
    v_low_digit := case when v_index <= length(v_low) then strpos(v_alphabet, substr(v_low, v_index, 1)) - 1 else 0 end;
    v_high_digit := case
      when not v_bounded then 62
      when v_index <= length(rank_between.next) then strpos(v_alphabet, substr(rank_between.next, v_index, 1)) - 1
      else 0
    end;
    if v_high_digit = v_low_digit then
      v_key := v_key || substr(v_alphabet, v_low_digit + 1, 1);
    elsif v_high_digit - v_low_digit > 1 then
      return v_key || substr(v_alphabet, (v_low_digit + v_high_digit) / 2 + 1, 1);
    elsif v_bounded and v_index < length(rank_between.next) then
      return v_key || substr(rank_between.next, v_index, 1);
    else
      v_key := v_key || substr(v_alphabet, v_low_digit + 1, 1);
      v_bounded := false;
    end if;
    v_index := v_index + 1;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."rank_between"(text, text) from public, anon;
grant execute on function "better_supabase"."rank_between"(text, text) to authenticated, service_role;

-- Key number nth of total, spread evenly at one width (rankKeys).
create or replace function "better_supabase"."rank_key"(nth bigint, total bigint)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_alphabet constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  v_width integer := 1;
  v_value numeric;
  v_key text := '';
begin
  if rank_key.nth < 1 or rank_key.nth > rank_key.total then
    raise exception 'nth must be between 1 and total' using errcode = '22023', hint = 'RANK_KEY_POSITION';
  end if;
  while 62::numeric ^ v_width <= rank_key.total loop
    v_width := v_width + 1;
  end loop;
  v_value := floor(62::numeric ^ v_width / (rank_key.total + 1)) * rank_key.nth;
  for v_place in 1..v_width loop
    v_key := substr(v_alphabet, (v_value % 62)::integer + 1, 1) || v_key;
    v_value := floor(v_value / 62);
  end loop;
  return rtrim(v_key, '0');
end;
$$;
revoke execute on function "better_supabase"."rank_key"(bigint, bigint) from public, anon;
grant execute on function "better_supabase"."rank_key"(bigint, bigint) to authenticated, service_role;

-- Moves a subject between two neighbours (either may be null for an end),
-- into to_group when given. It runs as the caller: the table's policies
-- decide what it can read and update, and a state-machine trigger on the
-- group column checks the stage change. Returns the new key.
create or replace function "better_supabase"."move"(subject_type text, subject_id text, previous_id text, next_id text, to_group text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."move"(text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."move"(text, text, text, text, text) to authenticated, service_role;

-- Rewrites every key of a tenant's rows (in rank_group, or every group) to
-- short, evenly spaced keys in the same order. Returns the rows rewritten.
create or replace function "better_supabase"."rebalance_ranks"(subject_type text, tenant text, rank_group text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."rebalance_ranks"(text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."rebalance_ranks"(text, text, text) to service_role;

-- blocks.rank.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."rank_between"(previous text, next text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_between"($1, $2) $$;
revoke execute on function "api"."rank_between"(text, text) from public, anon;
grant execute on function "api"."rank_between"(text, text) to authenticated, service_role;

create or replace function "api"."rank_key"(nth bigint, total bigint)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_key"($1, $2) $$;
revoke execute on function "api"."rank_key"(bigint, bigint) from public, anon;
grant execute on function "api"."rank_key"(bigint, bigint) to authenticated, service_role;

create or replace function "api"."move"(subject_type text, subject_id text, previous_id text, next_id text, to_group text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."move"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."move"(text, text, text, text, text) from public, anon;
grant execute on function "api"."move"(text, text, text, text, text) to authenticated, service_role;

create or replace function "api"."rebalance_ranks"(subject_type text, tenant text, rank_group text)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rebalance_ranks"($1, $2, $3) $$;
revoke execute on function "api"."rebalance_ranks"(text, text, text) from public, anon, authenticated;
grant execute on function "api"."rebalance_ranks"(text, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
