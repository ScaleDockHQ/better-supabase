-- ==== schema supabase/schemas/900_better_supabase_087_signatures.sql
-- better-supabase module: signatures
-- @bsb-block signatures@1 managed
-- @bsb-hash sha256:b1e97eebb73b03f2569576393e512406d8d7cafffa155944f67fcb3483fe53d4
-- Simple electronic signatures on a frozen version of a record: drawn, typed or click signatures in parallel or in order, a hash that detects edits after signing, and an approval step a signer can decide.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."signature_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."signatures";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."signature_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "content_hash" text not null,
  "signers" uuid[] not null check (cardinality("signers") between 1 and 20 and array_position("signers", null) is null),
  "sign_order" text not null default 'parallel' check ("sign_order" in ('parallel', 'sequential')),
  "status" text not null default 'pending' check ("status" in ('pending', 'completed', 'declined', 'cancelled')),
  "approval_request_id" uuid,
  "message" text check ("message" is null or length("message") <= 2000),
  "requested_by" uuid,
  "created_at" timestamptz not null default now(),
  "completed_at" timestamptz
);
create index if not exists "signature_requests_subject_idx" on "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id");
create index if not exists "signature_requests_version_idx" on "better_supabase"."signature_requests" ("version_id");
create index if not exists "signature_requests_signers_idx" on "better_supabase"."signature_requests" using gin ("signers");
alter table "better_supabase"."signature_requests" enable row level security;
revoke all on "better_supabase"."signature_requests" from anon, authenticated;
grant select on "better_supabase"."signature_requests" to authenticated;
grant all on "better_supabase"."signature_requests" to service_role;
drop policy if exists signature_requests_read on "better_supabase"."signature_requests";
create policy signature_requests_read on "better_supabase"."signature_requests" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"));

create table if not exists "better_supabase"."signatures" (
  "id" uuid primary key default gen_random_uuid(),
  "request_id" uuid not null references "better_supabase"."signature_requests" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "signer" uuid not null,
  "method" text not null check ("method" in ('drawn', 'typed', 'click')),
  "typed_name" text check ("typed_name" is null or length("typed_name") between 1 and 200),
  "image_attachment_id" uuid,
  "signed_hash" text not null,
  "ip" text check ("ip" is null or length("ip") <= 64),
  "user_agent" text check ("user_agent" is null or length("user_agent") <= 512),
  "signed_at" timestamptz not null,
  check ("method" <> 'typed' or "typed_name" is not null),
  check ("method" <> 'drawn' or "image_attachment_id" is not null),
  unique ("request_id", "signer")
);
alter table "better_supabase"."signatures" enable row level security;
revoke all on "better_supabase"."signatures" from anon, authenticated;
grant select on "better_supabase"."signatures" to authenticated;
grant all on "better_supabase"."signatures" to service_role;
drop policy if exists signatures_read on "better_supabase"."signatures";
create policy signatures_read on "better_supabase"."signatures" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()));

-- Asks members to sign one version of a record. The version is frozen, so
-- retention and delete_version keep it; without one, the record's columns
-- are snapshotted first. fields: the extra columns
-- (blocks.signatures.options.extraColumns) to set.
drop function if exists "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, jsonb);
create or replace function "better_supabase"."create_signature_request"(tenant uuid, subject_type text, subject_id text, signers uuid[], version_id uuid default null, sign_order text default 'parallel', approval_request_id uuid default null, message text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_version uuid := create_signature_request.version_id;
  v_hash text;
  v_row "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'signatures.request'), false) and true)) then
    raise exception 'not allowed to request signatures on this record' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if create_signature_request.sign_order not in ('parallel', 'sequential') then
    raise exception 'sign_order must be parallel or sequential' using errcode = '22023', hint = 'SIGNATURE_ORDER_INVALID';
  end if;
  if coalesce(cardinality(create_signature_request.signers), 0) not between 1 and 20
    or array_position(create_signature_request.signers, null) is not null
    or (select count(distinct x) from unnest(create_signature_request.signers) x) <> cardinality(create_signature_request.signers) then
    raise exception 'name between 1 and 20 different signers' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if exists (
    select 1 from unnest(create_signature_request.signers) x
    where not exists (
      select 1 from "better_supabase"."memberships" m
      where m."workspace_id" = create_signature_request.tenant and m."user_id" = x
    )
  ) then
    raise exception 'every signer must be a member of the organization' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if create_signature_request.approval_request_id is not null then
    raise exception 'linking an approval request needs the approvals module' using errcode = '22023', hint = 'SIGNATURE_APPROVAL_UNSUPPORTED';
  end if;
  if v_version is null then
    v_version := ("better_supabase"."snapshot_version"(create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id) ->> 'id')::uuid;
  end if;
  select x."content_hash" into v_hash
    from "better_supabase"."versions" x
    where x."id" = v_version
      and x."tenant_id" = create_signature_request.tenant
      and x."subject_type" = create_signature_request.subject_type
      and x."subject_id" = create_signature_request.subject_id;
  if v_hash is null then
    raise exception 'the version isn''t a version of this record' using errcode = '22023', hint = 'SIGNATURE_VERSION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_request"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version;
    end if;
  end;
  update "better_supabase"."versions" x set "frozen" = true where x."id" = v_version and not x."frozen";
  insert into "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), auth.uid())
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$$;
revoke execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text) to authenticated, service_role;

