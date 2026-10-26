SET local check_function_bodies = off;
-- Retyping memberships.role rewrites the table under an exclusive lock.
set lock_timeout = '5s';

DROP TRIGGER "memberships_clear_tenant_claim" ON "public"."memberships";

ALTER TABLE "better_supabase"."invitations"
  DROP CONSTRAINT "invitations_role_check";

ALTER TABLE "better_supabase"."organization_domains"
  DROP CONSTRAINT "organization_domains_auto_join_role_check";

ALTER TABLE "public"."memberships"
  DROP CONSTRAINT "memberships_role_check";

DROP FUNCTION "better_supabase"."role_permissions"(text);

DROP FUNCTION "better_supabase"."role_rank"(text);

ALTER TABLE "public"."memberships"
  ALTER COLUMN "role" DROP DEFAULT;

ALTER TABLE "public"."memberships"
  DROP COLUMN "tier_role";

CREATE TABLE "better_supabase"."permission_overrides" (
  "organization_id" uuid    NOT NULL,
  "role_id"         uuid    NOT NULL,
  "permission_id"   uuid    NOT NULL,
  "granted"         boolean NOT NULL,
  CONSTRAINT "permission_overrides_pkey" PRIMARY KEY (organization_id, role_id, permission_id)
);

ALTER TABLE "better_supabase"."permission_overrides"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."permissions" (
  "id"  uuid NOT NULL DEFAULT gen_random_uuid(),
  "key" text NOT NULL,
  CONSTRAINT "permissions_key_key" UNIQUE (key),
  CONSTRAINT "permissions_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."permissions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."platform_invitations" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "email"       text                     NOT NULL,
  "role"        text                     NOT NULL,
  "token_hash"  text                     NOT NULL,
  "expires_at"  timestamp with time zone NOT NULL,
  "accepted_at" timestamp with time zone,
  "invited_by"  uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "accepted_by" uuid,
  "declined_at" timestamp with time zone,
  "revoked_at"  timestamp with time zone,
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "platform_invitations_pkey" PRIMARY KEY (id),
  CONSTRAINT "platform_invitations_token_hash_key" UNIQUE (token_hash)
);

ALTER TABLE "better_supabase"."platform_invitations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."platform_roles" (
  "user_id" uuid NOT NULL,
  "role_id" uuid NOT NULL,
  CONSTRAINT "platform_roles_pkey" PRIMARY KEY (user_id, role_id)
);

ALTER TABLE "better_supabase"."platform_roles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."role_permissions" (
  "role_id"       uuid NOT NULL,
  "permission_id" uuid NOT NULL,
  CONSTRAINT "role_permissions_pkey" PRIMARY KEY (role_id, permission_id)
);

ALTER TABLE "better_supabase"."role_permissions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."roles" (
  "id"    uuid NOT NULL DEFAULT gen_random_uuid(),
  "key"   text NOT NULL,
  "scope" text NOT NULL DEFAULT 'tenant'::text,
  CONSTRAINT "roles_key_key" UNIQUE (key),
  CONSTRAINT "roles_pkey" PRIMARY KEY (id),
  CONSTRAINT "roles_scope_check" CHECK ((scope = ANY (ARRAY['tenant'::text, 'platform'::text])))
);

ALTER TABLE "better_supabase"."roles"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."memberships"
  ADD COLUMN "updated_at" timestamp WITH time zone NOT NULL DEFAULT now();

ALTER TABLE "public"."memberships"
  ALTER COLUMN "role" DROP DEFAULT;

-- Hand-written: the catalog's tenant roles, then each membership's role key
-- becomes the role's id before the column turns into a uuid (a USING
-- expression can't look the id up). Permission keys and their links are in
-- the next migration.
INSERT INTO "better_supabase"."roles" ("key", "scope") VALUES
  ('owner', 'tenant'),
  ('admin', 'tenant'),
  ('member', 'tenant')
ON CONFLICT ("key") DO NOTHING;

-- A trigger that names the column blocks the type change; it comes back
-- unchanged right after.
DROP TRIGGER "bsb_organization_owner" ON "public"."memberships";

ALTER TABLE "public"."memberships" DISABLE TRIGGER USER;

UPDATE "public"."memberships" m
SET "role" = r."id"::text
FROM "better_supabase"."roles" r
WHERE r."key" = m."role";

ALTER TABLE "public"."memberships" ENABLE TRIGGER USER;

ALTER TABLE "public"."memberships"
  ALTER COLUMN "role" TYPE uuid USING "role"::uuid;

CREATE CONSTRAINT TRIGGER "bsb_organization_owner" AFTER UPDATE OF "role", "organization_id" OR DELETE ON "public"."memberships"
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION "better_supabase"."ensure_organization_owner"();

