-- ==== schema supabase/schemas/900_better_supabase_146_consents.sql
-- better-supabase module: consents
-- @bsb-block consents@1 managed
-- @bsb-hash sha256:3a0505b2178b977bed6b9348e6ba1708dd3da2e0d3f9da2a91c25105153e8d00
-- Consent per record and purpose: the purposes an organization asks consent for with their lawful basis and version, each decision with who made it (the person or a representative) and its signature, form or file as evidence, withdrawals and expiry. consent_active() answers whether processing may go ahead.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."consent_purposes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."consent_purposes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."consent_purposes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."consent_purposes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."consent_purposes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."consents";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."consents";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."consents";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."consents";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."consents";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Consent per record and purpose: what an organization asks consent for, each
-- decision with who made it and its evidence, withdrawals and expiry.
create table if not exists "better_supabase"."consent_purposes" (
  "id" uuid primary key default gen_random_uuid(),
  -- Null for a system purpose every organization uses.
  "tenant_id" uuid,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_.-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 4000),
  "legal_basis" text not null default 'consent' check ("legal_basis" in ('consent', 'contract', 'legal_obligation', 'vital_interest', 'public_task', 'legitimate_interest')),
  "version" text not null default '1' check (length("version") between 1 and 40),
  "requires_signature" boolean not null default false,
  "valid_months" integer check ("valid_months" is null or "valid_months" between 1 and 1200),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "consent_purposes_key_idx" on "better_supabase"."consent_purposes" ("tenant_id", "key", "version") nulls not distinct;
alter table "better_supabase"."consent_purposes" enable row level security;
revoke all on "better_supabase"."consent_purposes" from public, anon, authenticated;
grant select on "better_supabase"."consent_purposes" to authenticated;
grant all on "better_supabase"."consent_purposes" to service_role;
drop policy if exists consent_purposes_read on "better_supabase"."consent_purposes";
create policy consent_purposes_read on "better_supabase"."consent_purposes"
  for select to authenticated
  using ("tenant_id" is null or "tenant_id" in (select better_supabase.member_workspace_ids()));
create table if not exists "better_supabase"."consents" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "purpose_id" uuid not null references "better_supabase"."consent_purposes" ("id") on delete restrict,
  "subject_type" text not null,
  "subject_id" text not null,
  "given_by" text not null default 'self' check ("given_by" in ('self', 'representative')),
  -- The contact person who decided for the record, when a representative did.
  "given_by_contact_id" uuid,
  "given_by_user_id" uuid,
  "status" text not null check ("status" in ('granted', 'refused', 'withdrawn', 'expired')),
  "scope" jsonb not null default '{}'::jsonb check (jsonb_typeof("scope") = 'object'),
  -- When the decision was made, for a refusal too.
  "granted_at" timestamptz not null default now(),
  "valid_until" timestamptz,
  "withdrawn_at" timestamptz,
  "withdrawn_reason" text check ("withdrawn_reason" is null or length("withdrawn_reason") <= 1000),
  "signature_id" uuid,
  "submission_id" uuid,
  "attachment_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  check ("given_by" <> 'representative' or "given_by_contact_id" is not null),
  check ("status" <> 'withdrawn' or "withdrawn_at" is not null)
);
-- One grant in force per record and purpose version.
create unique index if not exists "consents_granted_idx" on "better_supabase"."consents" ("subject_type", "subject_id", "purpose_id") where "status" = 'granted';
create index if not exists "consents_subject_idx" on "better_supabase"."consents" ("tenant_id", "subject_type", "subject_id", "created_at" desc);
create index if not exists "consents_purpose_idx" on "better_supabase"."consents" ("purpose_id");
create index if not exists "consents_expiry_idx" on "better_supabase"."consents" ("valid_until") where "status" = 'granted' and "valid_until" is not null;
alter table "better_supabase"."consents" enable row level security;
revoke all on "better_supabase"."consents" from public, anon, authenticated;
grant select on "better_supabase"."consents" to authenticated;
grant all on "better_supabase"."consents" to service_role;
drop policy if exists consents_read on "better_supabase"."consents";
create policy consents_read on "better_supabase"."consents"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('consents.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read')) or "given_by_user_id" = (select auth.uid()));

