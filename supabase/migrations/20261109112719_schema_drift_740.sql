SET local check_function_bodies = off;

DROP POLICY "bsb_attachments_insert" ON "better_supabase"."attachments";

DROP POLICY "bsb_attachments_read" ON "better_supabase"."attachments";

DROP POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachments";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."attachments";

CREATE OR REPLACE FUNCTION better_supabase.import_upsert_batch (
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
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);
  perform set_config('better_supabase.search_deferred', 'on', true);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
    perform "better_supabase"."search_refresh_dirty"();
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_enqueue (
  subject_type text,
  subject_id   text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_key text := search_enqueue.subject_type || E'\x1f' || search_enqueue.subject_id;
  v_dirty text;
begin
  if coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' then
    v_dirty := coalesce(current_setting('better_supabase.search_dirty', true), '');
    if position(E'\n' || v_key || E'\n' in E'\n' || v_dirty) = 0 then
      perform set_config('better_supabase.search_dirty', v_dirty || v_key || E'\n', true);
    end if;
  else
    perform "better_supabase"."search_refresh"(search_enqueue.subject_type, search_enqueue.subject_id);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh_dirty()
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_count integer := 0;
  v_dirty text := coalesce(current_setting('better_supabase.search_dirty', true), '');
  v_line text;
begin
  perform set_config('better_supabase.search_dirty', '', true);
  for v_line in select l from string_to_table(v_dirty, E'\n') l where l <> '' loop
    if "better_supabase"."search_refresh"(split_part(v_line, E'\x1f', 1), split_part(v_line, E'\x1f', 2)) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$function$;

CREATE POLICY "bsb_attachments_insert" ON "better_supabase"."attachments"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((uploaded_by = ( SELECT auth.uid() AS uid)) AND (((subject_type = 'message'::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.send'::text) AS
    tenant_ids_with))) OR ((subject_type = 'conversation'::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.send'::text) AS tenant_ids_with))) OR
    ((subject_type = 'expense_line'::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.submit'::text) AS tenant_ids_with))) OR
    ((NOT COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'expense_line'::text])), false)) AND (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.upload'::text) AS tenant_ids_with))) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('upload'::text) g(tenant, subject_type, subject_id)))) AND
     ((subject_type IS NULL) OR ((((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))) OR
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = attachments.tenant_id) AND ((attachments.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.id = attachments.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_attachments_read" ON "better_supabase"."attachments"
  FOR SELECT
  TO "authenticated"
  USING
    ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))) AND
     ((subject_type IS NULL) OR ((((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))) OR
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = attachments.tenant_id) AND ((attachments.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.id = attachments.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END))));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH
    CHECK
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((uploaded_by = ( SELECT auth.uid() AS uid)) AND (((subject_type =
    'message'::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.send'::text) AS tenant_ids_with))) OR
    ((subject_type = 'conversation'::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.send'::text) AS tenant_ids_with))) OR
    ((subject_type = 'expense_line'::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.submit'::text) AS tenant_ids_with))) OR
    ((NOT COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'expense_line'::text])), false)) AND (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.upload'::text) AS tenant_ids_with))) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('upload'::text) g(tenant, subject_type, subject_id)))) AND
     ((subject_type IS NULL) OR ((((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))) OR
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = attachments.tenant_id) AND ((attachments.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.id = attachments.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END)))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))) AND
     ((subject_type IS NULL) OR ((((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))) OR
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = attachments.tenant_id) AND ((attachments.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.id = attachments.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END)))));