CREATE OR REPLACE FUNCTION api.can (
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."can"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.can_assign (
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."can_assign"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.can_assign_as (
  member uuid,
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."can_assign_as"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.can_user (
  member     uuid,
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."can_user"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.cap_allows (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cap_allows"($1) $function$;

CREATE OR REPLACE FUNCTION api.is_platform (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."is_platform"($1) $function$;

CREATE OR REPLACE FUNCTION api.member_can (
  member     uuid,
  tenant     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."member_can"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.member_can_while_deleting (
  member     uuid,
  tenant     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."member_can_while_deleting"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.member_permissions (
  member uuid,
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."member_permissions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.my_permissions (
  tenant uuid,
  keys   text[] DEFAULT NULL::text[]
)
  RETURNS text[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_permissions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."operation_permission"($1) $function$;

CREATE OR REPLACE FUNCTION api.permission_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."permission_claims"($1) $function$;

CREATE OR REPLACE FUNCTION api.permission_matches (
  granted text,
  wanted  text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."permission_matches"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.platform_can (
  member     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."platform_can"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.platform_can_assign (
  member uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."platform_can_assign"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.scope_permissions (
  scope text
)
  RETURNS text[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."scope_permissions"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_disabled (
  tenant uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."tenant_disabled"($1) $function$;

CREATE OR REPLACE FUNCTION api.tenant_ids_with (
  permission text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."tenant_ids_with"($1) $function$;

CREATE OR REPLACE FUNCTION api.user_disabled (
  user_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."user_disabled"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.accept_invitation (
  token text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "better_supabase"."invitations";
  pinvite "better_supabase"."platform_invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex')
  for update;
  if invite."id" is null then
  select * into pinvite
  from "better_supabase"."platform_invitations" i
  where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex')
  for update;
  if pinvite."id" is not null then
  if not (pinvite."accepted_at" is null and pinvite."declined_at" is null and pinvite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if pinvite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(pinvite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(pinvite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if pinvite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if pinvite."invited_by" is not null and not (
    coalesce(better_supabase.platform_can(pinvite."invited_by", 'platform.invite'), false)
    and better_supabase.platform_can_assign(pinvite."invited_by", pinvite."role"::text)
  ) then
    raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
  end if;
  if (select r."id" from "better_supabase"."roles" r where (r."id"::text = (pinvite."role")::text or r."key" = (pinvite."role")::text) order by (r."id"::text = (pinvite."role")::text) desc limit 1) is null then
    raise exception 'Unknown platform role %', pinvite."role" using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  insert into "better_supabase"."platform_roles" ("user_id", "role_id")
  values (me, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (pinvite."role")::text or r."key" = (pinvite."role")::text) order by (r."id"::text = (pinvite."role")::text) desc limit 1))
  on conflict do nothing;
  update "better_supabase"."platform_invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = pinvite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using pinvite."id", me;
    end if;
  end;
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', pinvite."id", 'organizationId', null, 'email', pinvite."email", 'role', pinvite."role"), 'invitations/' || pinvite."id"::text, null, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => pinvite."id"::text,
    metadata => jsonb_build_object('invitationId', pinvite."id", 'organizationId', null, 'email', pinvite."email", 'role', pinvite."role")
  );
  return null;
  end if;
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null and invite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(invite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(invite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if invite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "public"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "public"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invite."role")::text or r."key" = (invite."role")::text) order by (r."id"::text = (invite."role")::text) desc limit 1));
  update "better_supabase"."invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role"), 'invitations/' || invite."id"::text, (invite."organization_id")::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role")
  );
  perform "better_supabase".emit_event('organization.member_added', jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role"), 'organizations/' || invite."organization_id"::text, (invite."organization_id")::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role")
  );
  return invite."organization_id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accept_invitation_by_id (
  invitation_id uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "better_supabase"."invitations";
  pinvite "better_supabase"."platform_invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."id" = invitation_id
  for update;
  if invite."id" is null then
  select * into pinvite
  from "better_supabase"."platform_invitations" i
  where i."id" = invitation_id
  for update;
  if pinvite."id" is not null then
  if not (pinvite."accepted_at" is null and pinvite."declined_at" is null and pinvite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if pinvite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(pinvite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(pinvite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if pinvite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if pinvite."invited_by" is not null and not (
    coalesce(better_supabase.platform_can(pinvite."invited_by", 'platform.invite'), false)
    and better_supabase.platform_can_assign(pinvite."invited_by", pinvite."role"::text)
  ) then
    raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
  end if;
  if (select r."id" from "better_supabase"."roles" r where (r."id"::text = (pinvite."role")::text or r."key" = (pinvite."role")::text) order by (r."id"::text = (pinvite."role")::text) desc limit 1) is null then
    raise exception 'Unknown platform role %', pinvite."role" using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  insert into "better_supabase"."platform_roles" ("user_id", "role_id")
  values (me, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (pinvite."role")::text or r."key" = (pinvite."role")::text) order by (r."id"::text = (pinvite."role")::text) desc limit 1))
  on conflict do nothing;
  update "better_supabase"."platform_invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = pinvite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using pinvite."id", me;
    end if;
  end;
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', pinvite."id", 'organizationId', null, 'email', pinvite."email", 'role', pinvite."role"), 'invitations/' || pinvite."id"::text, null, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => pinvite."id"::text,
    metadata => jsonb_build_object('invitationId', pinvite."id", 'organizationId', null, 'email', pinvite."email", 'role', pinvite."role")
  );
  return null;
  end if;
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null and invite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(invite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(invite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if invite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "public"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "public"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invite."role")::text or r."key" = (invite."role")::text) order by (r."id"::text = (invite."role")::text) desc limit 1));
  update "better_supabase"."invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role"), 'invitations/' || invite."id"::text, (invite."organization_id")::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role")
  );
  perform "better_supabase".emit_event('organization.member_added', jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role"), 'organizations/' || invite."organization_id"::text, (invite."organization_id")::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role")
  );
  return invite."organization_id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.app_my_organizations()
  RETURNS TABLE (
    id           uuid,
    name         text,
    slug         text,
    role         text,
    plan         text,
    last_used_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  select o.id, o.name, o.slug, r.key, s.plan_key, m.last_used_at
  from public.memberships m
  join public.organizations o on o.id = m.organization_id
  join better_supabase.roles r on r.id = m.role
  left join public.subscriptions s on s.organization_id = o.id
  where m.user_id = (select auth.uid())
  order by o.name;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.app_organization_invitations (
  organization uuid
)
  RETURNS TABLE (
    id         uuid,
    email      text,
    role       text,
    invited_by text,
    created_at timestamp with time zone,
    expires_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.invite') then
    raise exception 'Not allowed to list invitations' using errcode = '42501';
  end if;
  return query
  select i.id, i.email, coalesce(r.key, i.role), coalesce(p.full_name, p.email), i.created_at, i.expires_at
  from better_supabase.invitations i
  left join better_supabase.roles r on r.id::text = i.role
  left join better_supabase.profiles p on p.id = i.invited_by
  where i.organization_id = organization
    and i.accepted_at is null and i.declined_at is null and i.revoked_at is null
    and i.expires_at >= now()
  order by i.created_at desc;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.app_organization_members (
  organization uuid
)
  RETURNS TABLE (
    user_id     uuid,
    role        text,
    full_name   text,
    email       text,
    avatar_url  text,
    avatar_path text,
    joined_at   timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.read') then
    raise exception 'Not allowed to list members' using errcode = '42501';
  end if;
  return query
  select m.user_id, r.key, p.full_name, coalesce(p.email, u.email::text), p.avatar_url, p.avatar_path, m.created_at
  from public.memberships m
  join better_supabase.roles r on r.id = m.role
  join auth.users u on u.id = m.user_id
  left join better_supabase.profiles p on p.id = m.user_id
  where m.organization_id = organization
  order by array_position(array['member', 'admin', 'owner'], r.key) desc nulls last, coalesce(p.full_name, u.email::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can (
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when can.scope = 'platform' then coalesce(better_supabase.platform_can(auth.uid(), can.permission), false)
    when can.scope in ('organization', 'tenant') then coalesce(better_supabase.member_can(auth.uid(), can.scope_id, can.permission), false)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_assign (
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role' or better_supabase.can_assign_as(auth.uid(), can_assign.tenant, can_assign.role)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_assign_as (
  member uuid,
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select member is not null
    and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = can_assign_as.tenant and m."user_id" = can_assign_as.member
    )
      and exists (
        select 1 from "better_supabase"."roles" r
        where r."id"::text = can_assign_as.role and r."scope"::text = 'tenant'
      )
    and not exists (
      select 1
        from (
          select r."id" as "role", can_assign_as.tenant as "organization_id"
          from "better_supabase"."roles" r
          where r."id"::text = can_assign_as.role
        ) m
        cross join "better_supabase"."permissions" p
        cross join lateral (select p."key" as key) k
        where coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    )
        and not coalesce(better_supabase.member_can(can_assign_as.member, can_assign_as.tenant, k.key), false)
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_user (
  member     uuid,
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when can_user.scope = 'platform' then better_supabase.platform_can(can_user.member, can_user.permission)
    when can_user.scope in ('organization', 'tenant') then better_supabase.member_can(can_user.member, can_user.scope_id, can_user.permission)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_organization_deletion (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_deletions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = cancel_organization_deletion.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."requested_by" = auth.uid() or coalesce(better_supabase.member_can_while_deleting(auth.uid(), cancel_organization_deletion.tenant, 'organization.delete'), false)) then
    raise exception 'You may not cancel this deletion' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  update "better_supabase"."organization_deletions" x set "cancelled_at" = now()
  where x."organization_id" = v_row."organization_id"
  returning * into v_row;
  
  perform "better_supabase".emit_event('organization.deletion_cancelled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_after"), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'organization.deletion_cancelled',
    category => 'data',
    target_type => 'organization',
    record_id => v_row."organization_id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_after")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cap_allows (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when jwt is null then true
    when jsonb_typeof(cap) = 'array'
      and not exists (
        select 1 from jsonb_array_elements_text(cap) c(key)
        where better_supabase.permission_matches(c.key, cap_allows.permission)
      ) then false
    when coalesce(jwt ->> 'client_id', '') = ''
      and (jwt -> 'act' is null
        or (jsonb_typeof(jwt -> 'act') = 'object'
          and jwt -> 'act' ->> 'kind' in ('support', 'impersonation'))) then true
    else exists (
      select 1
      from unnest(case jsonb_typeof(jwt -> 'scope')
          when 'string' then regexp_split_to_array(btrim(jwt ->> 'scope'), '\s+')
          when 'array' then array(select jsonb_array_elements_text(jwt -> 'scope'))
          else '{}'::text[]
        end) s(scope)
      cross join lateral unnest(better_supabase.scope_permissions(s.scope)) k(key)
      where s.scope <> ''
        and better_supabase.permission_matches(k.key, cap_allows.permission)
    )
  end
  from (select auth.jwt() as jwt) as token
  cross join lateral (
    select coalesce(jwt -> 'bsb_permission_cap', jwt -> 'bs_permission_cap') as cap
  ) as capped
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clear_tenant_claim()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update auth.users u
  set raw_app_meta_data = u.raw_app_meta_data - 'tenant_id'
  where u.id = old."user_id"
    and u.raw_app_meta_data ->> 'tenant_id' = old."organization_id"::text;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_invite_code (
  code       text,
  max_uses   integer                  DEFAULT 1,
  expires_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  tenant     uuid                     DEFAULT NULL::uuid,
  role       text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invite_codes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('waitlist.manage'), false))) or (create_invite_code.tenant is not null and coalesce(better_supabase.can('tenant', create_invite_code.tenant, 'members.invite'), false))) then
    raise exception 'You may not create this invite code' using errcode = '42501', hint = 'WAITLIST_FORBIDDEN';
  end if;
  if length(trim(create_invite_code.code)) < 8 then
    raise exception 'Invite codes need at least 8 characters' using errcode = '22023', hint = 'WAITLIST_CODE_INVALID';
  end if;
  if create_invite_code.role is not null and not (create_invite_code.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'An invite code can''t grant role %', create_invite_code.role using errcode = '22023', hint = 'WAITLIST_ROLE_INVALID';
  end if;
  if create_invite_code.role is not null
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('waitlist.manage'), false)))
    and not coalesce(better_supabase.can_assign(create_invite_code.tenant, create_invite_code.role), false) then
    raise exception 'You may not grant role %', create_invite_code.role using errcode = '42501', hint = 'WAITLIST_ROLE_FORBIDDEN';
  end if;
  insert into "better_supabase"."invite_codes" ("code_hash", "prefix", "max_uses", "expires_at", "organization_id", "role")
  values (
    encode(extensions.digest(upper(trim(create_invite_code.code)), 'sha256'), 'hex'),
    upper(left(trim(create_invite_code.code), 4)),
    create_invite_code.max_uses,
    create_invite_code.expires_at,
    create_invite_code.tenant,
    create_invite_code.role
  )
  returning * into v_row;
  perform "better_supabase".emit_event('invite_code.created', jsonb_build_object('codeId', v_row."id"::text, 'organizationId', v_row."organization_id"::text, 'prefix', v_row."prefix", 'role', v_row."role"), 'invite-codes/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/waitlist');
  perform better_supabase.audit_event(
    event_type => 'invite_code.created',
    category => 'access',
    target_type => 'invite_code',
    record_id => v_row."id"::text,
    target_label => v_row."prefix",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('codeId', v_row."id"::text, 'organizationId', v_row."organization_id"::text, 'prefix', v_row."prefix", 'role', v_row."role")
  );
  return to_jsonb(v_row) - 'code_hash';
exception when unique_violation then
  raise exception 'That invite code exists' using errcode = '23505', hint = 'WAITLIST_CODE_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_organization (
  attrs jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  owner uuid := case when service then nullif(attrs ->> 'owner_id', '')::uuid else auth.uid() end;
  organization uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if owner is null then
    raise exception 'An organization needs an owner' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if better_supabase.user_disabled(owner) then
    raise exception 'The user is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  case "better_supabase"."organization_slug_problem"(attrs ->> 'slug', null)
    when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
    when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
    when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
    else null;
  end case;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_create"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, owner;
    end if;
  end;
  insert into "public"."organizations" ("name", "slug")
  select r."name", r."slug"
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  returning "id" into organization;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (organization, owner, (select r."id" from "better_supabase"."roles" r where (r."id"::text = ('owner')::text or r."key" = ('owner')::text) order by (r."id"::text = ('owner')::text) desc limit 1));
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  perform "better_supabase".emit_event('organization.created', jsonb_build_object('organizationId', organization::text, 'userId', owner, 'role', 'owner'), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
  perform better_supabase.audit_event(
    event_type => 'organization.created',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', owner, 'role', 'owner')
  );
  return organization;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.current_tenant_id()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select (select m."organization_id"::text from "public"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decline_invitation (
  token text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."invitations" i set "declined_at" = now() where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex') and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', tenant), 'invitations/' || declined_id::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)
  );
    return true;
  end if;
  update "better_supabase"."platform_invitations" i set "declined_at" = now() where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex') and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id" into declined_id;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', null), 'invitations/' || declined_id::text, null, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', null)
  );
    return true;
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decline_invitation_by_id (
  invitation_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
  invitee_email text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if invitee_email is null then
    return false;
  end if;
  update "better_supabase"."invitations" i set "declined_at" = now() where i."id" = invitation_id and lower(i."email") = invitee_email and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', tenant), 'invitations/' || declined_id::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)
  );
    return true;
  end if;
  update "better_supabase"."platform_invitations" i set "declined_at" = now() where i."id" = invitation_id and lower(i."email") = invitee_email and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id" into declined_id;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', null), 'invitations/' || declined_id::text, null, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', null)
  );
    return true;
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.disable_service_principal (
  principal  uuid,
  created_by uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."service_principals";
begin
  select * into v_row from "better_supabase"."service_principals" p where p."id" = disable_service_principal.principal and p."disabled_at" is null for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if disable_service_principal.created_by is not null and not (
    coalesce(better_supabase.member_can(disable_service_principal.created_by, v_row."tenant_id", 'service_principals.manage'), false)
    and coalesce(better_supabase.can_assign_as(disable_service_principal.created_by, v_row."tenant_id", v_row."role"), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  update "better_supabase"."service_principals" set "disabled_at" = now(), "is_default" = false where "id" = v_row."id";
  delete from "public"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."id";
  perform "better_supabase".emit_event('service_principal.disabled', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id"), 'service-principals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/service-accounts');
  perform better_supabase.audit_event(
    event_type => 'service_principal.disabled',
    category => 'access',
    target_type => 'service_principal',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id"),
    actor_id => coalesce(disable_service_principal.created_by, auth.uid())
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.end_access (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
declare
  v_row "better_supabase"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."access_requests" r where r."id" = end_access.request_id for update;
  if not found then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "public"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."previous_role")::text or r."key" = (v_row."previous_role")::text) order by (r."id"::text = (v_row."previous_role")::text) desc limit 1)
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
  update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('access.ended', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'reason', 'revoked'), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.ended',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'reason', 'revoked')
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ensure_organization_owner()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- The row lock serializes concurrent demotions and leaves, so two
  -- transactions can't each remove a different last owner.
  perform 1 from "public"."organizations" o where o."id" = old."organization_id" for update;
  if found and not exists (
      select 1 from "public"."memberships" m where m."organization_id" = old."organization_id" and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = 'owner'
    ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expire_access_grants (
  max_grants integer DEFAULT 200
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."access_requests" r
    where r."granted_at" is not null and r."ended_at" is null and r."expires_at" <= now()
    order by r."expires_at"
    limit greatest(coalesce(expire_access_grants.max_grants, 200), 1)
    for update skip locked
  loop
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
      and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = v_row."role"
  ) then
    if v_row."previous_role" is null then
      delete from "public"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    else
      update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."previous_role")::text or r."key" = (v_row."previous_role")::text) order by (r."id"::text = (v_row."previous_role")::text) desc limit 1)
      where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
    end if;
  end if;
    update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
    perform "better_supabase".emit_event('access.ended', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'reason', 'expired'), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.ended',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'reason', 'expired')
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_shared_ai_chat (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_subject text;
  v_tenant text;
  v_leaf text;
  v_chat_id uuid;
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select l."subject_id", l."tenant_id"::text, l."leaf_id"
    into v_subject, v_tenant, v_leaf
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(get_shared_ai_chat.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'ai-chat'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses");
  if not found or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_chat_id := v_subject::uuid;
  -- The chat must still live in the tenant the link was created in.
  if not exists (select 1 from "better_supabase".ai_chats where id = v_chat_id and organization_id::text = v_tenant) then
    return null;
  end if;
  return jsonb_build_object(
    'chat', (select jsonb_build_object('id', id, 'title', title, 'model', model, 'created_at', created_at) from "better_supabase".ai_chats where id = v_chat_id),
    'leaf_id', v_leaf,
    'messages', "better_supabase"."ai_message_path_of"(v_chat_id, v_leaf, false)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.grant_access_request (
  request_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_previous text;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = grant_access_request.request_id for update;
  if not found or v_row."granted_at" is not null then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role") into v_previous from "public"."memberships" m
  where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."role")::text or r."key" = (v_row."role")::text) order by (r."id"::text = (v_row."role")::text) desc limit 1)
    where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
  else
    insert into "public"."memberships" ("organization_id", "user_id", "role")
    values (v_row."tenant_id", v_row."user_id", (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."role")::text or r."key" = (v_row."role")::text) order by (r."id"::text = (v_row."role")::text) desc limit 1));
  end if;
  update "better_supabase"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access.request_approved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.request_approved',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.has_organization_role (
  organization uuid,
  roles        text[] DEFAULT NULL::text[]
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1
    from "public"."memberships" m
    where m."organization_id" = has_organization_role.organization
      and m."user_id" = auth.uid()
      and (has_organization_role.roles is null or (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."organization_id")
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invitation_preview (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  preview jsonb;
  invitation uuid;
begin
  select jsonb_build_object(
    'status', case
    when i."accepted_at" is not null then 'accepted'
    when i."declined_at" is not null then 'declined'
    when i."revoked_at" is not null then 'revoked'
    when i."expires_at" < now() then 'expired'
    else 'pending'
  end,
    'email', i."email",
    'role', i."role",
    'tenant', i."organization_id",
    'expires_at', i."expires_at",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = i."organization_id"),
    'prefill', '{}'::jsonb
  ), i."id"
  into preview, invitation
  from "better_supabase"."invitations" i
  where i."token_hash" = encode(extensions.digest(invitation_preview.token, 'sha256'), 'hex');
  if preview is null then
    select jsonb_build_object(
    'status', case
    when i."accepted_at" is not null then 'accepted'
    when i."declined_at" is not null then 'declined'
    when i."revoked_at" is not null then 'revoked'
    when i."expires_at" < now() then 'expired'
    else 'pending'
  end,
    'email', i."email",
    'role', i."role",
    'tenant', null,
    'expires_at', i."expires_at",
    'organization', null,
    'prefill', '{}'::jsonb
  ), i."id"
    into preview, invitation
    from "better_supabase"."platform_invitations" i
    where i."token_hash" = encode(extensions.digest(invitation_preview.token, 'sha256'), 'hex');
  end if;
  if preview is not null then
    preview := preview || "better_supabase"."invitation_extra"(invitation);
  end if;
  return preview;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invite_member (
  tenant        uuid,
  invitee_email text,
  invitee_role  text,
  valid_for     interval DEFAULT '7 days'::interval,
  prefill       jsonb    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  created "better_supabase"."invitations";
  platform_created "better_supabase"."platform_invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  if tenant is null then
    if not service and not (select coalesce(better_supabase.is_platform('platform.invite'), false)) then
      raise exception 'Not allowed to invite platform users' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
    end if;
    if (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'platform' order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
      raise exception 'Unknown platform role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
    end if;
    if not service and not better_supabase.platform_can_assign(auth.uid(), ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'platform' order by (r."id"::text = (invitee_role)::text) desc limit 1))::text) then
      raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_invitation_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tenant, invitee_email, invitee_role;
    end if;
  end;
    delete from "better_supabase"."platform_invitations" i
    where lower(i."email") = lower(btrim(invitee_email)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
    insert into "better_supabase"."platform_invitations" ("email", "role", "token_hash", "invited_by", "expires_at")
    values (lower(btrim(invitee_email)), (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'platform' order by (r."id"::text = (invitee_role)::text) desc limit 1), encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
    returning * into platform_created;
    perform "better_supabase".emit_event('invitation.created', jsonb_build_object('invitationId', platform_created."id", 'organizationId', null, 'email', platform_created."email", 'role', platform_created."role"), 'invitations/' || platform_created."id"::text, null, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.created',
    category => 'membership',
    target_type => 'invitation',
    record_id => platform_created."id"::text,
    metadata => jsonb_build_object('invitationId', platform_created."id", 'organizationId', null, 'email', platform_created."email", 'role', platform_created."role")
  );
    return (jsonb_build_object(
    'id', platform_created."id",
    'tenant', null,
    'email', platform_created."email",
    'role', platform_created."role",
    'expires_at', platform_created."expires_at",
    'created_at', platform_created."created_at",
    'invited_by', platform_created."invited_by",
    'organization', null,
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = platform_created."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(platform_created."id"));
  end if;
  invitee_role := coalesce(invitee_role, 'member');
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "public"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'tenant' order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and not better_supabase.can_assign(tenant, ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'tenant' order by (r."id"::text = (invitee_role)::text) desc limit 1))::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if exists (
    select 1 from "public"."memberships" m join auth.users u on u.id = m."user_id"
    where m."organization_id" = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    raise exception '% is already a member', invitee_email using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invitation_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tenant, invitee_email, invitee_role;
    end if;
  end;
  delete from "better_supabase"."invitations" i
  where i."organization_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  insert into "better_supabase"."invitations" ("organization_id", "email", "role", "token_hash", "invited_by", "expires_at")
  values (tenant, lower(btrim(invitee_email)), (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'tenant' order by (r."id"::text = (invitee_role)::text) desc limit 1), encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
  returning * into created;
  perform "better_supabase".emit_event('invitation.created', jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role"), 'invitations/' || created."id"::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.created',
    category => 'membership',
    target_type => 'invitation',
    record_id => created."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role")
  );
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."organization_id",
    'email', created."email",
    'role', created."role",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = created."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = created."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(created."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.is_platform (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(better_supabase.platform_can(auth.uid(), is_platform.permission), false)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_chat_shares (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select "better_supabase"."list_share_links"('ai-chat', list_ai_chat_shares.chat::text)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_can (
  member     uuid,
  tenant     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select member is not null
    and not better_supabase.user_disabled(member)
    and not better_supabase.tenant_disabled(tenant)
    and (member is distinct from auth.uid() or better_supabase.cap_allows(member_can.permission))
    and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = member_can.tenant and m."user_id" = member_can.member
        and exists (select 1 from "better_supabase"."permissions" p where p."key" = member_can.permission and coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    ))
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_can_while_deleting (
  member     uuid,
  tenant     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select member is not null
    and not better_supabase.user_disabled(member)
    and (member is distinct from auth.uid() or better_supabase.cap_allows(member_can_while_deleting.permission))
    and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = member_can_while_deleting.tenant and m."user_id" = member_can_while_deleting.member
        and exists (select 1 from "better_supabase"."permissions" p where p."key" = member_can_while_deleting.permission and coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    ))
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_organization_ids (
  roles text[] DEFAULT NULL::text[]
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  ROWS 1
  SET search_path TO ''
  AS $function$
  select m."organization_id"
  from "public"."memberships" m
  where m."user_id" = (select auth.uid())
    and (member_organization_ids.roles is null or (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = any (member_organization_ids.roles))
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."organization_id")
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_permissions (
  member uuid,
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(array_agg(p."key" order by p."key"), '{}'::text[])
    from "better_supabase"."permissions" p
    where exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = member_permissions.tenant and m."user_id" = member_permissions.member
        and coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    )
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.membership_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', 'tenant',
      'id', m."organization_id",
      'roles', jsonb_build_array((select r."key" from "better_supabase"."roles" r where r."id" = m."role"))
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "public"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id")
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_invitations()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  invitee_email text;
  result jsonb := '[]'::jsonb;
begin
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if invitee_email is null then
    return result;
  end if;
  select coalesce(jsonb_agg(x.invitation order by x.expires_at), '[]'::jsonb)
  into result
  from (
    select (jsonb_build_object(
    'id', i."id",
    'tenant', i."organization_id",
    'email', i."email",
    'role', i."role",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = i."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = i."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(i."id")) - 'token' as invitation, i."id" as id, i."expires_at" as expires_at
    from "better_supabase"."invitations" i
    where lower(i."email") = invitee_email
      and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
    union all
    select (jsonb_build_object(
    'id', i."id",
    'tenant', null,
    'email', i."email",
    'role', i."role",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', null,
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = i."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(i."id")) - 'token' as invitation, i."id" as id, i."expires_at" as expires_at
    from "better_supabase"."platform_invitations" i
    where lower(i."email") = invitee_email
      and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  ) x;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_permissions (
  tenant uuid,
  keys   text[] DEFAULT NULL::text[]
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when auth.uid() is null or my_permissions.tenant is null then '{}'::text[]
    when my_permissions.keys is not null then coalesce((
      select array_agg(distinct k order by k)
      from unnest(my_permissions.keys) as k
      where better_supabase.can('tenant', my_permissions.tenant, k)
    ), '{}'::text[])
    when better_supabase.tenant_disabled(my_permissions.tenant) then '{}'::text[]
    else coalesce((
      select array_agg(distinct p order by p)
      from unnest(better_supabase.member_permissions(auth.uid(), my_permissions.tenant)) as p
      where better_supabase.cap_allows(p)
    ), '{}'::text[])
  end
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
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'activities.manage' then 'engagements.manage'
    when 'activities.read' then 'engagements.read'
    when 'activities.write' then 'engagements.write'
    when 'agents.create' then 'ai.create'
    when 'agents.moderate' then 'ai.moderate'
    when 'agents.publish' then 'ai.share'
    when 'agents.read' then 'ai.read'
    when 'ai-chat.admin' then 'ai_chat.admin'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai.admin'
    when 'ai-files.upload' then 'ai.create'
    when 'ai-keys.manage' then 'ai.admin'
    when 'ai-keys.use' then 'ai.create'
    when 'ai-schedules.create' then 'ai.create'
    when 'ai-schedules.manage' then 'ai.admin'
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
    when 'automations.admin' then 'rules.admin'
    when 'automations.edit' then 'rules.edit'
    when 'automations.publish' then 'rules.publish'
    when 'automations.read' then 'rules.read'
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
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.acknowledge' then 'controls.acknowledge'
    when 'compliance.collect' then 'controls.collect'
    when 'compliance.manage' then 'controls.manage'
    when 'compliance.read' then 'controls.read'
    when 'connectors.manage' then 'ai.admin'
    when 'connectors.read' then 'ai.read'
    when 'connectors.use' then 'ai.create'
    when 'contacts.manage' then 'parties.manage'
    when 'contacts.read' then 'parties.read'
    when 'contacts.write' then 'parties.write'
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
    when 'custom-fields.sensitive' then 'custom_fields.sensitive.read'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'organization.export'
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
    when 'employees.viewSensitive' then 'employees.view_sensitive'
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
    when 'field-history.read' then 'history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'goals.manage' then 'targets.manage'
    when 'goals.read' then 'targets.read'
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
    when 'knowledge.manage' then 'ai.admin'
    when 'knowledge.read' then 'ai.read'
    when 'knowledge.write' then 'ai.create'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'mail-sync.connect' then 'mail.connect'
    when 'mail-sync.manage' then 'mail.manage'
    when 'mail-sync.read' then 'mail.read'
    when 'mail-sync.send' then 'mail.send'
    when 'memory.manage' then 'ai.admin'
    when 'memory.read' then 'ai.read'
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
    when 'numbering.assign' then 'number_sequences.assign'
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
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
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
    when 'saved-views.read' then 'views.read'
    when 'saved-views.share' then 'views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.edit' then 'segments.edit'
    when 'segments.read' then 'segments.read'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_principals.manage'
    when 'service-accounts.read' then 'service_principals.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'work_items.manage'
    when 'tasks.read' then 'work_items.read'
    when 'tasks.write' then 'work_items.write'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
    when 'timeline.read' then 'activity.read'
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
    when 'waitlist.invite' then 'members.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow.admin'
    when 'workflow-editor.edit' then 'workflow.edit'
    when 'workflow-editor.publish' then 'workflow.publish'
    when 'workflow-editor.read' then 'workflow.read'
    when 'workflow-editor.run' then 'workflow.run'
    when 'workflows.admin' then 'workflow.admin'
    when 'workflows.read' then 'workflow.read'
    when 'workflows.run' then 'workflow.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_member_role (
  organization uuid,
  member       uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role") from "public"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_member_roles (
  organization uuid,
  member       uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select array[(select r."key" from "better_supabase"."roles" r where r."id" = m."role")]::text[]
  from "public"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member
$function$;

CREATE OR REPLACE FUNCTION better_supabase.permission_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(m."organization_id"::text, to_jsonb(better_supabase.member_permissions(m."user_id", m."organization_id"))), '{}'::jsonb)
  from "public"."memberships" m
  where m."user_id" = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id")
$function$;

CREATE OR REPLACE FUNCTION better_supabase.permission_matches (
  granted text,
  wanted  text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select granted = '*' or granted = wanted
    or (right(granted, 2) = '.*' and starts_with(wanted, left(granted, -1)))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.platform_can (
  member     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select member is not null
    and (platform_can.member is distinct from auth.uid() or auth.jwt() -> 'act' is null)
    and not better_supabase.user_disabled(member)
    and (member is distinct from auth.uid() or better_supabase.cap_allows(platform_can.permission))
    and (exists (
    select 1
    from "better_supabase"."platform_roles" a
    join "better_supabase"."role_permissions" rp on rp."role_id" = a."role_id"
    join "better_supabase"."permissions" p on p."id" = rp."permission_id"
    where a."user_id" = platform_can.member
      and p."key" = platform_can.permission
  ) or (platform_can.member = auth.uid() and exists (
    select 1
    from jsonb_array_elements_text(
      case when jsonb_typeof(coalesce(auth.jwt() -> 'platform_permissions', auth.jwt() -> 'app_metadata' -> 'platform_permissions')) = 'array'
        then coalesce(auth.jwt() -> 'platform_permissions', auth.jwt() -> 'app_metadata' -> 'platform_permissions')
        else '[]'::jsonb end
    ) g(key)
    where better_supabase.permission_matches(g.key, platform_can.permission)
  )))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.platform_can_assign (
  member uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select member is not null
    and exists (
      select 1 from "better_supabase"."roles" r
      where r."id"::text = platform_can_assign.role and r."scope"::text = 'platform'
    )
    and not exists (
      select 1
      from "better_supabase"."role_permissions" rp
      join "better_supabase"."permissions" p on p."id" = rp."permission_id"
      where rp."role_id"::text = platform_can_assign.role
        and not coalesce(better_supabase.platform_can(platform_can_assign.member, p."key"), false)
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.platform_invitations_readable()
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (select coalesce(better_supabase.is_platform('platform.invite'), false));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.redeem_for (
  code   text,
  member uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_code "better_supabase"."invite_codes";
  v_role text;
  v_added boolean;
begin
  select * into v_code from "better_supabase"."invite_codes" x
  where x."code_hash" = encode(extensions.digest(upper(trim(redeem_for.code)), 'sha256'), 'hex')
  for update;
  if v_code."id" is null or not (v_code."revoked_at" is null
      and (v_code."expires_at" is null or v_code."expires_at" > now())
      and (v_code."max_uses" is null or v_code."uses" < v_code."max_uses")) then
    raise exception 'This invite code is not valid' using errcode = '22023', hint = 'WAITLIST_CODE_INVALID';
  end if;
  insert into "better_supabase"."invite_code_redemptions" ("code_id", "user_id") values (v_code."id", redeem_for.member)
  on conflict do nothing;
  if not found then
    raise exception 'You already used this invite code' using errcode = '23505', hint = 'WAITLIST_CODE_USED';
  end if;
  update "better_supabase"."invite_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  if v_code."organization_id" is not null then
    v_role := coalesce(v_code."role", 'member');
    insert into "public"."memberships" ("organization_id", "user_id", "role")
    values (v_code."organization_id", redeem_for.member, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_role)::text or r."key" = (v_role)::text) order by (r."id"::text = (v_role)::text) desc limit 1))
    on conflict do nothing;
    v_added := found;
    if v_added then
      perform "better_supabase".emit_event('organization.member_added', jsonb_build_object('organizationId', v_code."organization_id"::text, 'userId', redeem_for.member, 'role', v_role), 'organizations/' || v_code."organization_id"::text, (v_code."organization_id")::text, null, 'better-supabase/waitlist');
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => redeem_for.member::text,
    tenant => (v_code."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_code."organization_id"::text, 'userId', redeem_for.member, 'role', v_role)
  );
    else
      v_role := null;
    end if;
  end if;
  return jsonb_build_object('organizationId', v_code."organization_id", 'role', v_role);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_service_principal (
  principal  uuid,
  tenant     uuid,
  name       text,
  role       text,
  is_default boolean DEFAULT false,
  created_by uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if register_service_principal.created_by is not null and not (
    coalesce(better_supabase.member_can(register_service_principal.created_by, register_service_principal.tenant, 'service_principals.manage'), false)
    and coalesce(better_supabase.can_assign_as(register_service_principal.created_by, register_service_principal.tenant, register_service_principal.role), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if not exists (
    select 1 from auth.users u
    where u.id = register_service_principal.principal
      and coalesce((u.raw_app_meta_data ->> 'bsb_service_principal')::boolean, false)
      and u.banned_until > now() + interval '50 years'
  ) then
    raise exception 'The user is not a service principal: create it with createServiceAccounts().create' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_USER';
  end if;
  if not ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (register_service_principal.role)::text or r."key" = (register_service_principal.role)::text) order by (r."id"::text = (register_service_principal.role)::text) desc limit 1) is not null) then
    raise exception 'Unknown role %', register_service_principal.role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if register_service_principal.is_default then
    update "better_supabase"."service_principals" set "is_default" = false
    where "tenant_id" = register_service_principal.tenant and "is_default";
  end if;
  insert into "better_supabase"."service_principals" ("id", "tenant_id", "name", "role", "is_default", "created_by")
  values (register_service_principal.principal, register_service_principal.tenant, register_service_principal.name,
    register_service_principal.role, coalesce(register_service_principal.is_default, false), register_service_principal.created_by);
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (register_service_principal.tenant, register_service_principal.principal, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (register_service_principal.role)::text or r."key" = (register_service_principal.role)::text) order by (r."id"::text = (register_service_principal.role)::text) desc limit 1));
  perform "better_supabase".emit_event('service_principal.created', jsonb_build_object('organizationId', register_service_principal.tenant::text, 'id', register_service_principal.principal, 'name', register_service_principal.name, 'role', register_service_principal.role), 'service-principals/' || register_service_principal.principal::text, (register_service_principal.tenant)::text, null, 'better-supabase/service-accounts');
  perform better_supabase.audit_event(
    event_type => 'service_principal.created',
    category => 'access',
    target_type => 'service_principal',
    record_id => register_service_principal.principal::text,
    target_label => register_service_principal.name,
    tenant => (register_service_principal.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', register_service_principal.tenant::text, 'id', register_service_principal.principal, 'name', register_service_principal.name, 'role', register_service_principal.role),
    actor_id => coalesce(register_service_principal.created_by, auth.uid())
  );
  return jsonb_build_object('id', register_service_principal.principal, 'tenant', register_service_principal.tenant,
    'name', register_service_principal.name, 'role', register_service_principal.role,
    'isDefault', coalesce(register_service_principal.is_default, false));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_access (
  tenant   uuid,
  role     text,
  reason   text     DEFAULT NULL::text,
  duration interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_current text;
  v_duration interval;
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role") into v_current from "public"."memberships" m
  where m."organization_id" = request_access.tenant and m."user_id" = v_me;
  if not found then
    raise exception 'only members can request a role' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  elsif not coalesce(better_supabase.can('tenant', request_access.tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request a role here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if not (request_access.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'this role can''t be requested' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  if v_current = request_access.role then
    raise exception 'you already hold this role' using errcode = '22023', hint = 'ACCESS_ROLE_HELD';
  end if;
  if v_current = 'owner' then
    raise exception 'an owner can''t request another role' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  v_duration := request_access.duration;
  if v_duration is not null and v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_access.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = request_access.tenant and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request here' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_request"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using request_access.tenant, request_access.role;
    end if;
  end;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "role", "reason", "duration")
  values (request_access.tenant, v_me, request_access.role, request_access.reason, v_duration)
  returning * into v_row;
  v_approval := "better_supabase"."open_approval"(
    request_access.tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, request_access.reason,
    jsonb_build_object('role', request_access.role, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access.requested', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.requested',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resend_invitation (
  invitation_id uuid,
  valid_for     interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  updated "better_supabase"."invitations";
  platform_updated "better_supabase"."platform_invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  update "better_supabase"."invitations" i
  set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "expires_at" = now() + valid_for
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    update "better_supabase"."platform_invitations" i
    set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
      "expires_at" = now() + valid_for
    where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('platform.invite'), false)))
    returning * into platform_updated;
    if platform_updated."id" is not null then
      perform "better_supabase".emit_event('invitation.resent', jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email"), 'invitations/' || platform_updated."id"::text, null, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.resent',
    category => 'membership',
    target_type => 'invitation',
    record_id => platform_updated."id"::text,
    metadata => jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email")
  );
      return (jsonb_build_object(
    'id', platform_updated."id",
    'tenant', null,
    'email', platform_updated."email",
    'role', platform_updated."role",
    'expires_at', platform_updated."expires_at",
    'created_at', platform_updated."created_at",
    'invited_by', platform_updated."invited_by",
    'organization', null,
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = platform_updated."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(platform_updated."id"));
    end if;
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  perform "better_supabase".emit_event('invitation.resent', jsonb_build_object('invitationId', updated."id", 'organizationId', updated."organization_id"::text, 'email', updated."email"), 'invitations/' || updated."id"::text, (updated."organization_id")::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.resent',
    category => 'membership',
    target_type => 'invitation',
    record_id => updated."id"::text,
    tenant => (updated."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', updated."id", 'organizationId', updated."organization_id"::text, 'email', updated."email")
  );
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = updated."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = updated."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(updated."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_ai_chat_share (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return "better_supabase"."revoke_share_link"(revoke_ai_chat_share.id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_invitation (
  invitation_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  tenant text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."organization_id"::text into tenant;
  if found then
    perform "better_supabase".emit_event('invitation.revoked', jsonb_build_object('invitationId', invitation_id, 'organizationId', tenant), 'invitations/' || invitation_id::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.revoked',
    category => 'membership',
    target_type => 'invitation',
    record_id => invitation_id::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', invitation_id, 'organizationId', tenant)
  );
    return true;
  end if;
  update "better_supabase"."platform_invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('platform.invite'), false))) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  if found then
    perform "better_supabase".emit_event('invitation.revoked', jsonb_build_object('invitationId', invitation_id, 'organizationId', null), 'invitations/' || invitation_id::text, null, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.revoked',
    category => 'membership',
    target_type => 'invitation',
    record_id => invitation_id::text,
    metadata => jsonb_build_object('invitationId', invitation_id, 'organizationId', null)
  );
    return true;
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.scim_group_role (
  display_name text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select coalesce(
    (select t.role from (select null::text as name, null::text as role where false) as t(name, role) where t.name = lower(scim_group_role.display_name)),
    case when lower(scim_group_role.display_name) = any (array['admin', 'member', 'viewer']::text[]) then lower(scim_group_role.display_name) end
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.scim_sync_member (
  scim_user uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."scim_users";
  v_tenant uuid;
  v_user uuid;
  v_current text;
  v_role text;
begin
  select * into v_row from "better_supabase"."scim_users" x where x."id" = scim_sync_member.scim_user;
  if v_row."user_id" is null then
    return;
  end if;
  v_tenant := v_row."organization_id";
  v_user := v_row."user_id";
  select (select r."key" from "better_supabase"."roles" r where r."id" = mm."role") into v_current from "public"."memberships" mm where mm."organization_id" = v_tenant and mm."user_id" = v_user;
  if v_current = 'owner' then
    return;
  end if;
  if not v_row."active" then
    delete from "public"."memberships" mm where mm."organization_id" = v_tenant and mm."user_id" = v_user;
    if found then
      perform "better_supabase".emit_event('organization.member_removed', jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user), 'organizations/' || v_tenant::text, (v_tenant)::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'organization.member_removed',
    category => 'membership',
    target_type => 'user',
    record_id => v_user::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user)
  );
    end if;
    return;
  end if;
  select coalesce((
    select sg."role" from "better_supabase"."scim_group_members" sm join "better_supabase"."scim_groups" sg on sg."id" = sm."group_id"
    where sm."scim_user_id" = v_row."id" and sg."role" is not null
    order by array_position(array['admin', 'member', 'viewer']::text[], sg."role")
    limit 1
  ), 'member') into v_role;
  if v_current is null then
    insert into "public"."memberships" ("organization_id", "user_id", "role") values (v_tenant, v_user, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_role)::text or r."key" = (v_role)::text) order by (r."id"::text = (v_role)::text) desc limit 1));
    perform "better_supabase".emit_event('organization.member_added', jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user, 'role', v_role), 'organizations/' || v_tenant::text, (v_tenant)::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => v_user::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user, 'role', v_role)
  );
  elsif v_current is distinct from v_role then
    update "public"."memberships" mm set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_role)::text or r."key" = (v_role)::text) order by (r."id"::text = (v_role)::text) desc limit 1) where mm."organization_id" = v_tenant and mm."user_id" = v_user;
    perform "better_supabase".emit_event('organization.role_changed', jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user, 'role', v_role, 'previousRole', v_current), 'organizations/' || v_tenant::text, (v_tenant)::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'organization.role_changed',
    category => 'membership',
    target_type => 'user',
    record_id => v_user::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user, 'role', v_role, 'previousRole', v_current)
  );
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.scope_permissions (
  scope text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select array[scope]
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_notification (
  notification jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := notification ->> 'type';
  v_tenant uuid := nullif(notification ->> 'tenant', '')::uuid;
  v_actor uuid := coalesce(nullif(notification ->> 'actor', '')::uuid, auth.uid());
  v_subject_type text := notification ->> 'subject_type';
  v_subject_id text := notification ->> 'subject_id';
  v_priority text := coalesce(notification ->> 'priority', 'normal');
  v_key text := nullif(notification ->> 'key', '');
  v_activity text := coalesce(notification ->> 'activity', 'participating');
  v_channels text[] := case
    when jsonb_typeof(notification -> 'channels') = 'array'
      then array(select jsonb_array_elements_text(notification -> 'channels'))
    else array['in_app']::text[]
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;
  v_want_members uuid[];
  v_want_channels text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_type is null or btrim(v_type) = '' then
    raise exception 'A notification needs a type' using errcode = '22023', hint = 'NOTIFICATION_TYPE_REQUIRED';
  end if;
  if not (v_priority = any(array['low', 'normal', 'high', 'urgent']::text[])) then
    raise exception 'Unknown notification priority' using errcode = '22023', hint = 'NOTIFICATION_PRIORITY_UNKNOWN';
  end if;
  if v_activity not in ('participating', 'all') then
    raise exception 'activity must be participating or all' using errcode = '22023', hint = 'NOTIFICATION_ACTIVITY_UNKNOWN';
  end if;
  if notification ? 'actions' and jsonb_typeof(notification -> 'actions') <> 'null' and (
    jsonb_typeof(notification -> 'actions') <> 'array'
    or jsonb_array_length(notification -> 'actions') > 10
    or exists (
      select 1 from jsonb_array_elements(notification -> 'actions') a
      where jsonb_typeof(a) <> 'object'
        or jsonb_typeof(a -> 'key') is distinct from 'string'
        or (a ->> 'key') !~ '^[A-Za-z0-9_.:-]{1,64}$'
        or jsonb_typeof(a -> 'label') is distinct from 'string'
        or length(a ->> 'label') not between 1 and 100
        or (a ? 'operation' and jsonb_typeof(a -> 'operation') <> 'null' and (jsonb_typeof(a -> 'operation') <> 'string' or length(a ->> 'operation') not between 1 and 200))
        or (a ? 'payload' and jsonb_typeof(a -> 'payload') not in ('object', 'null'))
        or exists (select 1 from jsonb_object_keys(a) k where k not in ('key', 'label', 'operation', 'payload'))
    )
    or (select count(distinct a ->> 'key') from jsonb_array_elements(notification -> 'actions') a) <> jsonb_array_length(notification -> 'actions')
  ) then
    raise exception 'actions must be at most 10 { key, label, operation, payload } objects with unique keys' using errcode = '22023', hint = 'NOTIFICATION_ACTIONS_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    if v_tenant is null or not coalesce(better_supabase.member_can(auth.uid(), v_tenant, 'notifications.send'), false) then
      raise exception 'Not allowed to send notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
    end if;
    v_actor := auth.uid();
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_notification_send"(jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb)', v_hook::oid::regproc)
        using notification;
    end if;
  end;
  if to_regprocedure('"public"."notification_audience"(jsonb)') is not null then
    execute format('select %s($1)', to_regprocedure('"public"."notification_audience"(jsonb)')::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;
  if v_subject_type is not null and v_subject_id is not null then
    -- watchers: false sends to the named recipients only; ignore still holds.
    if coalesce((notification ->> 'watchers')::boolean, true) then
      v_recipients := v_recipients || array(
        select s."user_id" from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and (s."level" = 'all' or (v_activity = 'participating' and s."level" = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and s."level" = 'ignore' and s."user_id" = x
      )
    );
  end if;
  
  if nullif(notification ->> 'permission', '') is not null and v_tenant is null then
    raise exception 'A permission audience needs a tenant' using errcode = '22023', hint = 'NOTIFICATION_PERMISSION_NEEDS_TENANT';
  end if;
  if nullif(notification ->> 'permission', '') is not null then
    v_recipients := v_recipients || coalesce(array(
      select m."user_id"
      from "public"."memberships" m
      where m."organization_id" = v_tenant
        and coalesce(better_supabase.can_user(m."user_id", 'tenant', v_tenant, notification ->> 'permission'), false)
      
      union
      select a."user_id"
      from "better_supabase"."platform_roles" a
      where coalesce(better_supabase.platform_can(a."user_id", notification ->> 'permission'), false)
    ), '{}');
  end if;
  -- exclude: users the composer already reached (the mentioned ones, say).
  if jsonb_typeof(notification -> 'exclude') = 'array' then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))
    );
  end if;
  if v_actor is not null and not coalesce((notification ->> 'include_actor')::boolean, false) then
    v_recipients := array_remove(v_recipients, v_actor);
  end if;
  if v_tenant is not null then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where coalesce(better_supabase.member_can(x, v_tenant, 'notifications.read'), false)
    );
  end if;
  v_recipients := array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients) > 1000 then
    raise exception 'A notification reaches at most 1000 recipients' using errcode = '22023', hint = 'NOTIFICATION_TOO_MANY_RECIPIENTS';
  end if;
  select coalesce(array_agg(w.member), '{}'), coalesce(array_agg(w.channel), '{}')
  into v_want_members, v_want_channels
  from (
    select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p."enabled", case c when 'in_app' then true else false end) as enabled
      from unnest(v_recipients) x cross join unnest(v_channels) c
      left join "better_supabase"."notification_preferences" p
        on p."user_id" = x and p."channel" = c
        and (p."type" = v_type or p."type" = '*')
        and (p."organization_id" is null or p."organization_id" = v_tenant)
      order by x, c, p."organization_id" is null, p."type" = '*'
    ) w
    where w.enabled
  ) w;
  v_recipients := array(select distinct x from unnest(v_want_members) x);
  if cardinality(v_recipients) = 0 then
    return null;
  end if;

  if v_key is not null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;
  if v_event is null then
    insert into "better_supabase"."notification_events" ("type", "data", "organization_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "actions", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', nullif(notification -> 'actions', 'null'::jsonb), v_priority, v_key, auth.uid())
    on conflict do nothing
    returning "id" into v_event;
  end if;
  if v_event is null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;

  insert into "better_supabase"."notification_recipients" ("event_id", "organization_id", "user_id", "dismissed_at", "resolved_at", "created_at")
  select v_event, v_tenant, x, case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end, case when coalesce((notification ->> 'resolved')::boolean, false) then now() end, clock_timestamp()
  from unnest(v_recipients) x
  on conflict do nothing;
  insert into "better_supabase"."notification_deliveries" ("recipient_id", "organization_id", "channel", "status", "delivered_at")
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else 'pending' end, case when c = 'in_app' then now() end
  from "better_supabase"."notification_recipients" rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc."user_id"
  where rc."event_id" = v_event
  on conflict do nothing;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_notify"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_event;
    end if;
  end;
  perform "better_supabase".emit_event('notification.created', jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'recipientIds', to_jsonb(v_recipients)), 'notifications/' || v_event::text, (v_tenant)::text, 'notification.created:' || v_event::text, 'better-supabase/notifications');
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_service_principal_role (
  principal  uuid,
  role       text,
  created_by uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."service_principals";
begin
  select * into v_row from "better_supabase"."service_principals" p where p."id" = set_service_principal_role.principal and p."disabled_at" is null for update;
  if not found then
    raise exception 'No such service principal' using errcode = 'P0002', hint = 'SERVICE_PRINCIPAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if set_service_principal_role.created_by is not null and not (
    coalesce(better_supabase.member_can(set_service_principal_role.created_by, v_row."tenant_id", 'service_principals.manage'), false)
    and coalesce(better_supabase.can_assign_as(set_service_principal_role.created_by, v_row."tenant_id", set_service_principal_role.role), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if not ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (set_service_principal_role.role)::text or r."key" = (set_service_principal_role.role)::text) order by (r."id"::text = (set_service_principal_role.role)::text) desc limit 1) is not null) then
    raise exception 'Unknown role %', set_service_principal_role.role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  update "better_supabase"."service_principals" set "role" = set_service_principal_role.role where "id" = v_row."id";
  update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (set_service_principal_role.role)::text or r."key" = (set_service_principal_role.role)::text) order by (r."id"::text = (set_service_principal_role.role)::text) desc limit 1)
  where "organization_id" = v_row."tenant_id" and "user_id" = v_row."id";
  perform "better_supabase".emit_event('service_principal.role_changed', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'role', set_service_principal_role.role), 'service-principals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/service-accounts');
  perform better_supabase.audit_event(
    event_type => 'service_principal.role_changed',
    category => 'access',
    target_type => 'service_principal',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'role', set_service_principal_role.role),
    actor_id => coalesce(set_service_principal_role.created_by, auth.uid())
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.share_ai_chat (
  chat uuid,
  leaf text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_owner uuid;
  v_leaf text;
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select organization_id, owner_id, current_leaf_id into v_tenant, v_owner, v_leaf
  from "better_supabase".ai_chats where id = share_ai_chat.chat;
  if not found or v_owner is distinct from auth.uid() then
    raise exception 'no chat' using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_leaf);
  insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "role", "created_by", "leaf_id")
  values (v_tenant, 'ai-chat', share_ai_chat.chat::text, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), 'view', auth.uid(), v_leaf)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sso_on_auth_user()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scim record;
  v_join record;
  v_tenant uuid;
  v_user uuid := new.id;
begin
  if new.email is null or new.email_confirmed_at is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.email is not distinct from new.email and old.email_confirmed_at is not null then
    return new;
  end if;
  begin
    for v_scim in
      update "better_supabase"."scim_users" x set "user_id" = new.id
      where x."user_id" is null and x."email" = lower(new.email)
        and exists (select 1 from "better_supabase"."organization_domains" vd where vd."organization_id" = x."organization_id" and vd."verified_at" is not null and vd."domain" = lower(split_part(new.email, '@', 2)))
        and not exists (select 1 from "better_supabase"."scim_users" y where y."organization_id" = x."organization_id" and y."user_id" = new.id)
      returning x."id" as id
    loop
      perform "better_supabase"."scim_sync_member"(v_scim.id);
    end loop;
    for v_join in
      select x."organization_id" as tenant, x."auto_join_role" as role from "better_supabase"."organization_domains" x
      where x."verified_at" is not null and x."auto_join_role" is not null
        and x."domain" = lower(split_part(new.email, '@', 2))
        and not exists (select 1 from "better_supabase"."scim_users" y where y."organization_id" = x."organization_id" and y."user_id" = new.id)
        and not exists (select 1 from "public"."memberships" mm where mm."organization_id" = x."organization_id" and mm."user_id" = new.id)
    loop
      v_tenant := v_join.tenant;
      insert into "public"."memberships" ("organization_id", "user_id", "role") values (v_tenant, v_user, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_join.role)::text or r."key" = (v_join.role)::text) order by (r."id"::text = (v_join.role)::text) desc limit 1));
      perform "better_supabase".emit_event('organization.member_added', jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user, 'role', v_join.role), 'organizations/' || v_tenant::text, (v_tenant)::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => v_user::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'userId', v_user, 'role', v_join.role)
  );
    end loop;
  exception when others then
    raise warning 'SSO membership for user % failed: % (SQLSTATE %)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_disabled (
  tenant uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select false
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_ids_with (
  permission text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  ROWS 1
  SET search_path TO ''
  AS $function$
  select m."organization_id"
  from "public"."memberships" m
  where m."user_id" = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m."organization_id")
    and better_supabase.cap_allows(tenant_ids_with.permission)
    and exists (select 1 from "better_supabase"."permissions" p where p."key" = tenant_ids_with.permission and coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    ))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transfer_ownership (
  organization uuid,
  new_owner    uuid,
  former_role  text DEFAULT 'admin'::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.transfer_ownership'), false)) then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (
    select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = 'owner'
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (former_role)::text or r."key" = (former_role)::text) order by (r."id"::text = (former_role)::text) desc limit 1) is not null) then
    raise exception 'Unknown role %', former_role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = new_owner) then
    raise exception 'The new owner must be a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if better_supabase.user_disabled(new_owner) then
    raise exception 'The new owner is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- One statement for both rows, so a statement-level guard on the number of
  -- owners sees the transfer as a whole.
  update "public"."memberships" m set "role" = case
      when m."user_id" = new_owner then (select r."id" from "better_supabase"."roles" r where (r."id"::text = ('owner')::text or r."key" = ('owner')::text) order by (r."id"::text = ('owner')::text) desc limit 1)
      else (select r."id" from "better_supabase"."roles" r where (r."id"::text = (former_role)::text or r."key" = (former_role)::text) order by (r."id"::text = (former_role)::text) desc limit 1)
    end
  where m."organization_id" = organization
    and (m."user_id" = new_owner
      or (me is not null and me <> new_owner and m."user_id" = me and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = 'owner'));
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, new_owner, 'owner';
    end if;
  end;
  perform "better_supabase".emit_event('organization.ownership_transferred', jsonb_build_object('organizationId', organization::text, 'userId', new_owner, 'role', 'owner'), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
  perform better_supabase.audit_event(
    event_type => 'organization.ownership_transferred',
    category => 'membership',
    target_type => 'user',
    record_id => new_owner::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', new_owner, 'role', 'owner')
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_invitation (
  invitation_id uuid,
  invitee_email text  DEFAULT NULL::text,
  invitee_role  text  DEFAULT NULL::text,
  prefill       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  current_invite "better_supabase"."invitations";
  updated "better_supabase"."invitations";
  tenant uuid;
  platform_current "better_supabase"."platform_invitations";
  platform_updated "better_supabase"."platform_invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if invitee_email is not null and btrim(invitee_email) = '' then
    raise exception 'The email address is empty' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  select * into current_invite from "better_supabase"."invitations" i
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  for update;
  if current_invite."id" is null then
    select * into platform_current from "better_supabase"."platform_invitations" i
    where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
    for update;
    if platform_current."id" is not null then
      if platform_current."expires_at" < now() then
        raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
      end if;
      if not service and not (select coalesce(better_supabase.is_platform('platform.invite'), false)) then
        raise exception 'Not allowed to invite platform users' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
      end if;
      if invitee_role is not null and (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'platform' order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
        raise exception 'Unknown platform role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
      end if;
      if not service and (not better_supabase.platform_can_assign(auth.uid(), (platform_current."role")::text) or (invitee_role is not null and not better_supabase.platform_can_assign(auth.uid(), ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'platform' order by (r."id"::text = (invitee_role)::text) desc limit 1))::text))) then
        raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
      end if;
      if invitee_email is not null then
        delete from "better_supabase"."platform_invitations" i
        where lower(i."email") = lower(btrim(invitee_email))
          and i."id" <> invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
      end if;
      platform_updated := platform_current;
    if invitee_email is not null then
      platform_updated."email" := lower(btrim(invitee_email));
    end if;
    if invitee_role is not null then
      platform_updated."role" := (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'platform' order by (r."id"::text = (invitee_role)::text) desc limit 1);
    end if;
    update "better_supabase"."platform_invitations" i
    set "email" = platform_updated."email",
      "role" = platform_updated."role"
    where i."id" = invitation_id
    returning * into platform_updated;
      perform "better_supabase".emit_event('invitation.updated', jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email", 'role', platform_updated."role"), 'invitations/' || platform_updated."id"::text, null, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.updated',
    category => 'membership',
    target_type => 'invitation',
    record_id => platform_updated."id"::text,
    metadata => jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email", 'role', platform_updated."role")
  );
      return (jsonb_build_object(
    'id', platform_updated."id",
    'tenant', null,
    'email', platform_updated."email",
    'role', platform_updated."role",
    'expires_at', platform_updated."expires_at",
    'created_at', platform_updated."created_at",
    'invited_by', platform_updated."invited_by",
    'organization', null,
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = platform_updated."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(platform_updated."id")) - 'token';
    end if;
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if current_invite."expires_at" < now() then
    raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  tenant := current_invite."organization_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "public"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invitee_role is not null and (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'tenant' order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and (
    not better_supabase.can_assign(tenant, current_invite."role"::text)
    or (invitee_role is not null and not better_supabase.can_assign(tenant, ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'tenant' order by (r."id"::text = (invitee_role)::text) desc limit 1))::text))
  ) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if invitee_email is not null and exists (
    select 1 from "public"."memberships" m join auth.users u on u.id = m."user_id"
    where m."organization_id" = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    raise exception '% is already a member', invitee_email using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
  if invitee_email is not null then
    delete from "better_supabase"."invitations" i
    where i."organization_id" = tenant
      and lower(i."email") = lower(btrim(invitee_email))
      and i."id" <> invitation_id
      and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  end if;
  updated := current_invite;
    if invitee_email is not null then
      updated."email" := lower(btrim(invitee_email));
    end if;
    if invitee_role is not null then
      updated."role" := (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'tenant' order by (r."id"::text = (invitee_role)::text) desc limit 1);
    end if;
    update "better_supabase"."invitations" i
    set "email" = updated."email",
      "role" = updated."role"
    where i."id" = invitation_id
    returning * into updated;
  perform "better_supabase".emit_event('invitation.updated', jsonb_build_object('invitationId', updated."id", 'organizationId', tenant::text, 'email', updated."email", 'role', updated."role"), 'invitations/' || updated."id"::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.updated',
    category => 'membership',
    target_type => 'invitation',
    record_id => updated."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', updated."id", 'organizationId', tenant::text, 'email', updated."email", 'role', updated."role")
  );
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = updated."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = updated."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(updated."id")) - 'token';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_member_role (
  organization uuid,
  member       uuid,
  role         text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  previous text;
  previous_assignable text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (role)::text or r."key" = (role)::text) order by (r."id"::text = (role)::text) desc limit 1) is not null) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role"), m."role"::text into previous, previous_assignable
  from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever blocks.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (role)::text or r."key" = (role)::text) order by (r."id"::text = (role)::text) desc limit 1))::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (role)::text or r."key" = (role)::text) order by (r."id"::text = (role)::text) desc limit 1)
  where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  perform "better_supabase".emit_event('organization.role_changed', jsonb_build_object('organizationId', organization::text, 'userId', member, 'role', role, 'previousRole', previous), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
  perform better_supabase.audit_event(
    event_type => 'organization.role_changed',
    category => 'membership',
    target_type => 'user',
    record_id => member::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', member, 'role', role, 'previousRole', previous)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_organization_domain (
  id             uuid,
  auto_join_role text    DEFAULT NULL::text,
  enforce_sso    boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_domains";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_domains" x where x."id" = update_organization_domain.id for update;
  if v_row."id" is null or not coalesce(better_supabase.can('tenant', v_row."organization_id", 'sso.manage'), false) then
    raise exception 'No domain you manage has this id' using errcode = 'P0002', hint = 'SSO_DOMAIN_NOT_FOUND';
  end if;
  if update_organization_domain.auto_join_role is not null and not (update_organization_domain.auto_join_role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'Auto-join cannot assign role %', update_organization_domain.auto_join_role using errcode = '22023', hint = 'SSO_ROLE_INVALID';
  end if;
  if update_organization_domain.auto_join_role is not null
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    and not coalesce(better_supabase.can_assign(v_row."organization_id", update_organization_domain.auto_join_role), false) then
    raise exception 'You may not assign role %', update_organization_domain.auto_join_role using errcode = '42501', hint = 'SSO_ROLE_FORBIDDEN';
  end if;
  if (update_organization_domain.enforce_sso or update_organization_domain.auto_join_role is not null) and v_row."verified_at" is null then
    raise exception 'Verify the domain first' using errcode = '22023', hint = 'SSO_DOMAIN_NOT_VERIFIED';
  end if;
  update "better_supabase"."organization_domains" x set "auto_join_role" = update_organization_domain.auto_join_role, "enforce_sso" = update_organization_domain.enforce_sso
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('organization.domain_updated', jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', auth.uid()), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'organization.domain_updated',
    category => 'security',
    target_type => 'domain',
    record_id => v_row."id"::text,
    target_label => v_row."domain",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', auth.uid()),
    actor_id => auth.uid()
  );
  return to_jsonb(v_row) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."domain", 'value', 'better-supabase-domain-verification=' || v_row."verification_token"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.user_disabled (
  user_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select false
$function$;

ALTER TABLE "better_supabase"."organization_domains"
  ADD CONSTRAINT "organization_domains_auto_join_role_check" CHECK ((auto_join_role = ANY (ARRAY['admin'::text, 'member'::text, 'viewer'::text])));

ALTER TABLE "better_supabase"."permission_overrides"
  ADD CONSTRAINT "permission_overrides_permission_id_fkey" FOREIGN KEY (permission_id) REFERENCES better_supabase.permissions(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."platform_invitations"
  ADD CONSTRAINT "platform_invitations_accepted_by_fkey" FOREIGN KEY (accepted_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."platform_invitations"
  ADD CONSTRAINT "platform_invitations_invited_by_fkey" FOREIGN KEY (invited_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."platform_roles"
  ADD CONSTRAINT "platform_roles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."role_permissions"
  ADD CONSTRAINT "role_permissions_permission_id_fkey" FOREIGN KEY (permission_id) REFERENCES better_supabase.permissions(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."permission_overrides"
  ADD CONSTRAINT "permission_overrides_role_id_fkey" FOREIGN KEY (role_id) REFERENCES better_supabase.roles(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."platform_roles"
  ADD CONSTRAINT "platform_roles_role_id_fkey" FOREIGN KEY (role_id) REFERENCES better_supabase.roles(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."role_permissions"
  ADD CONSTRAINT "role_permissions_role_id_fkey" FOREIGN KEY (role_id) REFERENCES better_supabase.roles(id) ON DELETE CASCADE;

ALTER TABLE "public"."memberships"
  ADD CONSTRAINT "memberships_role_fkey" FOREIGN KEY (ROLE) REFERENCES better_supabase.roles(id) ON DELETE RESTRICT;

CREATE INDEX permission_overrides_permission_idx ON better_supabase.permission_overrides USING btree (permission_id);

CREATE INDEX permission_overrides_role_idx ON better_supabase.permission_overrides USING btree (role_id);

CREATE INDEX platform_invitations_accepted_by_idx ON better_supabase.platform_invitations USING btree (accepted_by);

CREATE INDEX platform_invitations_invited_by_idx ON better_supabase.platform_invitations USING btree (invited_by);

CREATE UNIQUE INDEX platform_invitations_open_email_idx ON better_supabase.platform_invitations USING btree (lower(email))
  WHERE ((accepted_at IS NULL) AND (declined_at IS NULL) AND (revoked_at IS NULL));

CREATE INDEX platform_roles_role_idx ON better_supabase.platform_roles USING btree (role_id);

CREATE INDEX role_permissions_permission_idx ON better_supabase.role_permissions USING btree (permission_id);

CREATE INDEX memberships_role_idx ON public.memberships USING btree (ROLE);

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.permission_overrides
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "category": "access", "key_columns": ["organization_id", "role_id", "permission_id"], "tenant_column": "organization_id"}');

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.permissions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "category": "access", "key_columns": ["id"]}');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.platform_invitations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.platform_roles
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "category": "access", "key_columns": ["user_id", "role_id"]}');

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.role_permissions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "category": "access", "key_columns": ["role_id", "permission_id"]}');

CREATE TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.roles
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "category": "access", "key_columns": ["id"]}');

CREATE TRIGGER bsb_clear_tenant_claim
  AFTER DELETE ON public.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.clear_tenant_claim();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON public.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE POLICY "bsb_platform_invitations_read" ON "better_supabase"."platform_invitations"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT better_supabase.platform_invitations_readable() AS platform_invitations_readable));

CREATE POLICY "bsb_tenant_scope_delete" ON "public"."memberships"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "public"."memberships"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "public"."memberships"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN (
    SELECT better_supabase.member_organization_ids() AS member_organization_ids)))));

