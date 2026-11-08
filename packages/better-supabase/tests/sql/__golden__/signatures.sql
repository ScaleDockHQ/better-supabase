-- ==== alone: schema supabase/schemas/900_better_supabase_087_signatures.sql
-- better-supabase module: signatures
-- @bsb-block signatures@1 managed
-- @bsb-hash sha256:09606f5afec8bfb2c90270932b903c2de541dbd510ebf2a16303157b80c15f67
-- Simple electronic signatures on a frozen version of a record: drawn, typed or click signatures in parallel or in order, a hash that detects edits after signing, and an approval step a signer can decide.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."signature_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "content_hash" text not null,
  "signers" uuid[] not null constraint bsb_signature_requests_signers_check check (cardinality("signers") >= 1 and cardinality("signers") <= 20 and array_position("signers", null) is null),
  "sign_order" text not null default 'parallel' constraint bsb_signature_requests_sign_order_check check ("sign_order" in ('parallel', 'sequential')),
  "status" text not null default 'pending' constraint bsb_signature_requests_status_check check ("status" in ('pending', 'completed', 'declined', 'cancelled')),
  "approval_request_id" uuid,
  "message" text constraint bsb_signature_requests_message_check check ("message" is null or length("message") <= 2000),
  "meaning" text,
  "requested_by" uuid,
  "created_at" timestamptz not null default now(),
  "completed_at" timestamptz
);
-- What signing means (blocks.signatures.options.meanings), such as approved.

create index "signature_requests_subject_idx" on "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id");
create index "signature_requests_version_idx" on "better_supabase"."signature_requests" ("version_id");
create index "signature_requests_signers_idx" on "better_supabase"."signature_requests" using gin ("signers");
alter table "better_supabase"."signature_requests" enable row level security;
revoke all on "better_supabase"."signature_requests" from public, anon, authenticated;
grant select on "better_supabase"."signature_requests" to authenticated;
grant all on "better_supabase"."signature_requests" to service_role;
create policy bsb_signature_requests_read on "better_supabase"."signature_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"));

create table "better_supabase"."signatures" (
  "id" uuid primary key default gen_random_uuid(),
  "request_id" uuid not null references "better_supabase"."signature_requests" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "signer" uuid not null,
  "method" text not null constraint bsb_signatures_method_check check ("method" in ('drawn', 'typed', 'click')),
  "typed_name" text constraint bsb_signatures_typed_name_check check ("typed_name" is null or length("typed_name") >= 1 and length("typed_name") <= 200),
  "image_attachment_id" uuid,
  "signed_hash" text not null,
  "ip" text constraint bsb_signatures_ip_check check ("ip" is null or length("ip") <= 64),
  "user_agent" text constraint bsb_signatures_user_agent_check check ("user_agent" is null or length("user_agent") <= 512),
  "signed_at" timestamptz not null,
  constraint bsb_signatures_check check ("method" <> 'typed' or "typed_name" is not null),
  constraint bsb_signatures_check1 check ("method" <> 'drawn' or "image_attachment_id" is not null),
  unique ("request_id", "signer")
);
alter table "better_supabase"."signatures" enable row level security;
revoke all on "better_supabase"."signatures" from public, anon, authenticated;
grant select on "better_supabase"."signatures" to authenticated;
grant all on "better_supabase"."signatures" to service_role;
create policy bsb_signatures_read on "better_supabase"."signatures"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()));

-- Asks members to sign one version of a record. The version is frozen, so
-- retention and delete_version keep it; without one, the record's columns
-- are snapshotted first. meaning says what signing means, one of
-- blocks.signatures.options.meanings. fields: the extra columns
-- (columns your schema files add) to set.

create or replace function "better_supabase"."create_signature_request"(tenant uuid, subject_type text, subject_id text, signers uuid[], version_id uuid default null, sign_order text default 'parallel', approval_request_id uuid default null, message text default null, meaning text default null)
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
  if create_signature_request.meaning is not null and create_signature_request.meaning not in ('authored', 'reviewed', 'approved', 'released', 'acknowledged', 'agreed') then
    raise exception 'meaning must be one of authored, reviewed, approved, released, acknowledged, agreed' using errcode = '22023', hint = 'SIGNATURE_REQUEST_MEANING_UNKNOWN';
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
      where m."organization_id" = create_signature_request.tenant and m."user_id" = x
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
  insert into "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "meaning", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), create_signature_request.meaning, auth.uid())
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'meaning', v_row."meaning", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$$;
revoke execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) to authenticated, service_role;

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
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(auth.uid() = any (v_req."signers"), false) or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.read'), false) and true)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "better_supabase"."signature_verification"(v_req."id"));
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
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'meaning', q."meaning", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."signature_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signature_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signature_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signature_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."signatures" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signatures" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signatures" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signatures" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_087_signatures.sql
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

