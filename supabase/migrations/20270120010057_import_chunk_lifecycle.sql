SET local check_function_bodies = off;

DROP VIEW "better_supabase"."maintenance_jobs";

DROP FUNCTION "api"."fail_import_chunk"(uuid, text, integer, text);

DROP FUNCTION "better_supabase"."fail_import_chunk"(uuid, text, integer, text);

ALTER TABLE "better_supabase"."import_chunks"
  ALTER COLUMN "items" DROP NOT NULL;

CREATE OR REPLACE FUNCTION api.fail_import_chunk (
  run     uuid,
  entity  text,
  chunk   integer,
  message text,
  final   boolean DEFAULT false
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."fail_import_chunk"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.import_chunk_maintenance()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_chunk_maintenance"() $function$;

CREATE OR REPLACE FUNCTION api.list_import_conflicts (
  run       uuid,
  entity    text    DEFAULT NULL::text,
  after     text    DEFAULT NULL::text,
  row_limit integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_import_conflicts"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_import_chunk (
  run    uuid,
  entity text,
  chunk  integer,
  lease  integer DEFAULT 300
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_items jsonb;
begin
  with pick as (
    select x."run_id", x."entity", x."chunk"
    from "better_supabase"."import_chunks" x
    where x."run_id" = claim_import_chunk.run and x."entity" = claim_import_chunk.entity and x."chunk" = claim_import_chunk.chunk
      and x."items" is not null
      and (x."status" = 'pending' or (x."status" = 'claimed' and x."claimed_at" < now() - make_interval(secs => greatest(claim_import_chunk.lease, 1))))
    for update skip locked
  )
  update "better_supabase"."import_chunks" x set "status" = 'claimed', "claimed_at" = now()
  from pick
  where x."run_id" = pick."run_id" and x."entity" = pick."entity" and x."chunk" = pick."chunk"
  returning x."items" into v_items;
  if v_items is null then
    return null;
  end if;
  return jsonb_build_object('entity', claim_import_chunk.entity, 'chunk', claim_import_chunk.chunk, 'items', v_items);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_import_chunk (
  run    uuid,
  entity text,
  chunk  integer,
  result jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  update "better_supabase"."import_chunks" x set "status" = 'done', "done_at" = now(), "result" = complete_import_chunk.result, "items" = null
  where x."run_id" = complete_import_chunk.run and x."entity" = complete_import_chunk.entity
    and x."chunk" = complete_import_chunk.chunk and x."status" = 'claimed';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enqueue_import_chunks (
  run    uuid,
  entity text,
  chunks integer
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
  v_chunk integer;
  v_failed integer[];
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = enqueue_import_chunks.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    raise exception 'chunks must be at least 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select coalesce(array_agg(x."chunk"), '{}') into v_failed from "better_supabase"."import_chunks" x
  where x."run_id" = enqueue_import_chunks.run and x."entity" = enqueue_import_chunks.entity
    and x."status" = 'failed';
  -- A failed chunk that still has its items goes back to pending, with a new
  -- job, so a retry reaches it.
  update "better_supabase"."import_chunks" x set "status" = 'pending', "claimed_at" = null,
    "done_at" = null, "result" = null
  where x."run_id" = enqueue_import_chunks.run and x."entity" = enqueue_import_chunks.entity
    and x."status" = 'failed' and x."items" is not null;
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    if v_chunk = any (v_failed) then
      perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text || ':retry:' || extract(epoch from clock_timestamp())::text, dedupe_running => false);
    else
      perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
    end if;
  end loop;
  return enqueue_import_chunks.chunks;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fail_import_chunk (
  run     uuid,
  entity  text,
  chunk   integer,
  message text,
  final   boolean DEFAULT false
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_message text := left(coalesce(fail_import_chunk.message, ''), 500);
begin
  update "better_supabase"."import_chunks" x set "status" = 'failed', "done_at" = now(),
    "result" = jsonb_build_object('failed', true, 'message', v_message)
  where x."run_id" = fail_import_chunk.run and x."entity" = fail_import_chunk.entity
    and x."chunk" = fail_import_chunk.chunk and x."status" in ('pending', 'claimed', 'failed');
  if not found then
    return false;
  end if;
  if coalesce(fail_import_chunk.final, false) then
    update "better_supabase"."import_runs" r set "status" = 'failed', "outcome" = 'failed', "finished_at" = now(),
      "errors" = r."errors" || jsonb_build_array(jsonb_build_object(
        'entity', fail_import_chunk.entity, 'key', null, 'code', 'IMPORT_CHUNK_FAILED',
        'message', 'chunk ' || fail_import_chunk.chunk::text || ': ' || v_message))
    where r."id" = fail_import_chunk.run and r."status" in ('pending', 'running');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_import_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = 'PT409', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if exists (select 1 from "better_supabase"."import_chunks" c where c."run_id" = v_run_id and c."status" <> 'done') then
    raise exception 'the import has chunks that are not done' using errcode = 'PT409', hint = 'IMPORT_CHUNKS_OPEN';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (
    jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0
    or exists (
      select 1 from jsonb_each(coalesce(v_counts, '{}'::jsonb)) v_entity_counts(key, value)
      where coalesce((v_entity_counts.value ->> 'conflicted')::integer, 0) > 0
    )
  ) then
    v_outcome := 'completed_with_issues';
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      perform "better_supabase".emit_event('import.entity_completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
      if coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0) > 0 then
        perform better_supabase.audit_event(
    event_type => 'import.entity_completed',
    category => 'integration',
    target_type => 'import',
    record_id => v_run_id::text,
    target_label => v_entity,
    summary => 'imported ' || v_entity,
    tenant => (v_run."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity),
    idempotency_key => 'import:' || v_run_id::text || ':' || v_entity,
    actor_kind => 'integration',
    correlation_id => 'import:' || v_run_id::text
  );
      end if;
    end loop;
    perform "better_supabase".emit_event('import.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'count', v_total), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
  end if;
  perform "better_supabase"."search_refresh_run"(v_run_id);
  return v_counts;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_import_run (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = get_import_run.id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to read this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'outcome', v_run."outcome", 'plan', v_run."plan", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'mapperVersion', v_run."mapper_version", 'scopeAliases', v_run."scope_aliases", 'leaseUntil', v_run."lease_expires_at", 'heartbeatAt', v_run."heartbeat_at", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = v_run."id"
  ), 'chunks', (
    select jsonb_build_object(
      'pending', count(*) filter (where k."status" = 'pending'),
      'claimed', count(*) filter (where k."status" = 'claimed'),
      'done', count(*) filter (where k."status" = 'done'),
      'failed', count(*) filter (where k."status" = 'failed'),
      'bytes', coalesce(sum(pg_column_size(k."items")), 0)
    )
    from "better_supabase"."import_chunks" k
    where k."run_id" = v_run."id"
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_chunk_maintenance()
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_canceled integer := 0;
  v_cleared integer;
begin
  update "better_supabase"."import_chunks" x set "items" = null
  where x."items" is not null
    and (x."run_id" in (
        select r."id" from "better_supabase"."import_runs" r
        where r."status" in ('completed', 'canceled')
          or (r."status" = 'failed' and r."finished_at" < now() - interval '7 days'))
      or (x."status" = 'failed' and x."done_at" < now() - interval '7 days'));
  get diagnostics v_cleared = row_count;
  return jsonb_build_object('cleared', v_cleared, 'canceled', v_canceled);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_stock_count (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_stock_count.item ->> 'tenant')::uuid;
  v_data jsonb := import_stock_count.item -> 'data';
  v_location uuid;
  v_id uuid;
  v_status text;
  v_updated timestamptz;
  v_entry jsonb;
  v_variant uuid;
  v_bin uuid;
  v_lot uuid;
  v_serial text;
  v_counted numeric;
  v_expected numeric;
begin
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' then
    raise exception 'a stock count needs a list of lines' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_location := nullif(v_data ->> 'locationId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'locationId is a uuid' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_location is null and nullif(v_data ->> 'location', '') is null then
    -- Without a location the count goes to the organization's only active one.
    select min(x."id"::text)::uuid into v_location from "better_supabase"."inventory_locations" x
    where x."tenant_id" = v_tenant and x."active"
    having count(*) = 1;
  elsif v_location is null then
    select x."id" into v_location from "better_supabase"."inventory_locations" x where x."tenant_id" = v_tenant and x."code" = v_data ->> 'location';
  elsif not exists (select 1 from "better_supabase"."inventory_locations" x where x."id" = v_location and x."tenant_id" = v_tenant) then
    v_location := null;
  end if;
  if v_location is null then
    raise exception 'the count''s location isn''t in this organization, or the count names none and the organization has more than one active location' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if import_stock_count.subject_id is null then
    insert into "better_supabase"."stock_counts" as x ("tenant_id", "location_id", "note")
    values (v_tenant, v_location, nullif(btrim(v_data ->> 'note'), ''))
    returning x."id", x."updated_at" into v_id, v_updated;
  else
    select x."id", x."status" into v_id, v_status from "better_supabase"."stock_counts" x
    where x."id" = import_stock_count.subject_id::uuid and x."tenant_id" = v_tenant for update;
    if v_id is null then
      raise exception 'the stock count no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    if v_status <> 'open' then
      raise exception 'a posted or cancelled count can''t be imported again' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    update "better_supabase"."stock_counts" x set "location_id" = v_location, "note" = nullif(btrim(v_data ->> 'note'), ''), "updated_at" = now()
    where x."id" = v_id returning x."updated_at" into v_updated;
    delete from "better_supabase"."stock_count_lines" y where y."count_id" = v_id and y."movement_id" is null;
  end if;
  for v_entry in select e from jsonb_array_elements(v_data -> 'lines') e loop
    begin
      v_variant := nullif(v_entry ->> 'variantId', '')::uuid;
      v_bin := nullif(v_entry ->> 'binId', '')::uuid;
      v_lot := nullif(v_entry ->> 'lotId', '')::uuid;
      v_counted := (v_entry ->> 'counted')::numeric;
      v_expected := (v_entry ->> 'expected')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'ids are uuids and counted and expected are numbers' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end;
    if v_variant is null then
      select y."id" into v_variant from "better_supabase"."product_variants" y where y."tenant_id" = v_tenant and y."sku" = v_entry ->> 'sku';
    end if;
    if v_variant is null or not exists (select 1 from "better_supabase"."product_variants" y where y."id" = v_variant and y."tenant_id" = v_tenant) then
      raise exception 'a line''s variant isn''t in this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    if v_bin is null and nullif(v_entry ->> 'bin', '') is not null then
      select y."id" into v_bin from "better_supabase"."stock_bins" y where y."tenant_id" = v_tenant and y."location_id" = v_location and y."code" = v_entry ->> 'bin';
      if v_bin is null then
        raise exception 'a line''s bin isn''t at the location' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
      end if;
    end if;
    if v_lot is null and nullif(v_entry ->> 'lot', '') is not null then
      select y."id" into v_lot from "better_supabase"."stock_lots" y where y."tenant_id" = v_tenant and y."variant_id" = v_variant and y."code" = v_entry ->> 'lot';
      if v_lot is null then
        raise exception 'a line''s lot isn''t a lot of its variant' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
      end if;
    end if;
    v_serial := nullif(btrim(v_entry ->> 'serial'), '');
    if v_counted is null or v_counted < 0 or (v_serial is not null and (v_counted not in (0, 1) or v_bin is not null or v_lot is not null)) then
      raise exception 'a line needs a counted quantity of zero or more, and a serial is counted 0 or 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    insert into "better_supabase"."stock_count_lines" as x ("tenant_id", "count_id", "variant_id", "bin_id", "lot_id", "serial", "expected", "counted")
    values (v_tenant, v_id, v_variant, v_bin, v_lot, v_serial,
      coalesce(v_expected, "better_supabase"."count_expected"(v_variant, v_location, v_bin, v_lot, v_serial)), v_counted)
    on conflict ("count_id", "variant_id", coalesce("bin_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("lot_id", '00000000-0000-4000-8000-000000000000'::uuid), coalesce("serial", '')) do update
      set "counted" = excluded."counted", "expected" = excluded."expected", "updated_at" = now();
  end loop;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_conflicts (
  run       uuid,
  entity    text    DEFAULT NULL::text,
  after     text    DEFAULT NULL::text,
  row_limit integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_limit integer := least(greatest(coalesce(list_import_conflicts.row_limit, 100), 1), 1000);
  v_after_at timestamptz;
  v_after_id uuid;
  v_rows jsonb;
  v_found integer;
  v_next text;
begin
  select r."tenant_id" into v_tenant from "better_supabase"."import_runs" r where r."id" = list_import_conflicts.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import conflicts' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if list_import_conflicts.after is not null then
    begin
      v_after_at := split_part(convert_from(decode(translate(list_import_conflicts.after, '-_.', '+/='), 'base64'), 'utf8'), '|', 1)::timestamptz;
      v_after_id := split_part(convert_from(decode(translate(list_import_conflicts.after, '-_.', '+/='), 'base64'), 'utf8'), '|', 2)::uuid;
    exception when others then
      raise exception 'after is not a cursor of this list' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('entity', t."entity", 'key', t."key", 'code', t."code", 'message', t."message", 'createdAt', t."created_at", 'resolvedAt', t."resolved_at") order by t."created_at", t."id") filter (where t."n" <= v_limit), '[]'::jsonb),
    count(*),
    max(translate(encode(convert_to(t."created_at"::text || '|' || t."id"::text, 'utf8'), 'base64'), '+/=', '-_.')) filter (where t."n" = v_limit)
  into v_rows, v_found, v_next
  from (
    select p.*, row_number() over (order by p."created_at", p."id") as "n"
    from (
      select i."id", i."entity", i."key", i."code", i."message", i."created_at", i."resolved_at"
      from "better_supabase".import_run_issues i
      where i."run_id" = list_import_conflicts.run and i."kind" = 'conflict'
        and (list_import_conflicts.entity is null or i."entity" = list_import_conflicts.entity)
        and (v_after_at is null or (i."created_at", i."id") > (v_after_at, v_after_id))
      order by i."created_at", i."id"
      limit v_limit + 1
    ) p
  ) t;
  return jsonb_build_object('rows', v_rows, 'next_cursor', case when v_found > v_limit then v_next else null end);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_runs (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_import_runs.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_import_runs.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list imports' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'IMPORT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('source', 'status') then
      raise exception 'facet is one of source, status' using errcode = '22023', hint = 'IMPORT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'source' then (r."source")::text when 'status' then (r."status")::text end) as v
      from "better_supabase"."import_runs" r
      where r."tenant_id" = list_import_runs.tenant
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (r."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or r."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."import_runs" r
      where r."tenant_id" = list_import_runs.tenant
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (r."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or r."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt') then
    raise exception 'sort is one of createdAt' using errcode = '22023', hint = 'IMPORT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'IMPORT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_expires_at", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ), 'chunks', (
    select jsonb_build_object(
      'pending', count(*) filter (where k."status" = 'pending'),
      'claimed', count(*) filter (where k."status" = 'claimed'),
      'done', count(*) filter (where k."status" = 'done'),
      'failed', count(*) filter (where k."status" = 'failed'),
      'bytes', coalesce(sum(pg_column_size(k."items")), 0)
    )
    from "better_supabase"."import_chunks" k
    where k."run_id" = r."id"
  )) as j, jsonb_build_array((r."created_at")::text, (r."id")::text) as k
    from (
      select * from "better_supabase"."import_runs" r
      where r."tenant_id" = list_import_runs.tenant
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (r."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or r."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (r."created_at" >= (v_after ->> 0)::timestamptz and ((r."created_at" > (v_after ->> 0)::timestamptz) or (r."created_at" = (v_after ->> 0)::timestamptz and r."id" < (v_after ->> 1)::uuid))))
      order by r."created_at" asc, r."id" desc
      limit v_limit + 1 offset v_offset
    ) r
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_expires_at", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ), 'chunks', (
    select jsonb_build_object(
      'pending', count(*) filter (where k."status" = 'pending'),
      'claimed', count(*) filter (where k."status" = 'claimed'),
      'done', count(*) filter (where k."status" = 'done'),
      'failed', count(*) filter (where k."status" = 'failed'),
      'bytes', coalesce(sum(pg_column_size(k."items")), 0)
    )
    from "better_supabase"."import_chunks" k
    where k."run_id" = r."id"
  )) as j, jsonb_build_array((r."created_at")::text, (r."id")::text) as k
    from (
      select * from "better_supabase"."import_runs" r
      where r."tenant_id" = list_import_runs.tenant
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (r."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or r."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (r."created_at", r."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by r."created_at" desc, r."id" desc
      limit v_limit + 1 offset v_offset
    ) r
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_expires_at", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ), 'chunks', (
    select jsonb_build_object(
      'pending', count(*) filter (where k."status" = 'pending'),
      'claimed', count(*) filter (where k."status" = 'claimed'),
      'done', count(*) filter (where k."status" = 'done'),
      'failed', count(*) filter (where k."status" = 'failed'),
      'bytes', coalesce(sum(pg_column_size(k."items")), 0)
    )
    from "better_supabase"."import_chunks" k
    where k."run_id" = r."id"
  )) as j, jsonb_build_array((r."created_at")::text, (r."id")::text) as k
    from (
      select * from "better_supabase"."import_runs" r
      where r."tenant_id" = list_import_runs.tenant
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (r."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or r."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (r."created_at" >= (v_after ->> 0)::timestamptz and ((r."created_at" > (v_after ->> 0)::timestamptz) or (r."created_at" = (v_after ->> 0)::timestamptz and r."id" < (v_after ->> 1)::uuid))))
      order by r."created_at" asc, r."id" desc
      limit v_limit + 1 offset v_offset
    ) r
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'outcome', r."outcome", 'plan', r."plan", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'leaseUntil', r."lease_expires_at", 'heartbeatAt', r."heartbeat_at", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at", 'issues', (
    select jsonb_build_object(
      'conflict', count(*) filter (where i."kind" = 'conflict' and i."resolved_at" is null),
      'error', count(*) filter (where i."kind" = 'error' and i."resolved_at" is null),
      'warning', count(*) filter (where i."kind" = 'warning' and i."resolved_at" is null)
    )
    from "better_supabase".import_run_issues i
    where i."run_id" = r."id"
  ), 'chunks', (
    select jsonb_build_object(
      'pending', count(*) filter (where k."status" = 'pending'),
      'claimed', count(*) filter (where k."status" = 'claimed'),
      'done', count(*) filter (where k."status" = 'done'),
      'failed', count(*) filter (where k."status" = 'failed'),
      'bytes', coalesce(sum(pg_column_size(k."items")), 0)
    )
    from "better_supabase"."import_chunks" k
    where k."run_id" = r."id"
  )) as j, jsonb_build_array((r."created_at")::text, (r."id")::text) as k
    from (
      select * from "better_supabase"."import_runs" r
      where r."tenant_id" = list_import_runs.tenant
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (r."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or r."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (r."created_at", r."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by r."created_at" desc, r."id" desc
      limit v_limit + 1 offset v_offset
    ) r
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."import_runs" r
      where r."tenant_id" = list_import_runs.tenant
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or (r."source")::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or r."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE VIEW "better_supabase"."maintenance_jobs" WITH (security_invoker=true) AS  SELECT j.job,
    j.fn AS function,
    j.every_interval AS every,
    s.last_run_at,
    s.last_status,
    s.last_error,
    COALESCE(s.runs, (0)::bigint) AS runs,
    ((s.last_run_at IS NULL) OR ((s.last_run_at + j.every_interval) <= now())) AS due
   FROM (( VALUES ('digest_run'::text,'"better_supabase"."run_notification_digests"'::text,'01:00:00'::interval), ('expire_approvals'::text,'"better_supabase"."expire_approvals"'::text,'00:15:00'::interval), ('expire_support_sessions'::text,'"better_supabase"."expire_support_sessions"'::text,'00:05:00'::interval), ('expire_work_item_claims'::text,'"better_supabase"."expire_work_item_claims"'::text,'00:01:00'::interval), ('import_chunks'::text,'"better_supabase"."import_chunk_maintenance"'::text,'01:00:00'::interval), ('purge_chat_state'::text,'"better_supabase"."purge_chat_state"'::text,'00:15:00'::interval), ('purge_expired_trash'::text,'"better_supabase"."purge_expired_trash"'::text,'1 day'::interval), ('purge_idempotency_keys'::text,'better_supabase.purge_idempotency_keys'::text,'01:00:00'::interval), ('purge_rate_limits'::text,'better_supabase.purge_rate_limits'::text,'00:15:00'::interval), ('purge_usage_events'::text,'"better_supabase"."purge_usage_events"'::text,'1 day'::interval), ('purge_webhook_deliveries'::text,'"better_supabase"."purge_webhook_deliveries"'::text,'1 day'::interval), ('purge_webhooks'::text,'better_supabase.purge_webhooks'::text,'1 day'::interval)) j(job, fn, every_interval)
     LEFT JOIN better_supabase.maintenance_state s ON ((s.job = j.job)));

REVOKE ALL ON FUNCTION "api"."fail_import_chunk"(uuid, text, integer, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."fail_import_chunk"(uuid, text, integer, text, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_chunk_maintenance"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_chunk_maintenance"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_import_conflicts"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_import_conflicts"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."fail_import_chunk"(uuid, text, integer, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."fail_import_chunk"(uuid, text, integer, text, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_chunk_maintenance"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_chunk_maintenance"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_import_conflicts"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_import_conflicts"(uuid, text, text, integer) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."maintenance_jobs" TO "service_role";