-- Recomputes the signed version's hash from its content and each signature's
-- hash, and reports whether the record has a newer version since.
create or replace function "better_supabase"."signature_verification"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
  v_req_hash text;
  v_current text;
  v_latest uuid;
  v_latest_hash text;
  v_items jsonb;
  v_signed boolean;
begin
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = signature_verification.request_id;
  if not found then
    return null;
  end if;
  v_req_hash := v_req."content_hash";
  select encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') into v_current
    from "better_supabase"."versions" x where x."id" = v_req."version_id";
  select x."id", x."content_hash" into v_latest, v_latest_hash
    from "better_supabase"."versions" x
    where x."subject_type" = v_req."subject_type" and x."subject_id" = v_req."subject_id"
    order by x."number" desc
    limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'signer', g."signer", 'valid', g."signed_hash" = encode(extensions.digest(g."request_id"::text || ':' || v_req_hash || ':' || g."signer"::text || ':' || g."method" || ':' || coalesce(g."typed_name", '') || ':' || coalesce(g."image_attachment_id"::text, '') || ':' || to_char(g."signed_at" at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex')) order by g."signed_at"), '[]'::jsonb)
    into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  select coalesce(bool_and((i ->> 'valid')::boolean), true) into v_signed from jsonb_array_elements(v_items) i;
  return jsonb_build_object(
    'valid', v_current is not distinct from v_req_hash and v_signed,
    'contentMatches', v_current is not distinct from v_req_hash,
    'changedSince', v_latest_hash is distinct from v_req_hash,
    'latestVersionId', v_latest,
    'signatures', v_items
  );
end;
$$;
revoke execute on function "better_supabase"."signature_verification"(uuid) from public, anon, authenticated;

create or replace function "better_supabase"."sign_signature"(request_id uuid, method text, typed_name text default null, image_attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_req "better_supabase"."signature_requests"%rowtype;
  v_row "better_supabase"."signatures"%rowtype;
  v_typed text := nullif(trim(sign_signature.typed_name), '');
  v_current text;
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to sign' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if sign_signature.method not in ('drawn', 'typed', 'click') then
    raise exception 'method must be drawn, typed or click' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'typed' and v_typed is null then
    raise exception 'a typed signature needs the typed name' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'drawn' and sign_signature.image_attachment_id is null then
    raise exception 'a drawn signature needs its image attachment' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = sign_signature.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  if exists (select 1 from "better_supabase"."signatures" g where g."request_id" = v_req."id" and g."signer" = v_me) then
    raise exception 'you already signed this request' using errcode = '23505', hint = 'SIGNATURE_ALREADY_SIGNED';
  end if;
  select count(*) into v_count from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  if v_req."sign_order" = 'sequential' and array_position(v_req."signers", v_me) <> v_count + 1 then
    raise exception 'an earlier signer hasn''t signed yet' using errcode = '55000', hint = 'SIGNATURE_OUT_OF_ORDER';
  end if;
  if sign_signature.method = 'drawn' then
    raise exception 'a drawn signature needs the attachments module for its image' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  select encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') into v_current
    from "better_supabase"."versions" x where x."id" = v_req."version_id";
  if v_current is distinct from v_req."content_hash" then
    raise exception 'the version to sign changed after the request was made' using errcode = '55000', hint = 'SIGNATURE_CONTENT_CHANGED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_sign"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using v_req."id", v_me, sign_signature.method;
    end if;
  end;
  insert into "better_supabase"."signatures" ("request_id", "tenant_id", "signer", "method", "typed_name", "image_attachment_id", "signed_hash", "ip", "user_agent", "signed_at")
  values (v_req."id", v_req."tenant_id", v_me, sign_signature.method, v_typed, sign_signature.image_attachment_id,
    encode(extensions.digest(v_req."id"::text || ':' || v_req."content_hash" || ':' || v_me::text || ':' || sign_signature.method || ':' || coalesce(v_typed, '') || ':' || coalesce(sign_signature.image_attachment_id::text, '') || ':' || to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex'),
    left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64),
    left(v_headers ->> 'user-agent', 512),
    v_at)
  returning * into v_row;
  null;
  if v_count + 1 >= cardinality(v_req."signers") then
    update "better_supabase"."signature_requests" x set "status" = 'completed', "completed_at" = v_at
      where x."id" = v_req."id"
      returning * into v_req;
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_sign"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_row."id", v_req."status";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'requestId', v_row."request_id", 'signer', v_row."signer", 'method', v_row."method", 'typedName', v_row."typed_name", 'imageAttachmentId', v_row."image_attachment_id", 'signedHash', v_row."signed_hash", 'ip', v_row."ip", 'userAgent', v_row."user_agent", 'signedAt', v_row."signed_at") || jsonb_build_object('requestStatus', v_req."status");
end;
$$;
revoke execute on function "better_supabase"."sign_signature"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."sign_signature"(uuid, text, text, uuid) to authenticated, service_role;

-- A signer refuses; the request closes for everyone.
create or replace function "better_supabase"."decline_signature_request"(request_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_req "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = decline_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if v_me is null or not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'declined', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$$;
revoke execute on function "better_supabase"."decline_signature_request"(uuid, text) from public, anon;
grant execute on function "better_supabase"."decline_signature_request"(uuid, text) to authenticated, service_role;

-- The requester, or a holder of the manage permission, withdraws a request.
create or replace function "better_supabase"."cancel_signature_request"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = cancel_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_req."requested_by" = auth.uid() or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_signature_request"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_signature_request"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_signature_request"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
  v_items jsonb;
begin
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = get_signature_request.request_id;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (v_req."signers") or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.read'), false) and true)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "better_supabase"."signature_verification"(v_req."id"));
end;
$$;
revoke execute on function "better_supabase"."get_signature_request"(uuid) from public, anon;
grant execute on function "better_supabase"."get_signature_request"(uuid) to authenticated, service_role;

-- A record's requests, or with mine the requests the caller is asked to sign.
create or replace function "better_supabase"."list_signature_requests"(tenant uuid, subject_type text default null, subject_id text default null, status text default null, mine boolean default false, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or list_signature_requests.mine or coalesce(better_supabase.can('tenant', list_signature_requests.tenant, 'signatures.read'), false)) then
    raise exception 'not allowed to list signature requests' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."signature_requests" x
    where x."tenant_id" = list_signature_requests.tenant
      and (list_signature_requests.subject_type is null or x."subject_type" = list_signature_requests.subject_type)
      and (list_signature_requests.subject_id is null or x."subject_id" = list_signature_requests.subject_id)
      and (list_signature_requests.status is null or x."status" = list_signature_requests.status)
      and (list_signature_requests.before is null or x."created_at" < list_signature_requests.before)
      and (not list_signature_requests.mine or auth.uid() = any (x."signers"))
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and true))
    order by x."created_at" desc
    limit least(greatest(coalesce(list_signature_requests.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
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
drop policy if exists bsb_tenant_scope on "better_supabase"."signature_requests";
create policy bsb_tenant_scope on "better_supabase"."signature_requests" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."signatures";
create policy bsb_tenant_scope on "better_supabase"."signatures" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_087_signatures.sql
-- better-supabase module: signatures
-- @bsb-block-data signatures
-- @bsb-hash sha256:60d4f60f0497e6f4c25a101c6509c7c3f2624d76a1b38ef0dd34918d9d221802
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('signatures', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