-- ==== with every module: schema supabase/schemas/900_better_supabase_087_signatures.sql
-- better-supabase module: signatures
-- @bsb-block signatures@1 managed
-- @bsb-hash sha256:65a697bc9e34dd33c95c71348c2f858020a3fbd566f450b7cc11316d6f968605
-- Simple electronic signatures on a frozen version of a record: drawn, typed or click signatures in parallel or in order, a hash that detects edits after signing, and an approval step a signer can decide.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."signature_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "content_hash" text not null,
  "signers" uuid[] not null constraint bsb_signature_requests_signers_check check (cardinality("signers") >= 1 and cardinality("signers") <= 20 and array_position("signers", null) is null),
  "sign_order" text not null default 'parallel' constraint bsb_signature_requests_sign_order_check check ("sign_order" in ('parallel', 'sequential')),
  "status" text not null default 'pending' constraint bsb_signature_requests_status_check check ("status" in ('pending', 'completed', 'declined', 'cancelled')),
  "approval_request_id" uuid,
  "message" text constraint bsb_signature_requests_message_check check ("message" is null or length("message") <= 2000),
  "meaning" text,
  "requested_by" uuid,
  "created_at" timestamptz not null default now(),
  "completed_at" timestamptz
);
-- What signing means (blocks.signatures.options.meanings), such as approved.

create index "signature_requests_subject_idx" on "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id");
create index "signature_requests_version_idx" on "better_supabase"."signature_requests" ("version_id");
create index "signature_requests_signers_idx" on "better_supabase"."signature_requests" using gin ("signers");
alter table "better_supabase"."signature_requests" enable row level security;
revoke all on "better_supabase"."signature_requests" from public, anon, authenticated;
grant select on "better_supabase"."signature_requests" to authenticated;
grant all on "better_supabase"."signature_requests" to service_role;
create policy bsb_signature_requests_read on "better_supabase"."signature_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"));

create table "better_supabase"."signatures" (
  "id" uuid primary key default gen_random_uuid(),
  "request_id" uuid not null references "better_supabase"."signature_requests" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "signer" uuid not null,
  "method" text not null constraint bsb_signatures_method_check check ("method" in ('drawn', 'typed', 'click')),
  "typed_name" text constraint bsb_signatures_typed_name_check check ("typed_name" is null or length("typed_name") >= 1 and length("typed_name") <= 200),
  "image_attachment_id" uuid,
  "signed_hash" text not null,
  "ip" text constraint bsb_signatures_ip_check check ("ip" is null or length("ip") <= 64),
  "user_agent" text constraint bsb_signatures_user_agent_check check ("user_agent" is null or length("user_agent") <= 512),
  "signed_at" timestamptz not null,
  constraint bsb_signatures_check check ("method" <> 'typed' or "typed_name" is not null),
  constraint bsb_signatures_check1 check ("method" <> 'drawn' or "image_attachment_id" is not null),
  unique ("request_id", "signer")
);
alter table "better_supabase"."signatures" enable row level security;
revoke all on "better_supabase"."signatures" from public, anon, authenticated;
grant select on "better_supabase"."signatures" to authenticated;
grant all on "better_supabase"."signatures" to service_role;
create policy bsb_signatures_read on "better_supabase"."signatures"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()));

-- Asks members to sign one version of a record. The version is frozen, so
-- retention and delete_version keep it; without one, the record's columns
-- are snapshotted first. meaning says what signing means, one of
-- blocks.signatures.options.meanings. fields: the extra columns
-- (columns your schema files add) to set.

create or replace function "better_supabase"."create_signature_request"(tenant uuid, subject_type text, subject_id text, signers uuid[], version_id uuid default null, sign_order text default 'parallel', approval_request_id uuid default null, message text default null, meaning text default null)
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
  if create_signature_request.meaning is not null and create_signature_request.meaning not in ('authored', 'reviewed', 'approved', 'released', 'acknowledged', 'agreed') then
    raise exception 'meaning must be one of authored, reviewed, approved, released, acknowledged, agreed' using errcode = '22023', hint = 'SIGNATURE_REQUEST_MEANING_UNKNOWN';
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
      where m."organization_id" = create_signature_request.tenant and m."user_id" = x
    )
  ) then
    raise exception 'every signer must be a member of the organization' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if create_signature_request.approval_request_id is not null and not exists (
    select 1 from "better_supabase"."approval_requests" a
    where a."id" = create_signature_request.approval_request_id
      and a."tenant_id" = create_signature_request.tenant
      and a."subject_type" = create_signature_request.subject_type
      and a."subject_id" = create_signature_request.subject_id
  ) then
    raise exception 'the approval request isn''t for this record' using errcode = '22023', hint = 'SIGNATURE_APPROVAL_NOT_FOUND';
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
  insert into "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "meaning", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), create_signature_request.meaning, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('signature_request.requested', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id"), 'signature-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature_request.requested',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_row."id"::text,
    summary => 'requested signatures on ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'meaning', v_row."meaning", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$$;