-- Creates or changes the purpose with key and version: what the organization
-- asks consent for, its lawful basis, whether it takes a signature and how many
-- months a consent lasts. A null tenant saves a system purpose every
-- organization uses, which takes the service role.
create or replace function "better_supabase"."save_consent_purpose"(
  tenant uuid,
  key text,
  title text,
  version text default '1',
  description text default null,
  legal_basis text default 'consent',
  requires_signature boolean default false,
  valid_months integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."consent_purposes";
  v_key text := lower(trim(save_consent_purpose.key));
  v_title text := trim(save_consent_purpose.title);
  v_version text := coalesce(nullif(trim(save_consent_purpose.version), ''), '1');
  v_description text := nullif(trim(save_consent_purpose.description), '');
  v_basis text := coalesce(save_consent_purpose.legal_basis, 'consent');
  v_signature boolean := coalesce(save_consent_purpose.requires_signature, false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_consent_purpose.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'only the service role saves a system purpose' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_consent_purpose.tenant is not null and coalesce(better_supabase.can('tenant', save_consent_purpose.tenant, 'consents.manage'), false))) then
    raise exception 'not allowed to manage consent purposes' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_.-]{0,62}$' then
    raise exception 'a purpose key is lowercase letters, digits, _, - and ., at most 63 characters' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a purpose needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if length(v_version) > 40 then
    raise exception 'a purpose version is at most 40 characters' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if length(v_description) > 4000 then
    raise exception 'a purpose description is at most 4000 characters' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_basis not in ('consent', 'contract', 'legal_obligation', 'vital_interest', 'public_task', 'legitimate_interest') then
    raise exception 'legal_basis is one of consent, contract, legal_obligation, vital_interest, public_task and legitimate_interest' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if save_consent_purpose.valid_months is not null and save_consent_purpose.valid_months not between 1 and 1200 then
    raise exception 'valid_months is between 1 and 1200' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."consent_purposes" x
  where x."tenant_id" is not distinct from save_consent_purpose.tenant
    and x."key" = v_key and x."version" = v_version
  for update;
  if found then
    if v_row."archived_at" is not null then
      raise exception 'the consent purpose is archived' using errcode = '22023', hint = 'CONSENT_PURPOSE_ARCHIVED';
    end if;
    update "better_supabase"."consent_purposes" x set
      "title" = v_title,
    "description" = v_description,
      "legal_basis" = v_basis,
      "requires_signature" = v_signature,
    "updated_at" = now(),
      "valid_months" = save_consent_purpose.valid_months
    where x."id" = v_row."id"
    returning * into v_row;
    null;
  else
    insert into "better_supabase"."consent_purposes" ("tenant_id", "key", "title", "description", "legal_basis", "version", "requires_signature", "valid_months")
    values (save_consent_purpose.tenant, v_key, v_title, v_description, v_basis, v_version, v_signature, save_consent_purpose.valid_months)
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'legalBasis', v_row."legal_basis", 'version', v_row."version", 'requiresSignature', v_row."requires_signature", 'validMonths', v_row."valid_months", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_consent_purpose"(uuid, text, text, text, text, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."save_consent_purpose"(uuid, text, text, text, text, text, boolean, integer) to authenticated, service_role;

