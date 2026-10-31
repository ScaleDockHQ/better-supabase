SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.data_restore_tables()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."data_restore_tables"() $function$;

CREATE OR REPLACE FUNCTION api.restore_data_row (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_data_row"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.data_restore_tables()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
  with listed as (
    select t.name, t.tbl, t.col, t.omit, to_regclass(t.tbl) as oid
    from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = 'organization' and t.exported and to_regclass(t.tbl) is not null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', l.name,
    'tenantColumn', l.col,
    'columns', (
      select coalesce(jsonb_agg(a.attname order by a.attnum), '[]'::jsonb)
      from pg_catalog.pg_attribute a
      where a.attrelid = l.oid and a.attnum > 0 and not a.attisdropped
        and a.attgenerated = '' and a.attidentity <> 'a'
        and a.attname <> all (coalesce(l.omit, '{}'))
    ),
    'keyColumns', (
      select coalesce(jsonb_agg(a.attname order by k.ord), '[]'::jsonb)
      from pg_catalog.pg_constraint c
      cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
      join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
      where c.conrelid = l.oid and c.contype = 'p' and a.attname <> l.col
    ),
    'references', (
      select coalesce(jsonb_agg(distinct o.name), '[]'::jsonb)
      from pg_catalog.pg_constraint c
      join listed o on o.oid = c.confrelid
      where c.conrelid = l.oid and c.contype = 'f' and c.confrelid <> c.conrelid
    )
  ) order by l.name), '[]'::jsonb)
  from listed l
  );
end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_apply_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['data_lifecycle_row', 'supplier_item', 'product_identifier', 'customer']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        case v_entity
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        case v_entity
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;

        v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
        if not exists (
          select 1 from jsonb_array_elements(v_subjects) s
          where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
        ) then
          raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
        end if;

        for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
        end loop;

        if v_found then
          v_updated := v_updated + 1;
        else
          v_inserted := v_inserted + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_data_row (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_name text := item #>> '{data,table}';
  v_row jsonb := item #> '{data,row}';
  v_tenant text := item ->> 'tenant';
  v_table jsonb;
  v_tbl text;
  v_tenant_col text;
  v_columns text[];
  v_keys text[];
  v_given text[];
  v_cols text[];
  v_pk text[];
  v_sets text[];
  v_sql text;
  v_count bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role restores data' using errcode = '42501', hint = 'DATA_RESTORE_FORBIDDEN';
  end if;
  if v_name is null or jsonb_typeof(v_row) is distinct from 'object' then
    raise exception 'an item needs data.table and a data.row object' using errcode = '22023', hint = 'DATA_RESTORE_ROW_INVALID';
  end if;
  select x.value into v_table
  from jsonb_array_elements("better_supabase"."data_restore_tables"()) x
  where x.value ->> 'name' = v_name;
  if v_table is null then
    raise exception 'The restore has no table %', v_name using errcode = '22023', hint = 'DATA_RESTORE_TABLE';
  end if;
  select t.tbl into v_tbl from "better_supabase"."data_lifecycle_tables"() t
  where t.subject = 'organization' and t.name = v_name and t.exported;
  v_tenant_col := v_table ->> 'tenantColumn';
  select coalesce(array_agg(c.value), '{}') into v_columns from jsonb_array_elements_text(v_table -> 'columns') c;
  select coalesce(array_agg(c.value), '{}') into v_keys from jsonb_array_elements_text(v_table -> 'keyColumns') c;
  select coalesce(array_agg(k.key), '{}') into v_given from jsonb_object_keys(v_row) k(key);
  if exists (select 1 from unnest(v_given) g where g <> all (v_columns)) then
    raise exception 'The table % has no column %', v_name, (select g from unnest(v_given) g where g <> all (v_columns) limit 1) using errcode = '22023', hint = 'DATA_RESTORE_COLUMN';
  end if;

  select array_agg(distinct c) into v_cols from unnest(v_given || array[v_tenant_col]) c;
  v_row := v_row || pg_catalog.jsonb_build_object(v_tenant_col, v_tenant);
  v_pk := v_keys || case when v_tenant_col = any (
    select a.attname from pg_catalog.pg_constraint c
    cross join lateral unnest(c.conkey) k(attnum)
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.conrelid = to_regclass(v_tbl) and c.contype = 'p'
  ) then array[v_tenant_col] else '{}'::text[] end;

  v_sql := pg_catalog.format(
    'insert into %s as t (%s) select %s from jsonb_populate_record(null::%s, $1) r',
    v_tbl,
    (select string_agg(pg_catalog.format('%I', c), ', ') from unnest(v_cols) c),
    (select string_agg(pg_catalog.format('r.%I', c), ', ') from unnest(v_cols) c),
    v_tbl
  );
  if cardinality(v_pk) > 0 then
    select array_agg(pg_catalog.format('%I = excluded.%I', c, c)) into v_sets
    from unnest(v_cols) c where c <> all (v_pk);
    v_sql := v_sql || pg_catalog.format(
      ' on conflict ' || '(%s) do update set %s where t.%I::text = excluded.%I::text',
      (select string_agg(pg_catalog.format('%I', c), ', ') from unnest(v_pk) c),
      coalesce(array_to_string(v_sets, ', '), pg_catalog.format('%I = excluded.%I', v_pk[1], v_pk[1])),
      v_tenant_col, v_tenant_col
    );
  end if;
  execute v_sql using v_row;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'The row of % belongs to another organization', v_name using errcode = '23505', hint = 'DATA_RESTORE_ROW_CONFLICT';
  end if;
  return pg_catalog.jsonb_build_object('subjectId', item ->> 'key', 'subjectType', 'data_lifecycle_row');
end;
$function$;

REVOKE ALL ON FUNCTION "api"."data_restore_tables"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."data_restore_tables"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."restore_data_row"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_data_row"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."data_restore_tables"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."data_restore_tables"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_data_row"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_data_row"(uuid, jsonb, text) TO "service_role";
