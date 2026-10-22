SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."read_field_values"(uuid, text, text);

CREATE TABLE "public"."client_notes" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "client_name"     text                     NOT NULL,
  "diagnosis"       text,
  "birth_date"      text,
  CONSTRAINT "client_notes_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."client_notes"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."client_notes" FROM "anon";

ALTER TABLE "better_supabase"."field_definitions"
  ADD COLUMN "encrypted" boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION api.drop_field_key (
  owner text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drop_field_key"($1) $function$;

CREATE OR REPLACE FUNCTION api.encrypt_field_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."encrypt_field_definition"($1) $function$;

CREATE OR REPLACE FUNCTION api.field_decrypt (
  owner text,
  value text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."field_decrypt"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.field_encrypt (
  owner text,
  value text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."field_encrypt"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.client_notes_seal()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_owner text := 'tenant:' || (new."organization_id")::text;
  v_old_owner text;
  v_moved boolean := false;
  v_key text;
begin
  if tg_op = 'UPDATE' then
    v_old_owner := 'tenant:' || (old."organization_id")::text;
    v_moved := v_owner is distinct from v_old_owner;
  end if;
  if new."diagnosis" is not null and (case when tg_op = 'INSERT' then true else new."diagnosis" is distinct from old."diagnosis" end or left(new."diagnosis", 5) <> 'bsf1:') then
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."diagnosis" := "better_supabase"."field_seal"(v_key, new."diagnosis");
  elsif new."diagnosis" is not null and v_moved then
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."diagnosis" := "better_supabase"."field_seal"(v_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."diagnosis"));
  end if;
  if new."birth_date" is not null and (case when tg_op = 'INSERT' then true else new."birth_date" is distinct from old."birth_date" end or left(new."birth_date", 5) <> 'bsf1:') then
    new."birth_date" := ((new."birth_date")::date)::text;
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."birth_date" := "better_supabase"."field_seal"(v_key, new."birth_date");
  elsif new."birth_date" is not null and v_moved then
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."birth_date" := "better_supabase"."field_seal"(v_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."birth_date"));
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drop_field_key (
  owner text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role drops field keys' using errcode = '42501', hint = 'FIELD_KEY_FORBIDDEN';
  end if;
  delete from vault.secrets s where s.name = 'bs:field-key:' || drop_field_key.owner;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('field_key.dropped', jsonb_build_object('owner', drop_field_key.owner), 'field-keys/' || drop_field_key.owner, null, null, 'better-supabase/field-encryption');
  perform better_supabase.audit_event(
    event_type => 'field_key.dropped',
    category => 'security',
    target_type => 'field_key',
    record_id => drop_field_key.owner,
    metadata => jsonb_build_object('owner', drop_field_key.owner)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.encrypt_field_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_key text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "type" into v_tenant, v_type from "better_supabase"."field_definitions" where "id" = encrypt_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if v_type not in ('text', 'email', 'url') then
    raise exception 'only text fields can be encrypted' using errcode = '22023', hint = 'FIELD_NOT_ENCRYPTABLE';
  end if;
  v_key := "better_supabase"."field_key"('tenant:' || v_tenant::text, true);
  update "better_supabase"."field_definitions" set "encrypted" = true where "id" = encrypt_field_definition.definition;
  update "better_supabase"."field_values" set "value_text" = "better_supabase"."field_seal"(v_key, "value_text")
  where "definition_id" = encrypt_field_definition.definition
    and "value_text" is not null
    and left("value_text", 5) <> 'bsf1:';
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_decrypt (
  owner text,
  value text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if field_decrypt.value is null then
    return null;
  end if;
  return "better_supabase"."field_open"("better_supabase"."field_key"(field_decrypt.owner, false), field_decrypt.value);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_encrypt (
  owner text,
  value text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if field_encrypt.value is null then
    return null;
  end if;
  return "better_supabase"."field_seal"("better_supabase"."field_key"(field_encrypt.owner, true), field_encrypt.value);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_key (
  owner text,
  make  boolean DEFAULT true
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_key text;
begin
  if field_key.owner is null or length(field_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-key:' || field_key.owner;
  if v_key is not null or not field_key.make then
    return v_key;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-key:' || field_key.owner, 0));
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-key:' || field_key.owner;
  if v_key is null then
    v_key := encode(extensions.gen_random_bytes(32), 'base64');
    perform vault.create_secret(v_key, 'bs:field-key:' || field_key.owner, 'better-supabase field encryption key');
  end if;
  return v_key;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_open (
  key   text,
  value text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case
    when field_open.value is null then null
    when left(field_open.value, 5) <> 'bsf1:' then field_open.value
    when field_open.key is null then null
    else extensions.pgp_sym_decrypt(decode(substr(field_open.value, 6), 'base64'), field_open.key)
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_seal (
  key   text,
  value text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select case when field_seal.value is null then null
    else 'bsf1:' || translate(encode(extensions.pgp_sym_encrypt(field_seal.value, field_seal.key, 'cipher-algo=aes256, s2k-mode=1'), 'base64'), E'\n', '')
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_field_definitions (
  tenant uuid,
  entity text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.read_field_values (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_values jsonb;
  v_key text;
  v_read jsonb;
begin
  v_key := "better_supabase"."field_key"('tenant:' || read_field_values.tenant::text, false);
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', case when coalesce(d."encrypted", false) then "better_supabase"."field_open"(v_key, v."value_text") else v."value_text" end)), '[]'::jsonb),
    jsonb_agg(v."id") filter (where coalesce(d."encrypted", false) or coalesce(d."sensitive", false))
  into v_values, v_read
  from "better_supabase"."field_values" v
  left join "better_supabase"."field_definitions" d on d."id" = v."definition_id"
  where v."tenant_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.sensitive.read')), false));
  if v_read is not null then
    perform better_supabase.audit_event(
    event_type => 'field_value.viewed',
    category => 'read',
    target_type => 'field_value',
    record_id => read_field_values.subject_id,
    summary => 'Read ' || jsonb_array_length(v_read)::text || ' protected field value(s) of ' || read_field_values.subject_type,
    tenant => (read_field_values.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', read_field_values.tenant, 'subjectType', read_field_values.subject_type, 'subjectId', read_field_values.subject_id, 'ids', v_read)
  );
  end if;
  return v_values;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_field_value (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  definition   uuid,
  value        text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || set_field_value.tenant::text, set_field_value.value) else set_field_value.value end)
  returning "id" into v_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id), 'field-values/' || v_id::text, (set_field_value.tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.client_notes_reveal (
  ids uuid[]
)
  RETURNS TABLE (
    id         uuid,
    diagnosis  text,
    birth_date date
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_read record;
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role reveal client_notes' using errcode = '42501', hint = 'APP_REVEAL_FORBIDDEN';
  end if;
  if coalesce(cardinality(client_notes_reveal.ids), 0) > 500 then
    raise exception 'reveal at most 500 rows of client_notes per call' using errcode = '22023', hint = 'APP_REVEAL_TOO_MANY';
  end if;
  for v_read in
    select t."organization_id" as tenant, jsonb_agg(t.id order by t.id) as ids
    from "public"."client_notes" t
    where t.id = any (client_notes_reveal.ids) and (v_service or ("organization_id" in (select better_supabase.member_organization_ids()) and (select better_supabase.session_active())))
    group by 1
  loop
    perform better_supabase.audit_event(
    event_type => 'client_notes.viewed',
    category => 'read',
    target_type => 'client_notes',
    record_id => case when jsonb_array_length(v_read.ids) = 1 then v_read.ids ->> 0 end,
    summary => 'Revealed ' || jsonb_array_length(v_read.ids)::text || ' ' || 'client_notes' || ' record(s)',
    tenant => (v_read.tenant)::uuid,
    metadata => jsonb_build_object('ids', v_read.ids, 'columns', '["diagnosis","birth_date"]'::jsonb)
  );
  end loop;
  return query
    with r as materialized (
      select t.id, 'tenant:' || (t."organization_id")::text as bs_owner, t."diagnosis", t."birth_date"
      from "public"."client_notes" t
      where t.id = any (client_notes_reveal.ids) and (v_service or ("organization_id" in (select better_supabase.member_organization_ids()) and (select better_supabase.session_active())))
    ),
    k as materialized (
      select o.bs_owner, "better_supabase"."field_key"(o.bs_owner, false) as bs_key
      from (select distinct r.bs_owner from r) o
    )
    select r.id, ("better_supabase"."field_open"(k.bs_key, r."diagnosis"))::text, ("better_supabase"."field_open"(k.bs_key, r."birth_date"))::date
    from r join k on k.bs_owner = r.bs_owner;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."client_notes_reveal"(uuid[]) FROM PUBLIC, "anon";

ALTER TABLE "public"."client_notes"
  ADD CONSTRAINT "client_notes_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

CREATE INDEX client_notes_organization_id_idx ON public.client_notes USING btree (organization_id);

CREATE TRIGGER bs_seal_fields
  BEFORE INSERT OR UPDATE OF organization_id, diagnosis, birth_date ON public.client_notes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.client_notes_seal();

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON public.client_notes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE POLICY "bs_session_active" ON "public"."client_notes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));

CREATE POLICY "client_notes_delete" ON "public"."client_notes"
  FOR DELETE
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "client_notes_insert" ON "public"."client_notes"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "client_notes_select" ON "public"."client_notes"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "client_notes_update" ON "public"."client_notes"
  FOR UPDATE
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

REVOKE ALL ON FUNCTION "api"."drop_field_key"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drop_field_key"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."encrypt_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."encrypt_field_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."field_decrypt"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."field_decrypt"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."field_encrypt"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."field_encrypt"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."client_notes_seal"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."drop_field_key"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drop_field_key"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."encrypt_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."encrypt_field_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."field_decrypt"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."field_decrypt"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."field_encrypt"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."field_encrypt"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."field_key"(text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."field_open"(text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."field_seal"(text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."read_field_values"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."read_field_values"(uuid, text, text) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "public"."client_notes_reveal"(uuid[]) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."client_notes_reveal"(uuid[]) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."client_notes_reveal"(uuid[]) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."client_notes_reveal"(uuid[]) TO "service_role";

REVOKE ALL ON TABLE "public"."client_notes" FROM "authenticated";

REVOKE ALL ("birth_date") ON TABLE "public"."client_notes" FROM "authenticated";

GRANT INSERT ("birth_date"), UPDATE ("birth_date") ON TABLE "public"."client_notes" TO "authenticated";

REVOKE ALL ("client_name") ON TABLE "public"."client_notes" FROM "authenticated";

GRANT INSERT ("client_name"), SELECT ("client_name"), UPDATE ("client_name") ON TABLE "public"."client_notes" TO "authenticated";

REVOKE ALL ("created_at") ON TABLE "public"."client_notes" FROM "authenticated";

GRANT INSERT ("created_at"), SELECT ("created_at"), UPDATE ("created_at") ON TABLE "public"."client_notes" TO "authenticated";

REVOKE ALL ("diagnosis") ON TABLE "public"."client_notes" FROM "authenticated";

GRANT INSERT ("diagnosis"), UPDATE ("diagnosis") ON TABLE "public"."client_notes" TO "authenticated";

REVOKE ALL ("id") ON TABLE "public"."client_notes" FROM "authenticated";

GRANT INSERT ("id"), SELECT ("id"), UPDATE ("id") ON TABLE "public"."client_notes" TO "authenticated";

REVOKE ALL ("organization_id") ON TABLE "public"."client_notes" FROM "authenticated";

GRANT INSERT ("organization_id"), SELECT ("organization_id"), UPDATE ("organization_id") ON TABLE "public"."client_notes" TO "authenticated";

REVOKE ALL ("updated_at") ON TABLE "public"."client_notes" FROM "authenticated";

GRANT INSERT ("updated_at"), SELECT ("updated_at"), UPDATE ("updated_at") ON TABLE "public"."client_notes" TO "authenticated";

GRANT DELETE ON TABLE "public"."client_notes" TO "authenticated";

REVOKE ALL ON TABLE "public"."client_notes" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."client_notes" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."client_notes" TO "service_role";