-- Archives a purpose: no new consent can be recorded for it, and the consents
-- already given stay as they are.
create or replace function "better_supabase"."archive_consent_purpose"(purpose_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."consent_purposes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."consent_purposes" x where x."id" = archive_consent_purpose.purpose_id for update;
  if not found then
    raise exception 'no such consent purpose' using errcode = 'P0002', hint = 'CONSENT_PURPOSE_NOT_FOUND';
  end if;
  if v_row."tenant_id" is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'only the service role archives a system purpose' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.manage'), false))) then
    raise exception 'not allowed to manage consent purposes' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'legalBasis', v_row."legal_basis", 'version', v_row."version", 'requiresSignature', v_row."requires_signature", 'validMonths', v_row."valid_months", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."consent_purposes" x set
    "updated_at" = now(),
    "archived_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'legalBasis', v_row."legal_basis", 'version', v_row."version", 'requiresSignature', v_row."requires_signature", 'validMonths', v_row."valid_months", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_consent_purpose"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_consent_purpose"(uuid) to authenticated, service_role;

-- The purposes an organization asks consent for: its own and the system ones,
-- by key, the newest version first.
create or replace function "better_supabase"."list_consent_purposes"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or list_consent_purposes.tenant in (select better_supabase.member_workspace_ids())) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'legalBasis', x."legal_basis", 'version', x."version", 'requiresSignature', x."requires_signature", 'validMonths', x."valid_months", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key", x."created_at" desc, x."id"), '[]'::jsonb)
    from "better_supabase"."consent_purposes" x
    where (x."tenant_id" = list_consent_purposes.tenant or x."tenant_id" is null)
      and (coalesce(list_consent_purposes.include_archived, false) or x."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_consent_purposes"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_consent_purposes"(uuid, boolean) to authenticated, service_role;

-- Records a decision on a purpose for record subject_type/subject_id: status
-- granted or refused. A representative names the contact who decided. The
-- decision ends the grant it replaces. evidence is { signatureId,
-- submissionId, attachmentId }; a purpose that requires a signature needs
-- signatureId to grant.
create or replace function "better_supabase"."record_consent"(
  subject_type text,
  subject_id text,
  purpose_key text,
  status text,
  given_by text default 'self',
  given_by_contact_id uuid default null,
  valid_until timestamptz default null,
  scope jsonb default '{}'::jsonb,
  evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_purpose "better_supabase"."consent_purposes";
  v_row "better_supabase"."consents";
  v_given_by text := coalesce(record_consent.given_by, 'self');
  v_contact uuid := record_consent.given_by_contact_id;
  v_scope jsonb := coalesce(record_consent.scope, '{}'::jsonb);
  v_evidence jsonb := coalesce(record_consent.evidence, '{}'::jsonb);
  v_until timestamptz := record_consent.valid_until;
  v_signature uuid;
  v_submission uuid;
  v_attachment uuid;
  v_representative uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_tenant := (null::text)::uuid;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.record'), false) and coalesce("better_supabase"."can_subject"(record_consent.subject_type, record_consent.subject_id, 'read'), false))
      or false
      or false) then
    raise exception 'not allowed to record consent for this record' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.record'), false) and coalesce("better_supabase"."can_subject"(record_consent.subject_type, record_consent.subject_id, 'read'), false))) then
    v_representative := null::uuid;
    if v_representative is not null then
      v_given_by := 'representative';
      v_contact := v_representative;
    else
      v_given_by := 'self';
      v_contact := null;
    end if;
  end if;
  if record_consent.status is null or record_consent.status not in ('granted', 'refused') then
    raise exception 'status is granted or refused; withdraw_consent withdraws a consent' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_given_by not in ('self', 'representative') then
    raise exception 'given_by is self or representative' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_given_by = 'self' and v_contact is not null then
    raise exception 'only a representative''s consent names a contact' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_given_by = 'representative' then
    if v_contact is null then
      raise exception 'a representative''s consent names the contact who gave it' using errcode = '22023', hint = 'CONSENT_INVALID';
    end if;
    if not true then
      raise exception 'the contact doesn''t represent this record with authority to act' using errcode = '22023', hint = 'CONSENT_INVALID';
    end if;
  end if;
  if jsonb_typeof(v_scope) <> 'object' or jsonb_typeof(v_evidence) <> 'object' then
    raise exception 'scope and evidence are JSON objects' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select * into v_purpose from "better_supabase"."consent_purposes" x
  where x."key" = record_consent.purpose_key
    and (x."tenant_id" = v_tenant or x."tenant_id" is null)
    and x."archived_at" is null
  order by (x."tenant_id" is null), x."created_at" desc, x."id"
  limit 1;
  if not found then
    if exists (
      select 1 from "better_supabase"."consent_purposes" x
      where x."key" = record_consent.purpose_key and (x."tenant_id" = v_tenant or x."tenant_id" is null)
    ) then
      raise exception 'the consent purpose is archived' using errcode = '22023', hint = 'CONSENT_PURPOSE_ARCHIVED';
    end if;
    raise exception 'no such consent purpose' using errcode = 'P0002', hint = 'CONSENT_PURPOSE_NOT_FOUND';
  end if;
  if v_evidence ? 'signatureId' and not pg_input_is_valid(v_evidence ->> 'signatureId', 'uuid') then
    raise exception 'evidence.signatureId is not a uuid' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  v_signature := (v_evidence ->> 'signatureId')::uuid;
  if v_evidence ? 'submissionId' and not pg_input_is_valid(v_evidence ->> 'submissionId', 'uuid') then
    raise exception 'evidence.submissionId is not a uuid' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  v_submission := (v_evidence ->> 'submissionId')::uuid;
  if v_evidence ? 'attachmentId' and not pg_input_is_valid(v_evidence ->> 'attachmentId', 'uuid') then
    raise exception 'evidence.attachmentId is not a uuid' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  v_attachment := (v_evidence ->> 'attachmentId')::uuid;
  if record_consent.status = 'granted' and v_purpose."requires_signature" and v_signature is null then
    raise exception 'this purpose needs a signature to grant consent' using errcode = '22023', hint = 'CONSENT_SIGNATURE_REQUIRED';
  end if;
  if record_consent.status = 'refused' then
    v_until := null;
  elsif v_until is null and v_purpose."valid_months" is not null then
    v_until := now() + make_interval(months => v_purpose."valid_months");
  end if;
  if v_until is not null and v_until <= now() then
    raise exception 'valid_until is in the past' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_consent_record"(uuid, text, text, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::text)', v_hook::oid::regproc)
        using v_tenant, record_consent.subject_type, record_consent.subject_id, v_purpose."id", record_consent.status;
    end if;
  end;
  update "better_supabase"."consents" x set
    "status" = 'withdrawn',
    "withdrawn_at" = now(), "withdrawn_reason" = 'superseded'
  where x."subject_type" = record_consent.subject_type and x."subject_id" = record_consent.subject_id
    and x."tenant_id" = v_tenant and x."status" = 'granted'
    and x."purpose_id" in (
      select y."id" from "better_supabase"."consent_purposes" y
      where y."key" = v_purpose."key" and (y."tenant_id" = v_tenant or y."tenant_id" is null)
    );
  insert into "better_supabase"."consents" ("tenant_id", "purpose_id", "subject_type", "subject_id", "given_by", "given_by_contact_id", "given_by_user_id", "status", "scope", "valid_until", "signature_id", "submission_id", "attachment_id", "created_by")
  values (v_tenant, v_purpose."id", record_consent.subject_type, record_consent.subject_id, v_given_by, v_contact, auth.uid(), record_consent.status, v_scope, v_until, v_signature, v_submission, v_attachment, auth.uid())
  returning * into v_row;
  if record_consent.status = 'granted' then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_consent_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'purposeTitle', v_purpose."title", 'purposeVersion', v_purpose."version", 'legalBasis', v_purpose."legal_basis", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'givenBy', v_row."given_by", 'givenByContactId', v_row."given_by_contact_id", 'givenByUserId', v_row."given_by_user_id", 'status', v_row."status", 'scope', coalesce(v_row."scope", '{}'::jsonb), 'grantedAt', v_row."granted_at", 'validUntil', v_row."valid_until", 'withdrawnAt', v_row."withdrawn_at", 'withdrawnReason', v_row."withdrawn_reason", 'signatureId', v_row."signature_id", 'submissionId', v_row."submission_id", 'attachmentId', v_row."attachment_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'active', (v_row."status" = 'granted' and (v_row."valid_until" is null or v_row."valid_until" > now())));
end;
$$;
revoke execute on function "better_supabase"."record_consent"(text, text, text, text, text, uuid, timestamptz, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."record_consent"(text, text, text, text, text, uuid, timestamptz, jsonb, jsonb) to authenticated, service_role;

-- Withdraws a granted consent. The service role, members with
-- consents.record who read the record, the record's own guest, a
-- representative with authority to act and whoever recorded it may withdraw.
create or replace function "better_supabase"."withdraw_consent"(consent_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."consents";
  v_purpose "better_supabase"."consent_purposes";
  v_reason text := nullif(trim(withdraw_consent.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."consents" x where x."id" = withdraw_consent.consent_id for update;
  if not found then
    raise exception 'no such consent' using errcode = 'P0002', hint = 'CONSENT_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.record'), false) and coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false))
      or false
      or false) or coalesce(v_row."given_by_user_id" = auth.uid(), false)) then
    if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.read'), false) and coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false))
      or false
      or false
      or false) then
      raise exception 'not allowed to withdraw this consent' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
    end if;
    raise exception 'no such consent' using errcode = 'P0002', hint = 'CONSENT_NOT_FOUND';
  end if;
  if v_row."status" = 'withdrawn' then
    raise exception 'the consent is already withdrawn' using errcode = '22023', hint = 'CONSENT_ALREADY_WITHDRAWN';
  end if;
  if v_row."status" <> 'granted' then
    raise exception 'only a granted consent can be withdrawn' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_consent_withdraw"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."consents" x set
    "status" = 'withdrawn',
    "withdrawn_at" = now(),
    "withdrawn_reason" = v_reason
  where x."id" = v_row."id"
  returning * into v_row;
  select * into v_purpose from "better_supabase"."consent_purposes" x where x."id" = v_row."purpose_id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_consent_withdraw"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'purposeTitle', v_purpose."title", 'purposeVersion', v_purpose."version", 'legalBasis', v_purpose."legal_basis", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'givenBy', v_row."given_by", 'givenByContactId', v_row."given_by_contact_id", 'givenByUserId', v_row."given_by_user_id", 'status', v_row."status", 'scope', coalesce(v_row."scope", '{}'::jsonb), 'grantedAt', v_row."granted_at", 'validUntil', v_row."valid_until", 'withdrawnAt', v_row."withdrawn_at", 'withdrawnReason', v_row."withdrawn_reason", 'signatureId', v_row."signature_id", 'submissionId', v_row."submission_id", 'attachmentId', v_row."attachment_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'active', (v_row."status" = 'granted' and (v_row."valid_until" is null or v_row."valid_until" > now())));
