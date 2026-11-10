SET local check_function_bodies = off;

DROP TRIGGER "bsb_search_drive_node_watch_0" ON "better_supabase"."drive_node_texts";

CREATE OR REPLACE FUNCTION api.usage_remaining (
  tenant uuid,
  meter  text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."usage_remaining"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.audit (
  target          regclass,
  ignore          text[]       DEFAULT '{}'::text[],
  replace_trigger boolean      DEFAULT false,
  redact          text[]       DEFAULT '{}'::text[],
  category        text         DEFAULT NULL::text,
  event_prefix    text         DEFAULT NULL::text,
  target_type     text         DEFAULT NULL::text,
  tenant_column   text         DEFAULT NULL::text,
  label_column    text         DEFAULT NULL::text,
  tenant_path     text         DEFAULT NULL::text,
  tenant_function regprocedure DEFAULT NULL::regprocedure,
  deferred        boolean      DEFAULT false,
  statement       boolean      DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  keys text[];
  path_steps jsonb := '[]';
  path_column text;
  parts text[];
  cur_rel regclass := target;
  cur_col text;
  ref_rel regclass;
  ref_col text;
  segment text;
  seg_table text;
  seg_read text;
  base_settings jsonb;
  trigger_kind text := case when audit.deferred then 'constraint ' else '' end;
  trigger_timing text := case when audit.deferred then 'deferrable initially deferred ' else '' end;
begin
  if audit.statement then
    if audit.deferred or audit.tenant_path is not null or audit.tenant_function is not null then
      raise exception 'audit(statement => true) does not combine with deferred, tenant_path or tenant_function';
    end if;
    if not exists (select 1 from pg_catalog.pg_index i where i.indrelid = audit.target and i.indisprimary) then
      raise exception 'audit(statement => true) needs a primary key on %', audit.target;
    end if;
  end if;
  if audit.tenant_path is not null then
    parts := regexp_split_to_array(btrim(audit.tenant_path), '\s*->\s*');
    if coalesce(array_length(parts, 1), 0) < 2 then
      raise exception 'tenant_path % needs a column and at least one table.column hop', audit.tenant_path;
    end if;
    path_column := parts[1];
    cur_col := path_column;
    for i in 2..array_length(parts, 1) loop
      segment := parts[i];
      seg_read := substring(segment from '[^.]+$');
      seg_table := substring(segment from '^(.*)\.[^.]+$');
      if seg_read is null or seg_table is null then
        raise exception 'tenant_path hop % must be table.column', segment;
      end if;
      select con.confrelid::regclass, a.attname::text into ref_rel, ref_col
      from pg_catalog.pg_constraint con
      join pg_catalog.pg_attribute a on a.attrelid = con.confrelid and a.attnum = con.confkey[1]
      where con.contype = 'f' and con.conrelid = cur_rel and array_length(con.conkey, 1) = 1
        and con.conkey[1] = (
          select c.attnum from pg_catalog.pg_attribute c
          where c.attrelid = cur_rel and c.attname = cur_col and not c.attisdropped
        );
      if ref_rel is null then
        raise exception 'tenant_path: % has no foreign key on column %', cur_rel, cur_col;
      end if;
      if pg_catalog.to_regclass(case when position('.' in seg_table) > 0 then seg_table else (select n.nspname from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace where c.oid = audit.target) || '.' || seg_table end) is distinct from ref_rel then
        raise exception 'tenant_path: % does not reference %', cur_col, seg_table;
      end if;
      path_steps := path_steps || jsonb_build_array(jsonb_build_object('table', ref_rel::text, 'ref', ref_col, 'read', seg_read));
      cur_rel := ref_rel;
      cur_col := seg_read;
    end loop;
  end if;
  perform better_supabase.replace_equivalent_triggers(
    target, 'bsb_audit', 'audit', replace_trigger
  );
  select array_agg(c.attname::text order by k.ord) into keys
  from pg_catalog.pg_index i
  cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
  join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
  where i.indrelid = audit.target and i.indisprimary;
  delete from "better_supabase"."audited_tables" a where a."target" = audit.target;
  base_settings := jsonb_strip_nulls(jsonb_build_object(
    'ignore', to_jsonb(coalesce(audit.ignore, '{}')),
    'redact', to_jsonb(coalesce(audit.redact, '{}')),
    'key_columns', to_jsonb(keys),
    'category', audit.category,
    'event_prefix', audit.event_prefix,
    'target_type', audit.target_type,
    'tenant_column', audit.tenant_column,
    'label_column', audit.label_column,
    'tenant_path', case when audit.tenant_path is not null then jsonb_build_object('column', path_column, 'steps', path_steps) end,
    'tenant_function', audit.tenant_function::text
  ));
  execute format('drop trigger if exists bsb_audit on %s', target);
  execute format('drop trigger if exists bsb_audit_update on %s', target);
  execute format('drop trigger if exists bsb_audit_stmt_insert on %s', target);
  execute format('drop trigger if exists bsb_audit_stmt_update on %s', target);
  execute format('drop trigger if exists bsb_audit_stmt_delete on %s', target);
  if audit.statement then
    execute format(
      'create trigger bsb_audit_stmt_insert after insert on %s referencing new table as new_rows for each statement when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_statement_change(%L)',
      target, base_settings::text
    );
    execute format(
      'create trigger bsb_audit_stmt_update after update on %s referencing old table as old_rows new table as new_rows for each statement when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_statement_change(%L)',
      target, base_settings::text
    );
    execute format(
      'create trigger bsb_audit_stmt_delete after delete on %s referencing old table as old_rows for each statement when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_statement_change(%L)',
      target, base_settings::text
    );
  elsif cardinality(coalesce(audit.ignore, '{}')) > 0 then
    execute format(
      'create %strigger bsb_audit after insert or delete on %s %sfor each row when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_row_change(%L)',
      trigger_kind, target, trigger_timing, base_settings::text
    );
    execute format(
      'create %strigger bsb_audit_update after update on %s %sfor each row when (((to_jsonb(old) - %L::text[]) is distinct from (to_jsonb(new) - %L::text[])) and (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'')) execute function better_supabase.audit_row_change(%L)',
      trigger_kind, target, trigger_timing, audit.ignore, audit.ignore, base_settings::text
    );
  else
    execute format(
      'create %strigger bsb_audit after insert or update or delete on %s %sfor each row when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_row_change(%L)',
      trigger_kind, target, trigger_timing, base_settings::text
    );
  end if;
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
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
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
  return v_counts;
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
        and s."archived_at" is null;
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
    when 'activity' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."activities" s
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
    when 'risk' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."cause"::text, s."consequence"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."risks" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'case' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."root_cause"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."cases" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."scope"::text, s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."inspections" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."location"::text, s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."meetings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'content_entry' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."content_entries" s
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
      select s."tenant_id", f."name"::text, nullif(concat_ws(E'\n', f."content"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."drive_nodes" s
        join "better_supabase"."drive_node_search" f on f."id" = s."id"
        where s."id" = (search_refresh.subject_id)::uuid
        and f."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.subjects' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
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
    "updated_at" = now()
  where ("better_supabase"."search_documents"."tenant_id", "better_supabase"."search_documents"."title", "better_supabase"."search_documents"."body", "better_supabase"."search_documents"."url")
    is distinct from (excluded."tenant_id", excluded."title", excluded."body", excluded."url");
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

CREATE OR REPLACE FUNCTION better_supabase.usage_overview (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  return (
    with meters as (
      select jsonb_object_keys("better_supabase"."usage_meters"()) as meter
      union
      select q."meter" from "better_supabase"."usage_quotas" q
      where q."tenant_id" = usage_overview.tenant
        or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any (better_supabase.tenant_entitlements(usage_overview.tenant)) or q."plan" = any (better_supabase.tenant_plans(usage_overview.tenant))))
      union
      select distinct c."meter" from "better_supabase"."usage_counters" c
      where c."tenant_id" = usage_overview.tenant
    ),
    quota as (
      select distinct on (q."meter")
        q."meter" as meter,
        q."limit" as quota_limit,
        q."period" as period
      from "better_supabase"."usage_quotas" q
      join meters m on m.meter = q."meter"
      where q."tenant_id" = usage_overview.tenant
        or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any (better_supabase.tenant_entitlements(usage_overview.tenant)) or q."plan" = any (better_supabase.tenant_plans(usage_overview.tenant))))
      order by q."meter", (q."tenant_id" is not null) desc, q."limit" desc nulls first
    ),
    chosen as (
      select m.meter,
        quota.quota_limit,
        quota.period as quota_period,
        coalesce(quota.period, 'month') as period
      from meters m
      left join quota on quota.meter = m.meter
    ),
    win as (
      select p.period, w.starts_at, w.ends_at
      from (select distinct chosen.period from chosen) p
      cross join lateral "better_supabase"."usage_window"(usage_overview.tenant, p.period) w
    ),
    used as (
      select ch.meter, coalesce(sum(c."value"), 0)::numeric as used
      from chosen ch
      join win w on w.period = ch.period
      left join "better_supabase"."usage_counters" c
        on c."tenant_id" = usage_overview.tenant
        and c."meter" = ch.meter
        and c."day" >= (w.starts_at at time zone 'utc')::date
        and c."day" < greatest((w.ends_at at time zone 'utc')::date, (w.starts_at at time zone 'utc')::date + 1)
      group by ch.meter
    ),
    catalog as (
      select "better_supabase"."usage_meters"() as meters
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'meter', ch.meter,
        'used', u.used,
        'limit', ch.quota_limit,
        'remaining', case
          when ch.quota_limit is null then null
          else greatest(ch.quota_limit - u.used, 0)
        end,
        'unlimited', ch.quota_period is not null and ch.quota_limit is null,
        'period', ch.period,
        'resets_at', w.ends_at,
        'starts_at', w.starts_at
      ) || coalesce(catalog.meters -> ch.meter, '{}'::jsonb)
      order by ch.meter
    ), '[]'::jsonb)
    from chosen ch
    join used u on u.meter = ch.meter
    join win w on w.period = ch.period
    cross join catalog
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_remaining (
  tenant uuid,
  meter  text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  return (
    with quota as (
      select q."limit" as quota_limit, q."period" as period
      from "better_supabase"."usage_quotas" q
      where q."meter" = usage_remaining.meter
        and (q."tenant_id" = usage_remaining.tenant or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any (better_supabase.tenant_entitlements(tenant)) or q."plan" = any (better_supabase.tenant_plans(tenant)))))
      order by (q."tenant_id" is not null) desc, q."limit" desc nulls first
      limit 1
    ),
    win as (
      select w.starts_at, w.ends_at
      from "better_supabase"."usage_window"(usage_remaining.tenant, coalesce((select quota.period from quota), 'month')) w
    ),
    used as (
      select coalesce(sum(c."value"), 0)::numeric as used
      from "better_supabase"."usage_counters" c
      cross join win w
      where c."tenant_id" = usage_remaining.tenant
        and c."meter" = usage_remaining.meter
        and c."day" >= (w.starts_at at time zone 'utc')::date
        and c."day" < greatest((w.ends_at at time zone 'utc')::date, (w.starts_at at time zone 'utc')::date + 1)
    )
    select jsonb_build_object(
      'used', (select used.used from used),
      'limit', (select quota.quota_limit from quota),
      'remaining', case
        when (select quota.quota_limit from quota) is null then null
        else greatest((select quota.quota_limit from quota) - (select used.used from used), 0)
      end,
      'resets_at', (select win.ends_at from win)
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_status (
  tenant uuid,
  meter  text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  return (
    with quota as (
      select q."limit" as quota_limit, q."period" as period
      from "better_supabase"."usage_quotas" q
      where q."meter" = usage_status.meter
        and (q."tenant_id" = usage_status.tenant or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any (better_supabase.tenant_entitlements(tenant)) or q."plan" = any (better_supabase.tenant_plans(tenant)))))
      order by (q."tenant_id" is not null) desc, q."limit" desc nulls first
      limit 1
    ),
    win as (
      select w.starts_at, w.ends_at
      from "better_supabase"."usage_window"(usage_status.tenant, coalesce((select quota.period from quota), 'month')) w
    ),
    used as (
      select coalesce(sum(c."value"), 0)::numeric as used
      from "better_supabase"."usage_counters" c
      cross join win w
      where c."tenant_id" = usage_status.tenant
        and c."meter" = usage_status.meter
        and c."day" >= (w.starts_at at time zone 'utc')::date
        and c."day" < greatest((w.ends_at at time zone 'utc')::date, (w.starts_at at time zone 'utc')::date + 1)
    )
    select jsonb_build_object(
      'meter', usage_status.meter,
      'used', (select used.used from used),
      'limit', (select quota.quota_limit from quota),
      'remaining', case
        when (select quota.quota_limit from quota) is null then null
        else greatest((select quota.quota_limit from quota) - (select used.used from used), 0)
      end,
      'unlimited', (select quota.period from quota) is not null and (select quota.quota_limit from quota) is null,
      'period', coalesce((select quota.period from quota), 'month'),
      'resets_at', (select win.ends_at from win),
      'starts_at', (select win.starts_at from win)
    ) || coalesce("better_supabase"."usage_meters"() -> usage_status.meter, '{}'::jsonb)
  );
end;
$function$;

CREATE TRIGGER bsb_search_drive_node_watch_0_u
  AFTER UPDATE OF node_id, content ON better_supabase.drive_node_texts
  FOR EACH ROW
  WHEN (((old.node_id IS DISTINCT FROM new.node_id) OR (old.content IS DISTINCT FROM new.content)))
  EXECUTE FUNCTION better_supabase.search_watch_drive_node_0();

CREATE TRIGGER bsb_search_drive_node_watch_0
  AFTER INSERT OR DELETE ON better_supabase.drive_node_texts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_watch_drive_node_0();

REVOKE ALL ON FUNCTION "api"."usage_remaining"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_remaining"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_remaining"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_remaining"(uuid, text) TO "authenticated", "service_role";
