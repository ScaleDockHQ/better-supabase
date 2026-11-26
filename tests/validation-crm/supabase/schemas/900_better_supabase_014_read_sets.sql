-- better-supabase module: read-sets
-- @bsb-block read-sets@1 managed
-- @bsb-hash sha256:0219ccdf9acb46add91aacca9da0171655e37c1facb43b6128b64a056a7e2b8e
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
  v_target constant text := 'better_supabase';
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
-- app_chrome
create or replace function public.rs_app_chrome(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'unread', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."notification_recipients" as t0 where (t0."recipient_user_id" = ((p->>'userId')::uuid) and t0."read_at" is null and t0."dismissed_at" is null) limit 1001) as c)),
    'openTasks', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."tasks" as t0 where (t0."status" = any('{"todo","in_progress"}') and exists (select 1 from "public"."task_assignees" as t1 where t1."task_id" = t0."id" and t1."user_id" = ((p->>'userId')::uuid))) limit 1001) as c)),
    'approvals', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."approval_requests" as t0 where (t0."status" = 'requested' and t0."approver_user_id" = ((p->>'userId')::uuid)) limit 1001) as c))
  )
$rs$;
revoke execute on function public.rs_app_chrome(jsonb) from public, anon, authenticated;
grant execute on function public.rs_app_chrome(jsonb) to authenticated;

-- customer_detail
create or replace function public.rs_customer_detail(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'customer', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('id', t0."id", 'companyName', t0."company_name", 'isBusiness', t0."is_business", 'status', t0."status", 'billingEmail', t0."billing_email", 'website', t0."website") as row from "public"."customers" as t0 where (t0."id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid)) limit 2) s), 'count', null),
    'contacts', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('id', t0."id", 'jobTitle', t0."job_title", 'isPrimary', t0."is_primary", 'contactProfile', (select json_build_object('id', t1."id", 'firstName', t1."first_name", 'lastName', t1."last_name", 'displayName', t1."display_name", 'contactMethods', (select coalesce(json_agg(s.r order by s.o), '[]'::json) from (select json_build_object('id', t2."id", 'type', t2."type", 'value', t2."value", 'isPrimary', t2."is_primary") as r, row_number() over () as o from "public"."contact_methods" as t2 where t2."contact_profile_id" = t1."id") as s)) from "public"."contact_profiles" as t1 where t1."id" = t0."contact_profile_id" limit 1)) as row from "public"."customer_contacts" as t0 where (t0."customer_id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid)) order by t0."is_primary" desc, t0."created_at" asc) s), 'count', null),
    'locations', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('id', t0."id", 'name', t0."name", 'addressLine1', t0."address_line1", 'addressCity', t0."address_city", 'isPrimary', t0."is_primary") as row from "public"."customer_locations" as t0 where (t0."customer_id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid)) order by t0."is_primary" desc, t0."created_at" asc) s), 'count', null),
    'quotes', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."quotes" as t0 where (t0."customer_id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid)) limit 1001) as c)),
    'invoices', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."invoices" as t0 where (t0."customer_id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid)) limit 1001) as c))
  )
$rs$;
revoke execute on function public.rs_customer_detail(jsonb) from public, anon, authenticated;
grant execute on function public.rs_customer_detail(jsonb) to authenticated;