revoke execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) to authenticated, service_role;

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
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  if sign_signature.image_attachment_id is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = sign_signature.image_attachment_id
      and a."tenant_id" = v_req."tenant_id"
  ) then
    raise exception 'the signature image isn''t an attachment in this organization' using errcode = '22023', hint = 'SIGNATURE_IMAGE_NOT_FOUND';
  end if;
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  perform "better_supabase".emit_event('signature_request.signed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature_request.signed',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'signed ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method")
  );
  -- A signer who approves the linked request's current step decides it.
  if v_req."approval_request_id" is not null and "better_supabase"."approval_eligible"(v_req."approval_request_id") then
    perform "better_supabase"."decide_approval"(v_req."approval_request_id", 'approved', 'Signed electronically');
  end if;
  if v_count + 1 >= cardinality(v_req."signers") then
    update "better_supabase"."signature_requests" x set "status" = 'completed', "completed_at" = v_at
      where x."id" = v_req."id"
      returning * into v_req;
    perform "better_supabase".emit_event('signature_request.completed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'versionId', v_req."version_id", 'meaning', v_req."meaning"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
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
  perform "better_supabase".emit_event('signature_request.declined', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signer', v_me), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature_request.declined',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'declined to sign' || coalesce(': ' || left(decline_signature_request.reason, 200), ''),
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signer', v_me)
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  perform "better_supabase".emit_event('signature_request.cancelled', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature_request.cancelled',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'cancelled a signature request',
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id")
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(auth.uid() = any (v_req."signers"), false) or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.read'), false) and true)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "better_supabase"."signature_verification"(v_req."id"));
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
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'meaning', q."meaning", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."signature_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signature_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signature_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signature_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."signatures" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signatures" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signatures" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signatures" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.signature_requests deferrable initially deferred for each row execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"signature_request","event_prefix":"signature_request"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_087_signatures.sql
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

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_087_signatures.sql
-- better-supabase module: signatures
-- @bsb-block signatures@1 managed
-- @bsb-hash sha256:98e3e35a95b1ad0f4ee2ceb1ff718ac92c69baaa52d8b73d148441bee8f288dd
-- Simple electronic signatures on a frozen version of a record: drawn, typed or click signatures in parallel or in order, a hash that detects edits after signing, and an approval step a signer can decide.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
create table "app_private"."signature_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "content_hash" text not null,
  "signers" uuid[] not null constraint bsb_signature_requests_signers_check check (cardinality("signers") >= 1 and cardinality("signers") <= 20 and array_position("signers", null) is null),
  "sign_order" text not null default 'parallel' constraint bsb_signature_requests_sign_order_check check ("sign_order" in ('parallel', 'sequential')),
  "status" text not null default 'pending' constraint bsb_signature_requests_status_check check ("status" in ('pending', 'completed', 'declined', 'cancelled')),
  "approval_request_id" uuid,
  "message" text constraint bsb_signature_requests_message_check check ("message" is null or length("message") <= 2000),
  "meaning" text,
  "requested_by" uuid,
  "created_at" timestamptz not null default now(),
  "completed_at" timestamptz
);
-- What signing means (blocks.signatures.options.meanings), such as approved.

create index "signature_requests_subject_idx" on "app_private"."signature_requests" ("tenant_id", "subject_type", "subject_id");
create index "signature_requests_version_idx" on "app_private"."signature_requests" ("version_id");
create index "signature_requests_signers_idx" on "app_private"."signature_requests" using gin ("signers");
alter table "app_private"."signature_requests" enable row level security;
revoke all on "app_private"."signature_requests" from public, anon, authenticated;
grant select on "app_private"."signature_requests" to authenticated;
grant all on "app_private"."signature_requests" to service_role;
create policy bsb_signature_requests_read on "app_private"."signature_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"));

create table "app_private"."signatures" (
  "id" uuid primary key default gen_random_uuid(),
  "request_id" uuid not null references "app_private"."signature_requests" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "signer" uuid not null,
  "method" text not null constraint bsb_signatures_method_check check ("method" in ('drawn', 'typed', 'click')),
  "typed_name" text constraint bsb_signatures_typed_name_check check ("typed_name" is null or length("typed_name") >= 1 and length("typed_name") <= 200),
  "image_attachment_id" uuid,
  "signed_hash" text not null,
  "ip" text constraint bsb_signatures_ip_check check ("ip" is null or length("ip") <= 64),
  "user_agent" text constraint bsb_signatures_user_agent_check check ("user_agent" is null or length("user_agent") <= 512),
  "signed_at" timestamptz not null,
  constraint bsb_signatures_check check ("method" <> 'typed' or "typed_name" is not null),
  constraint bsb_signatures_check1 check ("method" <> 'drawn' or "image_attachment_id" is not null),
  unique ("request_id", "signer")
);
alter table "app_private"."signatures" enable row level security;
revoke all on "app_private"."signatures" from public, anon, authenticated;
grant select on "app_private"."signatures" to authenticated;
grant all on "app_private"."signatures" to service_role;
create policy bsb_signatures_read on "app_private"."signatures"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()));