CREATE POLICY "bsb_tenant_scope_update" ON "public"."memberships"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

COMMENT ON CONSTRAINT "roles_scope_check" ON "better_supabase"."roles" IS 'better-supabase check fb19a0bd';

REVOKE ALL ON FUNCTION "api"."can"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."can"(text, uuid, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."can_assign"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."can_assign"(uuid, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."can_assign_as"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."can_assign_as"(uuid, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."can_user"(uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."can_user"(uuid, text, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."cap_allows"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cap_allows"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."is_platform"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."is_platform"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."member_can"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."member_can"(uuid, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."member_can_while_deleting"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."member_can_while_deleting"(uuid, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."member_permissions"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."member_permissions"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."my_permissions"(uuid, text[]) FROM "anon";

GRANT EXECUTE ON FUNCTION "api"."my_permissions"(uuid, text[]) TO "anon";

REVOKE ALL ON FUNCTION "api"."operation_permission"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."operation_permission"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."permission_claims"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."permission_claims"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."permission_matches"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."permission_matches"(text, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."platform_can"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."platform_can"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."platform_can_assign"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."platform_can_assign"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."scope_permissions"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."scope_permissions"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."tenant_disabled"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."tenant_disabled"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."tenant_ids_with"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."tenant_ids_with"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."user_disabled"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."user_disabled"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can_assign_as"(uuid, uuid, text) FROM "supabase_auth_admin";

GRANT EXECUTE ON FUNCTION "better_supabase"."can_assign_as"(uuid, uuid, text) TO "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."cap_allows"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cap_allows"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."current_tenant_id"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."current_tenant_id"() FROM "anon";

GRANT EXECUTE ON FUNCTION "better_supabase"."current_tenant_id"() TO "anon";

REVOKE ALL ON FUNCTION "better_supabase"."current_tenant_id"() FROM "authenticated";

GRANT EXECUTE ON FUNCTION "better_supabase"."current_tenant_id"() TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."current_tenant_id"() FROM "service_role";

GRANT EXECUTE ON FUNCTION "better_supabase"."current_tenant_id"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."current_tenant_id"() FROM "supabase_auth_admin";

GRANT EXECUTE ON FUNCTION "better_supabase"."current_tenant_id"() TO "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."member_can"(uuid, uuid, text) FROM "supabase_auth_admin";

GRANT EXECUTE ON FUNCTION "better_supabase"."member_can"(uuid, uuid, text) TO "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."member_can_while_deleting"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_can_while_deleting"(uuid, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."member_permissions"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_permissions"(uuid, uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."operation_permission"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."operation_permission"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_member_roles"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_member_roles"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."permission_matches"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_matches"(text, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."platform_can"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."platform_can"(uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."platform_can_assign"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."platform_can_assign"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."platform_invitations_readable"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."platform_invitations_readable"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."scope_permissions"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."scope_permissions"(text) TO "anon", "authenticated", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."permission_overrides" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."permissions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."platform_invitations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."platform_invitations" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."platform_roles" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."role_permissions" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."roles" TO "service_role";

REVOKE ALL ON TABLE "public"."contacts" FROM "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."contacts" TO "service_role";

REVOKE ALL ON TABLE "public"."customers" FROM "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."customers" TO "service_role";

REVOKE ALL ON TABLE "public"."locations" FROM "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."locations" TO "service_role";

REVOKE ALL ON TABLE "public"."notes" FROM "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."notes" TO "service_role";

REVOKE ALL ON TABLE "public"."tags" FROM "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."tags" TO "service_role";