end;
$$;
revoke execute on function "better_supabase"."withdraw_consent"(uuid, text) from public, anon;
grant execute on function "better_supabase"."withdraw_consent"(uuid, text) to authenticated, service_role;

-- Whether record subject_type/subject_id has a consent in force for the
-- current version of purpose_key: granted and not past valid_until. False for
-- a caller who can't read the record's consents.
create or replace function "better_supabase"."consent_active"(subject_type text, subject_id text, purpose_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid := (null::text)::uuid;
  v_purpose uuid;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.read'), false) and coalesce("better_supabase"."can_subject"(consent_active.subject_type, consent_active.subject_id, 'read'), false))
      or false
      or false
      or false) then
    return false;
  end if;
  select x."id" into v_purpose from "better_supabase"."consent_purposes" x
  where x."key" = consent_active.purpose_key
    and (x."tenant_id" = v_tenant or x."tenant_id" is null)
    and x."archived_at" is null
  order by (x."tenant_id" is null), x."created_at" desc, x."id"
  limit 1;
  return v_purpose is not null and exists (
    select 1 from "better_supabase"."consents" x
    where x."tenant_id" = v_tenant and x."purpose_id" = v_purpose
      and x."subject_type" = consent_active.subject_type and x."subject_id" = consent_active.subject_id
      and (x."status" = 'granted' and (x."valid_until" is null or x."valid_until" > now()))
  );