-- Asks members to sign one version of a record. The version is frozen, so
-- retention and delete_version keep it; without one, the record's columns
-- are snapshotted first. meaning says what signing means, one of
-- blocks.signatures.options.meanings. fields: the extra columns
-- (columns your schema files add) to set.

create or replace function "app_private"."create_signature_request"(tenant uuid, subject_type text, subject_id text, signers uuid[], version_id uuid default null, sign_order text default 'parallel', approval_request_id uuid default null, message text default null, meaning text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_version uuid := create_signature_request.version_id;
  v_hash text;
  v_row "app_private"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'signatures.request'), false) and true)) then
    raise exception 'not allowed to request signatures on this record' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if create_signature_request.meaning is not null and create_signature_request.meaning not in ('authored', 'reviewed', 'approved', 'released', 'acknowledged', 'agreed') then
    raise exception 'meaning must be one of authored, reviewed, approved, released, acknowledged, agreed' using errcode = '22023', hint = 'SIGNATURE_REQUEST_MEANING_UNKNOWN';
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
      where m."organization_id" = create_signature_request.tenant and m."user_id" = x
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
  insert into "app_private"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "meaning", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), create_signature_request.meaning, auth.uid())
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'meaning', v_row."meaning", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$$;
revoke execute on function "app_private"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) from public, anon;
grant execute on function "app_private"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) to authenticated, service_role;

-- Recomputes the signed version's hash from its content and each signature's
-- hash, and reports whether the record has a newer version since.
create or replace function "app_private"."signature_verification"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."signature_requests"%rowtype;
  v_req_hash text;
  v_current text;
  v_latest uuid;
  v_latest_hash text;
  v_items jsonb;
  v_signed boolean;
