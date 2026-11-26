-- better-supabase module: read-sets
-- @bsb-block read-sets@1 managed
-- @bsb-hash sha256:2f953d2c8c69b36298460d78760a311f39364e9b2d04750608a202a7652eb750
-- One `stable` function per `defineReadSet` in `readSets`, so `db.$many(readSet, params)` is a single GET, and `read_batch`, which runs several stable reads in one call.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Functions for the read sets in `readSets` (better-supabase.config.ts); `gen` and `upgrade` rewrite them.
-- They are security invoker: RLS decides what each caller reads, as for any other query.

-- Runs several stable reads in one call: `calls` is an array of { fn, args },
-- and each entry of the result is { data }, { error } or { skipped } in the same
-- order. It calls only a stable, non-set function returning jsonb in the schema the
-- Data API reaches, with named arguments it declares, as the caller; anything else
-- is skipped, so the client calls it on its own.
create or replace function "better_supabase"."read_batch"(calls jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_target constant text := 'api';
  v_call jsonb;
  v_fn text;
  v_args jsonb;
  v_proc record;
  v_found boolean;
  v_params text;
  v_columns text;
  v_value jsonb;
  v_state text;
  v_message text;
  v_detail text;
  v_hint text;
  v_out jsonb := '[]'::jsonb;
begin
  if jsonb_typeof($1) is distinct from 'array' then
    raise exception 'Pass read_batch an array of { fn, args }' using errcode = '22023', hint = 'READ_BATCH_INVALID';
  end if;
  if jsonb_array_length($1) > 50 then
    raise exception 'a batch runs at most 50 calls' using errcode = '54000', hint = 'READ_BATCH_TOO_LARGE';
  end if;
  for v_call in
    select e.value from jsonb_array_elements($1) with ordinality as e(value, n) order by e.n
  loop
    v_fn := case when jsonb_typeof(v_call) = 'object' then v_call ->> 'fn' end;
    v_args := case when jsonb_typeof(v_call) = 'object' then coalesce(v_call -> 'args', '{}'::jsonb) end;
    v_found := false;
    if v_fn is not null and v_fn <> 'read_batch' and jsonb_typeof(v_args) = 'object' then
      select p.proargnames, p.proargtypes, p.pronargs, p.pronargdefaults into v_proc
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = v_target
        and p.proname = v_fn
        and p.prokind = 'f'
        and p.provolatile in ('s', 'i')
        and not p.proretset
        and p.provariadic = 0
        and p.proargmodes is null
        and p.prorettype = 'pg_catalog.jsonb'::pg_catalog.regtype
        and (p.pronargs = 0 or p.proargnames is not null)
        and not exists (
          select 1 from jsonb_object_keys(v_args) k(arg)
          where k.arg = '' or not k.arg = any (coalesce(p.proargnames[1:p.pronargs], '{}'::text[]))
        )
        and not exists (
          select 1 from unnest(p.proargnames[1:p.pronargs - p.pronargdefaults]) r(arg)
          where not v_args ? r.arg
        )
      order by p.pronargs
      limit 1;
      v_found := found;
    end if;
    if not v_found then
      v_out := v_out || jsonb_build_array(jsonb_build_object('skipped', true));
      continue;
    end if;
    select
      string_agg(format('%I => a.%I', a.arg, a.arg), ', ' order by a.n),
      string_agg(format('%I %s', a.arg, pg_catalog.format_type(v_proc.proargtypes[(a.n - 1)::integer], null)), ', ' order by a.n)
    into v_params, v_columns
    from unnest(v_proc.proargnames[1:v_proc.pronargs]) with ordinality as a(arg, n)
    where v_args ? a.arg;
    begin
      if v_params is null then
        execute format('select to_jsonb(%I.%I())', v_target, v_fn) into v_value;
      else
        execute format('select to_jsonb(%I.%I(%s)) from jsonb_to_record($1) as a(%s)', v_target, v_fn, v_params, v_columns)
          into v_value using v_args;
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('data', v_value));
    exception when others then
      get stacked diagnostics
        v_state = returned_sqlstate,
        v_message = message_text,
        v_detail = pg_exception_detail,
        v_hint = pg_exception_hint;
      v_out := v_out || jsonb_build_array(jsonb_build_object('error', jsonb_strip_nulls(jsonb_build_object(
        'code', v_state,
        'message', v_message,
        'details', nullif(v_detail, ''),
        'hint', nullif(v_hint, '')
      ))));
    end;
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."read_batch"(jsonb) from public, anon;
grant execute on function "better_supabase"."read_batch"(jsonb) to authenticated, service_role;

-- config.readSets
-- finance_overview
create or replace function public.rs_finance_overview(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'reconciliation', to_jsonb("api"."bank_reconciliation_board"("account_id" => ((p->>'accountId')::uuid), "line_limit" => 100)),
    'stock', to_jsonb("api"."inventory_overview"("tenant" => ((p->>'organizationId')::uuid)))
  )
$rs$;
revoke execute on function public.rs_finance_overview(jsonb) from public, anon, authenticated;
grant execute on function public.rs_finance_overview(jsonb) to authenticated;

-- pipeline_overview
create or replace function public.rs_pipeline_overview(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'customers', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."customers" as t0 limit 1001) as c)),
    'board', to_jsonb("api"."deal_board"("pipeline" => ((p->>'pipelineId')::uuid)))
  )
$rs$;
revoke execute on function public.rs_pipeline_overview(jsonb) from public, anon, authenticated;
grant execute on function public.rs_pipeline_overview(jsonb) to authenticated;

-- workspace_summary
create or replace function public.rs_workspace_summary(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'customers', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."customers" as t0 limit 1001) as c)),
    'active', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."customers" as t0 where t0."status" = 'active' limit 1001) as c)),
    'mine', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."customers" as t0 where t0."created_by" = (select auth.uid()) limit 1001) as c)),
    'latestNote', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('body', t0."body", 'createdAt', t0."created_at") as row from "public"."notes" as t0 order by t0."created_at" desc limit 1) s), 'count', null)
  )
$rs$;
revoke execute on function public.rs_workspace_summary(jsonb) from public, anon, authenticated;
grant execute on function public.rs_workspace_summary(jsonb) to authenticated;

-- blocks.read-sets.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."read_batch"(calls jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."read_batch"($1) $$;
revoke execute on function "api"."read_batch"(jsonb) from public, anon;
grant execute on function "api"."read_batch"(jsonb) to authenticated, service_role;