end;
$$;
revoke execute on function "better_supabase"."consent_active"(text, text, text) from public, anon;
grant execute on function "better_supabase"."consent_active"(text, text, text) to authenticated, service_role;

-- The consents of a record: the latest decision per purpose key, or with
-- include_history every decision, the newest first.
create or replace function "better_supabase"."list_consents"(subject_type text, subject_id text, include_history boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid := (null::text)::uuid;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.read'), false) and coalesce("better_supabase"."can_subject"(list_consents.subject_type, list_consents.subject_id, 'read'), false))
      or false
      or false
      or false) then
    raise exception 'not allowed to read the consents of this record' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(l.item order by l.key, l.created desc, l.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'purposeId', x."purpose_id", 'purposeKey', y."key", 'purposeTitle', y."title", 'purposeVersion', y."version", 'legalBasis', y."legal_basis", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'givenBy', x."given_by", 'givenByContactId', x."given_by_contact_id", 'givenByUserId', x."given_by_user_id", 'status', x."status", 'scope', coalesce(x."scope", '{}'::jsonb), 'grantedAt', x."granted_at", 'validUntil', x."valid_until", 'withdrawnAt', x."withdrawn_at", 'withdrawnReason', x."withdrawn_reason", 'signatureId', x."signature_id", 'submissionId', x."submission_id", 'attachmentId', x."attachment_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'active', (x."status" = 'granted' and (x."valid_until" is null or x."valid_until" > now()))) as item, y."key" as key, x."created_at" as created, x."id" as id,
        row_number() over (partition by y."key" order by x."created_at" desc, x."id" desc) as n
      from "better_supabase"."consents" x
      join "better_supabase"."consent_purposes" y on y."id" = x."purpose_id"
      where x."tenant_id" = v_tenant
        and x."subject_type" = list_consents.subject_type and x."subject_id" = list_consents.subject_id
    ) l
    where coalesce(list_consents.include_history, false) or l.n = 1
  );
