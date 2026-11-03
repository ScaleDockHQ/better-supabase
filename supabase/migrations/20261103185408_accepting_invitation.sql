SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.accepting_invitation()
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accepting_invitation"() $function$;

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
  perform set_config('better_supabase.accepting_invitation', pinvite."id"::text, true);
  insert into "better_supabase"."platform_roles" ("user_id", "role_id")
  values (me, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (pinvite."role")::text or r."key" = (pinvite."role")::text) order by (r."id"::text = (pinvite."role")::text) desc limit 1))
  on conflict do nothing;
  perform set_config('better_supabase.accepting_invitation', '', true);
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
  perform set_config('better_supabase.accepting_invitation', invite."id"::text, true);
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invite."role")::text or r."key" = (invite."role")::text) order by (r."id"::text = (invite."role")::text) desc limit 1));
  perform set_config('better_supabase.accepting_invitation', '', true);
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
  perform set_config('better_supabase.accepting_invitation', pinvite."id"::text, true);
  insert into "better_supabase"."platform_roles" ("user_id", "role_id")
  values (me, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (pinvite."role")::text or r."key" = (pinvite."role")::text) order by (r."id"::text = (pinvite."role")::text) desc limit 1))
  on conflict do nothing;
  perform set_config('better_supabase.accepting_invitation', '', true);
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
  perform set_config('better_supabase.accepting_invitation', invite."id"::text, true);
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invite."role")::text or r."key" = (invite."role")::text) order by (r."id"::text = (invite."role")::text) desc limit 1));
  perform set_config('better_supabase.accepting_invitation', '', true);
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

CREATE OR REPLACE FUNCTION better_supabase.accepting_invitation()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select nullif(current_setting('better_supabase.accepting_invitation', true), '')::uuid
$function$;

REVOKE ALL ON FUNCTION "api"."accepting_invitation"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accepting_invitation"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accepting_invitation"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accepting_invitation"() TO "authenticated", "service_role";