begin
  select * into v_req from "app_private"."signature_requests" x where x."id" = signature_verification.request_id;
  if not found then
    return null;
  end if;
  v_req_hash := v_req."content_hash";
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
    from "better_supabase"."versions" x where x."id" = v_req."version_id";
  select x."id", x."content_hash" into v_latest, v_latest_hash
    from "better_supabase"."versions" x
    where x."subject_type" = v_req."subject_type" and x."subject_id" = v_req."subject_id"
    order by x."number" desc
    limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'signer', g."signer", 'valid', g."signed_hash" = encode(extensions.digest(g."request_id"::text || ':' || v_req_hash || ':' || g."signer"::text || ':' || g."method" || ':' || coalesce(g."typed_name", '') || ':' || coalesce(g."image_attachment_id"::text, '') || ':' || to_char(g."signed_at" at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex')) order by g."signed_at"), '[]'::jsonb)
    into v_items
    from "app_private"."signatures" g where g."request_id" = v_req."id";
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
revoke execute on function "app_private"."signature_verification"(uuid) from public, anon, authenticated;

create or replace function "app_private"."sign_signature"(request_id uuid, method text, typed_name text default null, image_attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_req "app_private"."signature_requests"%rowtype;
  v_row "app_private"."signatures"%rowtype;
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
  select * into v_req from "app_private"."signature_requests" x where x."id" = sign_signature.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  if exists (select 1 from "app_private"."signatures" g where g."request_id" = v_req."id" and g."signer" = v_me) then
    raise exception 'you already signed this request' using errcode = '23505', hint = 'SIGNATURE_ALREADY_SIGNED';
  end if;
  select count(*) into v_count from "app_private"."signatures" g where g."request_id" = v_req."id";
  if v_req."sign_order" = 'sequential' and array_position(v_req."signers", v_me) <> v_count + 1 then
    raise exception 'an earlier signer hasn''t signed yet' using errcode = '55000', hint = 'SIGNATURE_OUT_OF_ORDER';
  end if;
  if sign_signature.method = 'drawn' then
    raise exception 'a drawn signature needs the attachments module for its image' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  insert into "app_private"."signatures" ("request_id", "tenant_id", "signer", "method", "typed_name", "image_attachment_id", "signed_hash", "ip", "user_agent", "signed_at")
  values (v_req."id", v_req."tenant_id", v_me, sign_signature.method, v_typed, sign_signature.image_attachment_id,
    encode(extensions.digest(v_req."id"::text || ':' || v_req."content_hash" || ':' || v_me::text || ':' || sign_signature.method || ':' || coalesce(v_typed, '') || ':' || coalesce(sign_signature.image_attachment_id::text, '') || ':' || to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex'),
    left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64),
    left(v_headers ->> 'user-agent', 512),
    v_at)
  returning * into v_row;
  null;
  if v_count + 1 >= cardinality(v_req."signers") then
    update "app_private"."signature_requests" x set "status" = 'completed', "completed_at" = v_at
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
revoke execute on function "app_private"."sign_signature"(uuid, text, text, uuid) from public, anon;
grant execute on function "app_private"."sign_signature"(uuid, text, text, uuid) to authenticated, service_role;

-- A signer refuses; the request closes for everyone.
create or replace function "app_private"."decline_signature_request"(request_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_req "app_private"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "app_private"."signature_requests" x where x."id" = decline_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if v_me is null or not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "app_private"."signature_requests" x set "status" = 'declined', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$$;
revoke execute on function "app_private"."decline_signature_request"(uuid, text) from public, anon;
grant execute on function "app_private"."decline_signature_request"(uuid, text) to authenticated, service_role;

-- The requester, or a holder of the manage permission, withdraws a request.
create or replace function "app_private"."cancel_signature_request"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "app_private"."signature_requests" x where x."id" = cancel_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "app_private"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$$;
revoke execute on function "app_private"."cancel_signature_request"(uuid) from public, anon;
grant execute on function "app_private"."cancel_signature_request"(uuid) to authenticated, service_role;

create or replace function "app_private"."get_signature_request"(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req "app_private"."signature_requests"%rowtype;
  v_items jsonb;
begin
  select * into v_req from "app_private"."signature_requests" x where x."id" = get_signature_request.request_id;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(auth.uid() = any (v_req."signers"), false) or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.read'), false) and true)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "app_private"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "app_private"."signature_verification"(v_req."id"));
end;
$$;
revoke execute on function "app_private"."get_signature_request"(uuid) from public, anon;
grant execute on function "app_private"."get_signature_request"(uuid) to authenticated, service_role;

-- A record's requests, or with mine the requests the caller is asked to sign.
create or replace function "app_private"."list_signature_requests"(tenant uuid, subject_type text default null, subject_id text default null, status text default null, mine boolean default false, page_size integer default 50, before timestamptz default null)
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
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'meaning', q."meaning", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "app_private"."signature_requests" x
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
revoke execute on function "app_private"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "app_private"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."signature_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"))
  );
create policy bsb_tenant_scope_insert on "app_private"."signature_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."signature_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."signature_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."signatures" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "app_private"."signatures" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."signatures" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."signatures" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_087_signatures.sql
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

-- ==== api schema: schema supabase/schemas/900_better_supabase_087_signatures.sql
-- better-supabase module: signatures
-- @bsb-block signatures@1 managed
-- @bsb-hash sha256:b8bf9f6d27469cb553b88b92ccc6e3a9c8f01a2c091c7bc480b678aafa78feb6
-- Simple electronic signatures on a frozen version of a record: drawn, typed or click signatures in parallel or in order, a hash that detects edits after signing, and an approval step a signer can decide.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."signature_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "content_hash" text not null,
  "signers" uuid[] not null constraint bsb_signature_requests_signers_check check (cardinality("signers") >= 1 and cardinality("signers") <= 20 and array_position("signers", null) is null),
  "sign_order" text not null default 'parallel' constraint bsb_signature_requests_sign_order_check check ("sign_order" in ('parallel', 'sequential')),
  "status" text not null default 'pending' constraint bsb_signature_requests_status_check check ("status" in ('pending', 'completed', 'declined', 'cancelled')),
  "approval_request_id" uuid,
  "message" text constraint bsb_signature_requests_message_check check ("message" is null or length("message") <= 2000),
  "meaning" text,
  "requested_by" uuid,
  "created_at" timestamptz not null default now(),
  "completed_at" timestamptz
);
-- What signing means (blocks.signatures.options.meanings), such as approved.

create index "signature_requests_subject_idx" on "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id");
create index "signature_requests_version_idx" on "better_supabase"."signature_requests" ("version_id");
create index "signature_requests_signers_idx" on "better_supabase"."signature_requests" using gin ("signers");
alter table "better_supabase"."signature_requests" enable row level security;
revoke all on "better_supabase"."signature_requests" from public, anon, authenticated;
grant select on "better_supabase"."signature_requests" to authenticated;
grant all on "better_supabase"."signature_requests" to service_role;
create policy bsb_signature_requests_read on "better_supabase"."signature_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"));

create table "better_supabase"."signatures" (
  "id" uuid primary key default gen_random_uuid(),
  "request_id" uuid not null references "better_supabase"."signature_requests" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "signer" uuid not null,
  "method" text not null constraint bsb_signatures_method_check check ("method" in ('drawn', 'typed', 'click')),
  "typed_name" text constraint bsb_signatures_typed_name_check check ("typed_name" is null or length("typed_name") >= 1 and length("typed_name") <= 200),
  "image_attachment_id" uuid,
  "signed_hash" text not null,
  "ip" text constraint bsb_signatures_ip_check check ("ip" is null or length("ip") <= 64),
  "user_agent" text constraint bsb_signatures_user_agent_check check ("user_agent" is null or length("user_agent") <= 512),
  "signed_at" timestamptz not null,
  constraint bsb_signatures_check check ("method" <> 'typed' or "typed_name" is not null),
  constraint bsb_signatures_check1 check ("method" <> 'drawn' or "image_attachment_id" is not null),
  unique ("request_id", "signer")
);
alter table "better_supabase"."signatures" enable row level security;
revoke all on "better_supabase"."signatures" from public, anon, authenticated;
grant select on "better_supabase"."signatures" to authenticated;
grant all on "better_supabase"."signatures" to service_role;
create policy bsb_signatures_read on "better_supabase"."signatures"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()));