end;
$$;
revoke execute on function "better_supabase"."list_consents"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_consents"(text, text, boolean) to authenticated, service_role;

-- Marks every granted consent past valid_until expired and records
-- consent.expired for each. Run it on a schedule; returns how many expired.
create or replace function "better_supabase"."expire_consents"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."consents";
  v_purpose "better_supabase"."consent_purposes";
  v_count integer := 0;
begin
  for v_row in
    update "better_supabase"."consents" x set "status" = 'expired'
    where x."status" = 'granted' and x."valid_until" <= now()
    returning x.*
  loop
    select * into v_purpose from "better_supabase"."consent_purposes" y where y."id" = v_row."purpose_id";
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_consents"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_consents"() to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."consent_purposes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."consent_purposes";
create policy bsb_tenant_scope_select on "better_supabase"."consent_purposes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" is null or "tenant_id" in (select better_supabase.member_workspace_ids()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."consent_purposes";
create policy bsb_tenant_scope_insert on "better_supabase"."consent_purposes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."consent_purposes";
create policy bsb_tenant_scope_update on "better_supabase"."consent_purposes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."consent_purposes";
create policy bsb_tenant_scope_delete on "better_supabase"."consent_purposes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."consents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."consents";
create policy bsb_tenant_scope_select on "better_supabase"."consents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('consents.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read')) or "given_by_user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."consents";
create policy bsb_tenant_scope_insert on "better_supabase"."consents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."consents";
create policy bsb_tenant_scope_update on "better_supabase"."consents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."consents";
create policy bsb_tenant_scope_delete on "better_supabase"."consents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_146_consents.sql
-- better-supabase module: consents
-- @bsb-block-data consents
-- @bsb-hash sha256:847489b2aac958461d00305ddc46b04b6f03efe6f788452507bf88a805895ea4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('consents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
