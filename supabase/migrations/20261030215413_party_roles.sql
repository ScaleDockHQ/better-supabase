SET local check_function_bodies = off;

DROP FUNCTION "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer);

DROP FUNCTION "api"."list_people"(uuid, text, text, uuid, text, uuid, integer);

DROP FUNCTION "better_supabase"."list_companies"(uuid, text, text, uuid, text, uuid, integer);

DROP FUNCTION "better_supabase"."list_people"(uuid, text, text, uuid, text, uuid, integer);

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "roles" text[] NOT NULL DEFAULT '{}'::text[];

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "payment_terms_days" integer;

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "credit_currency" text;

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "credit_limit" bigint;

ALTER TABLE "better_supabase"."companies"
  ADD COLUMN "supplier_status" text;

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "roles" text[] NOT NULL DEFAULT '{}'::text[];

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "payment_terms_days" integer;

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "credit_currency" text;

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "credit_limit" bigint;

ALTER TABLE "better_supabase"."people"
  ADD COLUMN "supplier_status" text;

CREATE OR REPLACE FUNCTION api.list_companies (
  tenant          uuid,
  search          text,
  lifecycle       text,
  owner           uuid,
  after_name      text,
  after_id        uuid,
  page_size       integer,
  role            text    DEFAULT NULL::text,
  supplier_status text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_companies"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.list_people (
  tenant          uuid,
  search          text,
  lifecycle       text,
  owner           uuid,
  after_name      text,
  after_id        uuid,
  page_size       integer,
  role            text    DEFAULT NULL::text,
  supplier_status text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_people"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.set_party_roles (
  party uuid,
  roles text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_party_roles"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_supplier_status (
  party  uuid,
  status text,
  reason text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_supplier_status"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.supplier_status_from_qualifications (
  party uuid
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."supplier_status_from_qualifications"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.company_people_of (
  company uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'payment_terms_days', p."payment_terms_days", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'supplier_status', p."supplier_status") || jsonb_build_object('role', l."role", 'is_primary', l."is_primary")
    order by l."is_primary" desc, lower(p."name"), p."id"), '[]'::jsonb)
  from "better_supabase"."company_people" l join "better_supabase"."people" p on p."id" = l."person_id"
  where l."company_id" = company_people_of.company and p."archived_at" is null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.find_person_by_identity (
  tenant  uuid,
  channel text,
  address text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(p) || jsonb_build_object('roles', p."roles", 'payment_terms_days', p."payment_terms_days", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'supplier_status', p."supplier_status") from "better_supabase"."person_identities" i
  join "better_supabase"."people" p on p."id" = i."person_id"
  where i."tenant_id" = find_person_by_identity.tenant
    and i."channel" = trim(find_person_by_identity.channel)
    and i."address" = trim(find_person_by_identity.address)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_companies (
  tenant          uuid,
  search          text,
  lifecycle       text,
  owner           uuid,
  after_name      text,
  after_id        uuid,
  page_size       integer,
  role            text    DEFAULT NULL::text,
  supplier_status text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_like text := '%' || replace(replace(replace(coalesce(list_companies.search, ''), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'payment_terms_days', p."payment_terms_days", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'supplier_status', p."supplier_status") order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."companies" x
      where x."tenant_id" = list_companies.tenant
        and x."archived_at" is null
        and (list_companies.search is null or x."name" ilike v_like or x."domain" ilike v_like)
        and (list_companies.lifecycle is null or x."lifecycle" = list_companies.lifecycle)
        and (list_companies.owner is null or x."owner_user_id" = list_companies.owner)
        and (list_companies.role is null or list_companies.role = any (x."roles"))
        and (list_companies.supplier_status is null or x."supplier_status" = list_companies.supplier_status)
        and (list_companies.after_name is null or (lower(x."name"), x."id") > (lower(list_companies.after_name), list_companies.after_id))
      order by lower(x."name"), x."id"
      limit least(greatest(coalesce(list_companies.page_size, 50), 1), 200)
    ) p
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_people (
  tenant          uuid,
  search          text,
  lifecycle       text,
  owner           uuid,
  after_name      text,
  after_id        uuid,
  page_size       integer,
  role            text    DEFAULT NULL::text,
  supplier_status text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_like text := '%' || replace(replace(replace(coalesce(list_people.search, ''), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'payment_terms_days', p."payment_terms_days", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'supplier_status', p."supplier_status") order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."people" x
      where x."tenant_id" = list_people.tenant
        and x."archived_at" is null
        and (list_people.search is null or x."name" ilike v_like or x."email" ilike v_like)
        and (list_people.lifecycle is null or x."lifecycle" = list_people.lifecycle)
        and (list_people.owner is null or x."owner_user_id" = list_people.owner)
        and (list_people.role is null or list_people.role = any (x."roles"))
        and (list_people.supplier_status is null or x."supplier_status" = list_people.supplier_status)
        and (list_people.after_name is null or (lower(x."name"), x."id") > (lower(list_people.after_name), list_people.after_id))
      order by lower(x."name"), x."id"
      limit least(greatest(coalesce(list_people.page_size, 50), 1), 200)
    ) p
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_companies (
  keep uuid,
  drop uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_keep "better_supabase"."companies";
  v_drop "better_supabase"."companies";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_keep from "better_supabase"."companies" x where x."id" = merge_companies.keep for update;
  select * into v_drop from "better_supabase"."companies" x where x."id" = merge_companies.drop for update;
  if v_keep."id" is null or v_drop."id" is null then
    raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if v_keep."tenant_id" <> v_drop."tenant_id" or v_keep."id" = v_drop."id" or v_drop."merged_into" is not null then
    raise exception 'merge two different, unmerged records of one organization' using errcode = '22023', hint = 'PARTY_MERGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'contacts.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."companies" x set "domain" = null, "merged_into" = merge_companies.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_companies.drop;
  update "better_supabase"."companies" x set "domain" = coalesce(x."domain", v_drop."domain"), "website" = coalesce(x."website", v_drop."website"), "vat_id" = coalesce(x."vat_id", v_drop."vat_id"), "owner_user_id" = coalesce(x."owner_user_id", v_drop."owner_user_id"), "payment_terms_days" = coalesce(x."payment_terms_days", v_drop."payment_terms_days"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
  where x."id" = merge_companies.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", merge_companies.keep, l."person_id", l."role", false
  from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop;
  update "better_supabase"."companies" x set "roles" = array(select distinct r from unnest(x."roles" || v_drop."roles") r order by 1) where x."id" = merge_companies.keep;
  perform better_supabase.merge_subject_refs('better_supabase.companies', merge_companies.keep::text, merge_companies.drop::text);
  perform "better_supabase".emit_event('company.merged', jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop), 'companies/' || merge_companies.keep::text, (v_keep."tenant_id"::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'company.merged',
    category => 'data',
    target_type => 'company',
    record_id => merge_companies.keep::text,
    target_label => v_keep."name",
    summary => 'merged ' || v_drop."name" || ' into ' || v_keep."name",
    tenant => (v_keep."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop)
  );
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status") from "better_supabase"."companies" x where x."id" = merge_companies.keep);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_people (
  keep uuid,
  drop uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_keep "better_supabase"."people";
  v_drop "better_supabase"."people";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_keep from "better_supabase"."people" x where x."id" = merge_people.keep for update;
  select * into v_drop from "better_supabase"."people" x where x."id" = merge_people.drop for update;
  if v_keep."id" is null or v_drop."id" is null then
    raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if v_keep."tenant_id" <> v_drop."tenant_id" or v_keep."id" = v_drop."id" or v_drop."merged_into" is not null then
    raise exception 'merge two different, unmerged records of one organization' using errcode = '22023', hint = 'PARTY_MERGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'contacts.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."people" x set "email" = null, "merged_into" = merge_people.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_people.drop;
  update "better_supabase"."people" x set "email" = coalesce(x."email", v_drop."email"), "phone" = coalesce(x."phone", v_drop."phone"), "title" = coalesce(x."title", v_drop."title"), "owner_user_id" = coalesce(x."owner_user_id", v_drop."owner_user_id"), "user_id" = coalesce(x."user_id", v_drop."user_id"), "payment_terms_days" = coalesce(x."payment_terms_days", v_drop."payment_terms_days"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
  where x."id" = merge_people.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", l."company_id", merge_people.keep, l."role", false
  from "better_supabase"."company_people" l where l."person_id" = merge_people.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."person_id" = merge_people.drop;
  update "better_supabase"."people" x set "roles" = array(select distinct r from unnest(x."roles" || v_drop."roles") r order by 1) where x."id" = merge_people.keep;
  update "better_supabase"."person_identities" i set "person_id" = merge_people.keep where i."person_id" = merge_people.drop;
  update "better_supabase"."inbox_conversations" x set "contact_id" = merge_people.keep where x."contact_id" = merge_people.drop;
  perform better_supabase.merge_subject_refs('better_supabase.people', merge_people.keep::text, merge_people.drop::text);
  perform "better_supabase".emit_event('person.merged', jsonb_build_object('organizationId', v_keep."tenant_id", 'personId', merge_people.keep, 'name', v_keep."name", 'mergedId', merge_people.drop), 'persons/' || merge_people.keep::text, (v_keep."tenant_id"::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'person.merged',
    category => 'data',
    target_type => 'person',
    record_id => merge_people.keep::text,
    target_label => v_keep."name",
    summary => 'merged ' || v_drop."name" || ' into ' || v_keep."name",
    tenant => (v_keep."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_keep."tenant_id", 'personId', merge_people.keep, 'name', v_keep."name", 'mergedId', merge_people.drop)
  );
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status") from "better_supabase"."people" x where x."id" = merge_people.keep);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.emergency' then 'access_requests.emergency'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'access-requests.review' then 'access_requests.review'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.readRestricted' then 'activities.read_restricted'
    when 'activities.write' then 'activities.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.admin' then 'ai_chat.manage'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.write'
    when 'ai-schedules.manage' then 'ai_schedules.manage'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.revert' then 'audit.revert'
    when 'audit.view' then 'audit.read'
    when 'audit.viewAll' then 'audit.read'
    when 'automations.admin' then 'automations.manage'
    when 'automations.edit' then 'automations.write'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk.run' then 'bulk.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'care-plans.evaluate' then 'care_plans.evaluate'
    when 'care-plans.manage' then 'care_plans.manage'
    when 'care-plans.publish' then 'care_plans.publish'
    when 'care-plans.read' then 'care_plans.read'
    when 'care-plans.write' then 'care_plans.write'
    when 'cases.close' then 'cases.close'
    when 'cases.create' then 'cases.create'
    when 'cases.manage' then 'cases.manage'
    when 'cases.read' then 'cases.read'
    when 'cases.write' then 'cases.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
    when 'contacts.approveSupplier' then 'contacts.approve_supplier'
    when 'contacts.manage' then 'contacts.manage'
    when 'contacts.read' then 'contacts.read'
    when 'contacts.write' then 'contacts.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.read_sensitive'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'employees.read' then 'employees.read'
    when 'employees.viewSensitive' then 'employees.read_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'manufacturing.manage' then 'manufacturing.manage'
    when 'manufacturing.produce' then 'manufacturing.produce'
    when 'manufacturing.read' then 'manufacturing.read'
    when 'manufacturing.write' then 'manufacturing.write'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
    when 'memory.manage' then 'memory.manage'
    when 'memory.read' then 'memory.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'numbering.assign'
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'saved_views.read'
    when 'saved-views.share' then 'saved_views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.edit' then 'segments.write'
    when 'segments.read' then 'segments.read'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_accounts.manage'
    when 'service-accounts.read' then 'service_accounts.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'tasks.manage'
    when 'tasks.read' then 'tasks.read'
    when 'tasks.write' then 'tasks.write'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
    when 'timeline.read' then 'timeline.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'waitlist.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow_editor.manage'
    when 'workflow-editor.edit' then 'workflow_editor.write'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflows.admin' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_company (
  tenant  uuid,
  company uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_company.company;
  v_created boolean := save_company.company is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_company.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_company.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_company.attrs ? 'lifecycle' and not (save_company.attrs ->> 'lifecycle' = any ('{lead,prospect,customer,churned}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_company.attrs ->> 'paymentTermsDays' is not null and (case when save_company.attrs ->> 'paymentTermsDays' ~ '^[0-9]{1,4}$' then (save_company.attrs ->> 'paymentTermsDays')::integer > 3650 else true end) then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditLimit' is not null and save_company.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditCurrency' is not null and upper(trim(save_company.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' <> save_company.attrs ? 'creditCurrency' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' and (save_company.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_company.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_company_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_company.tenant, save_company.company, save_company.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_company.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."companies" ("tenant_id", "name", "domain", "website", "vat_id", "lifecycle", "owner_user_id", "payment_terms_days", "credit_limit", "credit_currency", "address", "created_by")
      values (save_company.tenant, nullif(trim(save_company.attrs ->> 'name'), ''), lower(nullif(trim(save_company.attrs ->> 'domain'), '')), nullif(trim(save_company.attrs ->> 'website'), ''), nullif(trim(save_company.attrs ->> 'vatId'), ''), coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(save_company.attrs ->> 'ownerId', '')::uuid, nullif(trim(save_company.attrs ->> 'paymentTermsDays'), '')::integer, nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')), save_company.attrs -> 'address', auth.uid())
      returning "id", "owner_user_id" into v_id, v_owner;
    else
      select x."owner_user_id" into v_previous_owner from "better_supabase"."companies" x
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant;
      update "better_supabase"."companies" x set "name" = case when save_company.attrs ? 'name' then coalesce(nullif(trim(save_company.attrs ->> 'name'), ''), x."name") else x."name" end,
        "domain" = case when save_company.attrs ? 'domain' then lower(nullif(trim(save_company.attrs ->> 'domain'), '')) else x."domain" end,
        "website" = case when save_company.attrs ? 'website' then nullif(trim(save_company.attrs ->> 'website'), '') else x."website" end,
        "vat_id" = case when save_company.attrs ? 'vatId' then nullif(trim(save_company.attrs ->> 'vatId'), '') else x."vat_id" end,
        "lifecycle" = case when save_company.attrs ? 'lifecycle' then coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_user_id" = case when save_company.attrs ? 'ownerId' then nullif(save_company.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
        "payment_terms_days" = case when save_company.attrs ? 'paymentTermsDays' then nullif(trim(save_company.attrs ->> 'paymentTermsDays'), '')::integer else x."payment_terms_days" end,
        "credit_limit" = case when save_company.attrs ? 'creditLimit' then nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_company.attrs ? 'creditCurrency' then upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "address" = case when save_company.attrs ? 'address' then save_company.attrs -> 'address' else x."address" end,
        "updated_at" = now()
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant and x."merged_into" is null
      returning x."owner_user_id" into v_owner;
      if not found then
        raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status") into v_row from "better_supabase"."companies" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('company.created', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('company.updated', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (save_company.tenant, v_owner, 'company', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_company_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_person (
  tenant uuid,
  person uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_person.person;
  v_created boolean := save_person.person is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_person.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_person.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_person.attrs ? 'lifecycle' and not (save_person.attrs ->> 'lifecycle' = any ('{lead,mql,sql,opportunity,customer}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_person.attrs ->> 'paymentTermsDays' is not null and (case when save_person.attrs ->> 'paymentTermsDays' ~ '^[0-9]{1,4}$' then (save_person.attrs ->> 'paymentTermsDays')::integer > 3650 else true end) then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditLimit' is not null and save_person.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditCurrency' is not null and upper(trim(save_person.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' <> save_person.attrs ? 'creditCurrency' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' and (save_person.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_person.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_person_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_person.tenant, save_person.person, save_person.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_person.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "title", "lifecycle", "owner_user_id", "user_id", "payment_terms_days", "credit_limit", "credit_currency", "created_by")
      values (save_person.tenant, nullif(trim(save_person.attrs ->> 'name'), ''), lower(nullif(trim(save_person.attrs ->> 'email'), '')), nullif(trim(save_person.attrs ->> 'phone'), ''), nullif(trim(save_person.attrs ->> 'title'), ''), coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(save_person.attrs ->> 'ownerId', '')::uuid, nullif(save_person.attrs ->> 'userId', '')::uuid, nullif(trim(save_person.attrs ->> 'paymentTermsDays'), '')::integer, nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')), auth.uid())
      returning "id", "owner_user_id" into v_id, v_owner;
    else
      select x."owner_user_id" into v_previous_owner from "better_supabase"."people" x
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant;
      update "better_supabase"."people" x set "name" = case when save_person.attrs ? 'name' then coalesce(nullif(trim(save_person.attrs ->> 'name'), ''), x."name") else x."name" end,
        "email" = case when save_person.attrs ? 'email' then lower(nullif(trim(save_person.attrs ->> 'email'), '')) else x."email" end,
        "phone" = case when save_person.attrs ? 'phone' then nullif(trim(save_person.attrs ->> 'phone'), '') else x."phone" end,
        "title" = case when save_person.attrs ? 'title' then nullif(trim(save_person.attrs ->> 'title'), '') else x."title" end,
        "lifecycle" = case when save_person.attrs ? 'lifecycle' then coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_user_id" = case when save_person.attrs ? 'ownerId' then nullif(save_person.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
        "user_id" = case when save_person.attrs ? 'userId' then nullif(save_person.attrs ->> 'userId', '')::uuid else x."user_id" end,
        "payment_terms_days" = case when save_person.attrs ? 'paymentTermsDays' then nullif(trim(save_person.attrs ->> 'paymentTermsDays'), '')::integer else x."payment_terms_days" end,
        "credit_limit" = case when save_person.attrs ? 'creditLimit' then nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_person.attrs ? 'creditCurrency' then upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "updated_at" = now()
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant and x."merged_into" is null
      returning x."owner_user_id" into v_owner;
      if not found then
        raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status") into v_row from "better_supabase"."people" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('person.created', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('person.updated', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (save_person.tenant, v_owner, 'person', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_person_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_party_roles (
  party uuid,
  roles text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
  v_tenant uuid;
  v_name text;
  v_roles text[] := array(select distinct trim(r) from unnest(coalesce(set_party_roles.roles, '{}'::text[])) r where nullif(trim(r), '') is not null order by 1);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select 'company', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."companies" x where x."id" = set_party_roles.party and x."merged_into" is null;
  if v_kind is null then
    select 'person', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."people" x where x."id" = set_party_roles.party and x."merged_into" is null;
  end if;
  if v_kind is null then
    raise exception 'company or person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if not (v_roles <@ '{customer,supplier,funder,partner}'::text[]) then
    raise exception 'unknown party role' using errcode = '22023', hint = 'PARTY_ROLES_INVALID';
  end if;
  if v_kind = 'company' then
    update "better_supabase"."companies" x set "roles" = v_roles, "updated_at" = now()
    where x."id" = set_party_roles.party and x."roles" is distinct from v_roles;
    if found then
      perform "better_supabase".emit_event('company.updated', jsonb_build_object('organizationId', v_tenant, 'companyId', set_party_roles.party, 'name', v_name), 'companies/' || set_party_roles.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
    end if;
  elsif v_kind = 'person' then
    update "better_supabase"."people" x set "roles" = v_roles, "updated_at" = now()
    where x."id" = set_party_roles.party and x."roles" is distinct from v_roles;
    if found then
      perform "better_supabase".emit_event('person.updated', jsonb_build_object('organizationId', v_tenant, 'personId', set_party_roles.party, 'name', v_name), 'persons/' || set_party_roles.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
    end if;
  end if;
  return case v_kind
    when 'company' then (select jsonb_build_object('type', 'company', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status")) from "better_supabase"."companies" x where x."id" = set_party_roles.party)
    when 'person' then (select jsonb_build_object('type', 'person', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status")) from "better_supabase"."people" x where x."id" = set_party_roles.party)
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_supplier_status (
  party  uuid,
  status text,
  reason text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
  v_tenant uuid;
  v_name text;
  v_status text := nullif(trim(set_supplier_status.status), '');
  v_reason text := nullif(trim(set_supplier_status.reason), '');
  v_previous text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select 'company', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."companies" x where x."id" = set_supplier_status.party and x."merged_into" is null;
  if v_kind is null then
    select 'person', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."people" x where x."id" = set_supplier_status.party and x."merged_into" is null;
  end if;
  if v_kind is null then
    raise exception 'company or person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.approve_supplier'), false)) then
    raise exception 'not allowed to approve suppliers' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if v_status is not null and v_status not in ('approved', 'conditional', 'blocked') then
    raise exception 'a supplier status is approved, conditional or blocked' using errcode = '22023', hint = 'PARTY_SUPPLIER_STATUS_INVALID';
  end if;
  if length(v_reason) > 2000 then
    raise exception 'a reason has at most 2000 characters' using errcode = '22023', hint = 'PARTY_SUPPLIER_STATUS_INVALID';
  end if;
  if v_kind = 'company' then
    select x."supplier_status" into v_previous from "better_supabase"."companies" x where x."id" = set_supplier_status.party for update;
    update "better_supabase"."companies" x set "supplier_status" = v_status, "updated_at" = now()
    where x."id" = set_supplier_status.party and x."supplier_status" is distinct from v_status;
    if found then
      perform "better_supabase".emit_event('company.supplier_status_changed', jsonb_build_object('organizationId', v_tenant, 'companyId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason), 'companies/' || set_supplier_status.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'company.supplier_status_changed',
    category => 'data',
    target_type => 'company',
    record_id => set_supplier_status.party::text,
    target_label => v_name,
    summary => 'supplier status of ' || v_name || ' set to ' || coalesce(v_status, 'none'),
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'companyId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason)
  );
    end if;
  elsif v_kind = 'person' then
    select x."supplier_status" into v_previous from "better_supabase"."people" x where x."id" = set_supplier_status.party for update;
    update "better_supabase"."people" x set "supplier_status" = v_status, "updated_at" = now()
    where x."id" = set_supplier_status.party and x."supplier_status" is distinct from v_status;
    if found then
      perform "better_supabase".emit_event('person.supplier_status_changed', jsonb_build_object('organizationId', v_tenant, 'personId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason), 'persons/' || set_supplier_status.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'person.supplier_status_changed',
    category => 'data',
    target_type => 'person',
    record_id => set_supplier_status.party::text,
    target_label => v_name,
    summary => 'supplier status of ' || v_name || ' set to ' || coalesce(v_status, 'none'),
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'personId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason)
  );
    end if;
  end if;
  return case v_kind
    when 'company' then (select jsonb_build_object('type', 'company', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status")) from "better_supabase"."companies" x where x."id" = set_supplier_status.party)
    when 'person' then (select jsonb_build_object('type', 'person', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status")) from "better_supabase"."people" x where x."id" = set_supplier_status.party)
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.supplier_status_from_qualifications (
  party uuid
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_gaps jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."companies" x
  where x."id" = supplier_status_from_qualifications.party and x."merged_into" is null;
  if v_tenant is null then
    raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.read'), false)) then
    raise exception 'not allowed to read companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  v_gaps := "better_supabase"."qualification_gaps"(v_tenant, 'company', jsonb_build_object('holderId', supplier_status_from_qualifications.party::text));
  return case when exists (
    select 1 from jsonb_array_elements(v_gaps) g where g ->> 'status' in ('missing', 'expired')
  ) then 'conditional' else 'approved' end;
end;
$function$;

ALTER TABLE "better_supabase"."companies"
  ADD CONSTRAINT "companies_check" CHECK (((credit_limit >= 0) AND (num_nulls(credit_limit, credit_currency) <> 1)));

ALTER TABLE "better_supabase"."companies"
  ADD CONSTRAINT "companies_credit_currency_check" CHECK ((credit_currency ~ '^[A-Z]{3}$'::text));

ALTER TABLE "better_supabase"."companies"
  ADD CONSTRAINT "companies_payment_terms_days_check" CHECK (((payment_terms_days >= 0) AND (payment_terms_days <= 3650)));

ALTER TABLE "better_supabase"."companies"
  ADD CONSTRAINT "companies_supplier_status_check" CHECK ((supplier_status = ANY (ARRAY['approved'::text, 'conditional'::text, 'blocked'::text])));

ALTER TABLE "better_supabase"."people"
  ADD CONSTRAINT "people_check" CHECK (((credit_limit >= 0) AND (num_nulls(credit_limit, credit_currency) <> 1)));

ALTER TABLE "better_supabase"."people"
  ADD CONSTRAINT "people_credit_currency_check" CHECK ((credit_currency ~ '^[A-Z]{3}$'::text));

ALTER TABLE "better_supabase"."people"
  ADD CONSTRAINT "people_payment_terms_days_check" CHECK (((payment_terms_days >= 0) AND (payment_terms_days <= 3650)));

ALTER TABLE "better_supabase"."people"
  ADD CONSTRAINT "people_supplier_status_check" CHECK ((supplier_status = ANY (ARRAY['approved'::text, 'conditional'::text, 'blocked'::text])));

CREATE INDEX companies_roles_idx ON better_supabase.companies USING gin (roles);

CREATE INDEX companies_supplier_status_idx ON better_supabase.companies USING btree (tenant_id, supplier_status)
  WHERE (supplier_status IS NOT NULL);

CREATE INDEX people_roles_idx ON better_supabase.people USING gin (roles);

CREATE INDEX people_supplier_status_idx ON better_supabase.people USING btree (tenant_id, supplier_status)
  WHERE (supplier_status IS NOT NULL);

REVOKE ALL ON FUNCTION "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_party_roles"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_party_roles"(uuid, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_supplier_status"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_supplier_status"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."supplier_status_from_qualifications"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."supplier_status_from_qualifications"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_party_roles"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_party_roles"(uuid, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_supplier_status"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_supplier_status"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."supplier_status_from_qualifications"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."supplier_status_from_qualifications"(uuid) TO "authenticated", "service_role";