-- Asks members to sign one version of a record. The version is frozen, so
-- retention and delete_version keep it; without one, the record's columns
-- are snapshotted first. meaning says what signing means, one of
-- blocks.signatures.options.meanings. fields: the extra columns
-- (columns your schema files add) to set.

create or replace function "better_supabase"."create_signature_request"(tenant uuid, subject_type text, subject_id text, signers uuid[], version_id uuid default null, sign_order text default 'parallel', approval_request_id uuid default null, message text default null, meaning text default null)
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
  if create_signature_request.meaning is not null and create_signature_request.meaning not in ('authored', 'reviewed', 'approved', 'released', 'acknowledged', 'agreed') then
    raise exception 'meaning must be one of authored, reviewed, approved, released, acknowledged, agreed' using errcode = '22023', hint = 'SIGNATURE_REQUEST_MEANING_UNKNOWN';
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
      where m."organization_id" = create_signature_request.tenant and m."user_id" = x
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
  insert into "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "meaning", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), create_signature_request.meaning, auth.uid())
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'meaning', v_row."meaning", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$$;
revoke execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) to authenticated, service_role;

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
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(auth.uid() = any (v_req."signers"), false) or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.read'), false) and true)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "better_supabase"."signature_verification"(v_req."id"));
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
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'meaning', q."meaning", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."signature_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signature_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signature_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signature_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."signatures" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signatures" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signatures" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signatures" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.signatures.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_signature_request"(tenant uuid, subject_type text, subject_id text, signers uuid[], version_id uuid default null, sign_order text default 'parallel', approval_request_id uuid default null, message text default null, meaning text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_signature_request"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) from public, anon;
grant execute on function "api"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) to authenticated, service_role;

create or replace function "api"."sign_signature"(request_id uuid, method text, typed_name text default null, image_attachment_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sign_signature"($1, $2, $3, $4) $$;
revoke execute on function "api"."sign_signature"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."sign_signature"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."decline_signature_request"(request_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decline_signature_request"($1, $2) $$;
revoke execute on function "api"."decline_signature_request"(uuid, text) from public, anon;
grant execute on function "api"."decline_signature_request"(uuid, text) to authenticated, service_role;

create or replace function "api"."cancel_signature_request"(request_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_signature_request"($1) $$;
revoke execute on function "api"."cancel_signature_request"(uuid) from public, anon;
grant execute on function "api"."cancel_signature_request"(uuid) to authenticated, service_role;

create or replace function "api"."get_signature_request"(request_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_signature_request"($1) $$;
revoke execute on function "api"."get_signature_request"(uuid) from public, anon;
grant execute on function "api"."get_signature_request"(uuid) to authenticated, service_role;

create or replace function "api"."list_signature_requests"(tenant uuid, subject_type text default null, subject_id text default null, status text default null, mine boolean default false, page_size integer default 50, before timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_signature_requests"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "api"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamptz) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_087_signatures.sql
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

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_087_signatures.sql
-- better-supabase module: signatures
-- @bsb-block signatures@1 managed
-- @bsb-hash sha256:3a33408cb338b2d2952e59712e1b84e7b7b63b78fb436203d67eda1e37b7e64c
-- Simple electronic signatures on a frozen version of a record: drawn, typed or click signatures in parallel or in order, a hash that detects edits after signing, and an approval step a signer can decide.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- better_supabase.signature_requests is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."signature_requests" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."signature_requests" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."signature_requests" add column if not exists "subject_type" text;
alter table "better_supabase"."signature_requests" add column if not exists "subject_id" text;
alter table "better_supabase"."signature_requests" add column if not exists "version_id" uuid references "better_supabase"."versions" ("id") on delete restrict;
alter table "better_supabase"."signature_requests" add column if not exists "content_hash" text;
alter table "better_supabase"."signature_requests" add column if not exists "signers" uuid[] constraint bsb_signature_requests_signers_check check (cardinality("signers") >= 1 and cardinality("signers") <= 20 and array_position("signers", null) is null);
alter table "better_supabase"."signature_requests" add column if not exists "sign_order" text not null default 'parallel' constraint bsb_signature_requests_sign_order_check check ("sign_order" in ('parallel', 'sequential'));
alter table "better_supabase"."signature_requests" add column if not exists "status" text not null default 'pending' constraint bsb_signature_requests_status_check check ("status" in ('pending', 'completed', 'declined', 'cancelled'));
alter table "better_supabase"."signature_requests" add column if not exists "approval_request_id" uuid;
alter table "better_supabase"."signature_requests" add column if not exists "message" text constraint bsb_signature_requests_message_check check ("message" is null or length("message") <= 2000);
alter table "better_supabase"."signature_requests" add column if not exists "meaning" text;
alter table "better_supabase"."signature_requests" add column if not exists "requested_by" uuid;
alter table "better_supabase"."signature_requests" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."signature_requests" add column if not exists "completed_at" timestamptz;
-- What signing means (blocks.signatures.options.meanings), such as approved.
alter table "better_supabase"."signature_requests" add column if not exists "meaning" text;
create index if not exists "signature_requests_subject_idx" on "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id");
create index if not exists "signature_requests_version_idx" on "better_supabase"."signature_requests" ("version_id");
create index if not exists "signature_requests_signers_idx" on "better_supabase"."signature_requests" using gin ("signers");
alter table "better_supabase"."signature_requests" enable row level security;
grant select on "better_supabase"."signature_requests" to authenticated;
grant all on "better_supabase"."signature_requests" to service_role;
create policy bsb_signature_requests_select on "better_supabase"."signature_requests"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"));

-- better_supabase.signatures is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."signatures" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."signatures" add column if not exists "request_id" uuid references "better_supabase"."signature_requests" ("id") on delete cascade;
alter table "better_supabase"."signatures" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."signatures" add column if not exists "signer" uuid;
alter table "better_supabase"."signatures" add column if not exists "method" text constraint bsb_signatures_method_check check ("method" in ('drawn', 'typed', 'click'));
alter table "better_supabase"."signatures" add column if not exists "typed_name" text constraint bsb_signatures_typed_name_check check ("typed_name" is null or length("typed_name") >= 1 and length("typed_name") <= 200);
alter table "better_supabase"."signatures" add column if not exists "image_attachment_id" uuid;
alter table "better_supabase"."signatures" add column if not exists "signed_hash" text;
alter table "better_supabase"."signatures" add column if not exists "ip" text constraint bsb_signatures_ip_check check ("ip" is null or length("ip") <= 64);
alter table "better_supabase"."signatures" add column if not exists "user_agent" text constraint bsb_signatures_user_agent_check check ("user_agent" is null or length("user_agent") <= 512);
alter table "better_supabase"."signatures" add column if not exists "signed_at" timestamptz;
alter table "better_supabase"."signatures" enable row level security;
grant select on "better_supabase"."signatures" to authenticated;
grant all on "better_supabase"."signatures" to service_role;
create policy bsb_signatures_select on "better_supabase"."signatures"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()));

-- Asks members to sign one version of a record. The version is frozen, so
-- retention and delete_version keep it; without one, the record's columns
-- are snapshotted first. meaning says what signing means, one of
-- blocks.signatures.options.meanings. fields: the extra columns
-- (columns your schema files add) to set.

create or replace function "better_supabase"."create_signature_request"(tenant uuid, subject_type text, subject_id text, signers uuid[], version_id uuid default null, sign_order text default 'parallel', approval_request_id uuid default null, message text default null, meaning text default null)
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
  if create_signature_request.meaning is not null and create_signature_request.meaning not in ('authored', 'reviewed', 'approved', 'released', 'acknowledged', 'agreed') then
    raise exception 'meaning must be one of authored, reviewed, approved, released, acknowledged, agreed' using errcode = '22023', hint = 'SIGNATURE_REQUEST_MEANING_UNKNOWN';
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
      where m."organization_id" = create_signature_request.tenant and m."user_id" = x
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
  insert into "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "meaning", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), create_signature_request.meaning, auth.uid())
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'meaning', v_row."meaning", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$$;
revoke execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) to authenticated, service_role;

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
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(auth.uid() = any (v_req."signers"), false) or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.read'), false) and true)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "better_supabase"."signature_verification"(v_req."id"));
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
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'meaning', q."meaning", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."signature_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signature_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signature_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signature_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."signatures" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signatures" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signatures" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signatures" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_087_signatures.sql
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

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_087_signatures.sql
-- better-supabase module: signatures
-- @bsb-block signatures@1 managed
-- @bsb-hash sha256:c38a7c4f86ea69ea976535ff8df1754a765973e05d21e964add24fb841376599
-- Simple electronic signatures on a frozen version of a record: drawn, typed or click signatures in parallel or in order, a hash that detects edits after signing, and an approval step a signer can decide.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."signature_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "content_hash" text not null,
  "signers" uuid[] not null constraint bsb_signature_requests_signers_check check (cardinality("signers") >= 1 and cardinality("signers") <= 20 and array_position("signers", null) is null),
  "sign_order" text not null default 'parallel' constraint bsb_signature_requests_sign_order_check check ("sign_order" in ('parallel', 'sequential')),
  "status" text not null default 'pending' constraint bsb_signature_requests_status_check check ("status" in ('pending', 'completed', 'declined', 'cancelled')),
  "approval_request_id" uuid,
  "message" text constraint bsb_signature_requests_message_check check ("message" is null or length("message") <= 2000),
  "meaning" text,
  "requested_by" uuid,
  "created_at" timestamptz not null default now(),
  "completed_at" timestamptz
);
-- What signing means (blocks.signatures.options.meanings), such as approved.

create index "signature_requests_subject_idx" on "better_supabase"."signature_requests" ("org_id", "subject_type", "subject_id");
create index "signature_requests_version_idx" on "better_supabase"."signature_requests" ("version_id");
create index "signature_requests_signers_idx" on "better_supabase"."signature_requests" using gin ("signers");
alter table "better_supabase"."signature_requests" enable row level security;
revoke all on "better_supabase"."signature_requests" from public, anon, authenticated;
grant select on "better_supabase"."signature_requests" to authenticated;
grant all on "better_supabase"."signature_requests" to service_role;
create policy bsb_signature_requests_read on "better_supabase"."signature_requests"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"));

create table "better_supabase"."signatures" (
  "id" uuid primary key default gen_random_uuid(),
  "request_id" uuid not null references "better_supabase"."signature_requests" ("id") on delete cascade,
  "org_id" uuid not null,
  "signer" uuid not null,
  "method" text not null constraint bsb_signatures_method_check check ("method" in ('drawn', 'typed', 'click')),
  "typed_name" text constraint bsb_signatures_typed_name_check check ("typed_name" is null or length("typed_name") >= 1 and length("typed_name") <= 200),
  "image_attachment_id" uuid,
  "signed_hash" text not null,
  "ip" text constraint bsb_signatures_ip_check check ("ip" is null or length("ip") <= 64),
  "user_agent" text constraint bsb_signatures_user_agent_check check ("user_agent" is null or length("user_agent") <= 512),
  "signed_at" timestamptz not null,
  constraint bsb_signatures_check check ("method" <> 'typed' or "typed_name" is not null),
  constraint bsb_signatures_check1 check ("method" <> 'drawn' or "image_attachment_id" is not null),
  unique ("request_id", "signer")
);
alter table "better_supabase"."signatures" enable row level security;
revoke all on "better_supabase"."signatures" from public, anon, authenticated;
grant select on "better_supabase"."signatures" to authenticated;
grant all on "better_supabase"."signatures" to service_role;
create policy bsb_signatures_read on "better_supabase"."signatures"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()));

-- Asks members to sign one version of a record. The version is frozen, so
-- retention and delete_version keep it; without one, the record's columns
-- are snapshotted first. meaning says what signing means, one of
-- blocks.signatures.options.meanings. fields: the extra columns
-- (columns your schema files add) to set.

create or replace function "better_supabase"."create_signature_request"(tenant uuid, subject_type text, subject_id text, signers uuid[], version_id uuid default null, sign_order text default 'parallel', approval_request_id uuid default null, message text default null, meaning text default null)
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
  if create_signature_request.meaning is not null and create_signature_request.meaning not in ('authored', 'reviewed', 'approved', 'released', 'acknowledged', 'agreed') then
    raise exception 'meaning must be one of authored, reviewed, approved, released, acknowledged, agreed' using errcode = '22023', hint = 'SIGNATURE_REQUEST_MEANING_UNKNOWN';
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
      where m."org_id" = create_signature_request.tenant and m."user_id" = x
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
      and x."org_id" = create_signature_request.tenant
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
  insert into "better_supabase"."signature_requests" ("org_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "meaning", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), create_signature_request.meaning, auth.uid())
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'meaning', v_row."meaning", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$$;
revoke execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) to authenticated, service_role;

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
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
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
  insert into "better_supabase"."signatures" ("request_id", "org_id", "signer", "method", "typed_name", "image_attachment_id", "signed_hash", "ip", "user_agent", "signed_at")
  values (v_req."id", v_req."org_id", v_me, sign_signature.method, v_typed, sign_signature.image_attachment_id,
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
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."org_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  null;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(auth.uid() = any (v_req."signers"), false) or (coalesce(better_supabase.can('tenant', v_req."org_id", 'signatures.read'), false) and true)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."org_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "better_supabase"."signature_verification"(v_req."id"));
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
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."org_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'meaning', q."meaning", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."signature_requests" x
    where x."org_id" = list_signature_requests.tenant
      and (list_signature_requests.subject_type is null or x."subject_type" = list_signature_requests.subject_type)
      and (list_signature_requests.subject_id is null or x."subject_id" = list_signature_requests.subject_id)
      and (list_signature_requests.status is null or x."status" = list_signature_requests.status)
      and (list_signature_requests.before is null or x."created_at" < list_signature_requests.before)
      and (not list_signature_requests.mine or auth.uid() = any (x."signers"))
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."org_id", 'signatures.read'), false) and true))
    order by x."created_at" desc
    limit least(greatest(coalesce(list_signature_requests.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_signature_requests"(uuid, text, text, text, boolean, integer, timestamptz) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."signature_requests" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('signatures.read')) or (select auth.uid()) = any ("signers"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signature_requests" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signature_requests" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signature_requests" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."signatures" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('signatures.read')) or "signer" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."signatures" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."signatures" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."signatures" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_087_signatures.sql
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
