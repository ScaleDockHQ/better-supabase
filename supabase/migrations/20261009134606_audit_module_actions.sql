SET local check_function_bodies = off;

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
begin
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex')
  for update;
  if invite."id" is null then
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
  values (invite."organization_id", me, invite."role");
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
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role")
  );
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
begin
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."id" = invitation_id
  for update;
  if invite."id" is null then
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
  values (invite."organization_id", me, invite."role");
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
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role")
  );
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

CREATE OR REPLACE FUNCTION better_supabase.assign_conversation (
  conversation uuid,
  assignee     uuid,
  team         uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before uuid;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = assign_conversation.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.assign'), false) or (assignee = (select auth.uid()) and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false))) then
    raise exception 'not allowed to assign this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if assignee is not null and not coalesce(better_supabase.can_user(assignee, 'tenant', v_conv."tenant_id", 'inbox.read'), false) then
    raise exception 'the assignee cannot read this inbox' using errcode = '22023', hint = 'INBOX_ASSIGNEE_INVALID';
  end if;
  v_before := v_conv."assignee_id";
  update "better_supabase"."conversations" set
    "assignee_id" = assign_conversation.assignee,
    "team_id" = coalesce(assign_conversation.team, "team_id")
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from assignee then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'assigned', (select auth.uid()), jsonb_build_object('from', v_before, 'to', assign_conversation.assignee));
    null;
    if assignee is not null then
      insert into "better_supabase"."conversation_participants" ("conversation_id", "user_id") values (v_conv."id", assignee)
      on conflict do nothing;
    end if;
    if assignee is not null and assignee is distinct from (select auth.uid()) then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.assigned',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', v_conv."subject",
        'recipients', to_jsonb(array[assignee]),
        'key', 'inbox.assigned:' || v_conv."id"::text || ':' || assignee::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id")
      ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_after_write()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_new uuid[];
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."deleted_at" is not null then
    perform better_supabase.audit_event(
    event_type => 'comment.deleted',
    category => 'data',
    target_type => 'comment',
    record_id => new."id"::text,
    tenant => (new."organization_id")::uuid,
    metadata => jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id")
  );
    return null;
  end if;
  v_new := array(
    select x from unnest(new."mentions") x
    where (tg_op = 'INSERT' or not x = any(old."mentions"))
      and coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'comments.read'), false)
  );
  if tg_op = 'INSERT' then
    null;
  end if;
  if cardinality(v_new) > 0 then
    null;
  end if;
  -- notify() trusts only the service role, so the mention is sent as it,
  -- with the comment's author as the actor; the claims are restored after.
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'comment.mentioned',
      'tenant', new."organization_id",
      'actor', new."author_id",
      'subject_type', new."subject_type",
      'subject_id', new."subject_id",
      'summary', left(new."body", 140),
      'subject_label', null::text,
      'action_path', null::text,
      'recipients', to_jsonb(v_new),
      'key', 'comment.mentioned:' || new."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('commentId', new."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_api_key (
  name        text,
  public_id   text,
  secret_hash text,
  tenant      uuid                     DEFAULT NULL::uuid,
  personal    boolean                  DEFAULT false,
  scopes      text[]                   DEFAULT '{}'::text[],
  expires_at  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  rate_limit  integer                  DEFAULT NULL::integer,
  prefix      text                     DEFAULT 'bs'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  owner uuid := case when personal then auth.uid() end;
  created "better_supabase"."api_keys";
begin
  if personal and owner is null then
    raise exception 'Sign in to create a personal API key' using errcode = '42501', hint = 'API_KEY_SIGN_IN';
  end if;
  if not personal and tenant is null then
    raise exception 'A tenant API key needs a tenant' using errcode = '22023', hint = 'API_KEY_TENANT_REQUIRED';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    if not personal and not coalesce(better_supabase.can('tenant', tenant, 'api_keys.manage'), false) then
      raise exception 'Not allowed to manage API keys in this tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
    if personal and tenant is not null and not coalesce(better_supabase.can('tenant', tenant, 'api_keys.own'), false) then
      raise exception 'Not allowed to create API keys in this tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
    if personal and tenant is null and exists (
      select 1 from better_supabase.member_organization_ids() as m(id)
      where m.id not in (select better_supabase.tenant_ids_with('api_keys.own'))
    ) then
      raise exception 'Not allowed to create API keys for every tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
  end if;
  if expires_at is not null and expires_at <= now() then
    raise exception 'expires_at is in the past' using errcode = '22023', hint = 'API_KEY_EXPIRED';
  end if;
  insert into "better_supabase"."api_keys" ("organization_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "rate_limit", "expires_at")
  values (tenant, owner, create_api_key.name, create_api_key.prefix, create_api_key.public_id, create_api_key.secret_hash, coalesce(create_api_key.scopes, '{}'), create_api_key.rate_limit, create_api_key.expires_at)
  returning * into created;
  perform better_supabase.audit_event(
    event_type => 'api_key.created',
    category => 'security',
    target_type => 'api_key',
    record_id => created."id"::text,
    target_label => created."name",
    tenant => (created."organization_id")::uuid,
    metadata => jsonb_build_object('keyId', created."id", 'organizationId', created."organization_id"::text, 'userId', created."user_id", 'name', created."name", 'publicId', created."public_id")
  );
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."organization_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at",
    'state', case
      when created."revoked_at" is not null and created."revoked_at" <= now() then 'revoked'
      when created."expires_at" is not null and created."expires_at" <= now() then 'expired'
      when created."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = created."id" order by s."created_at" desc limit 1)
  );
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
  values (organization, owner, 'owner');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
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

CREATE OR REPLACE FUNCTION better_supabase.credential_delete (
  provider text,
  name     text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_delete.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_delete.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  delete from vault.secrets s where s.name = 'bs:cred:' || credential_delete.provider || ':' || credential_delete.name;
  if not found then
    return false;
  end if;
  perform better_supabase.audit_event(
    event_type => 'credential.deleted',
    category => 'security',
    target_type => 'credential',
    record_id => credential_delete.provider || ':' || credential_delete.name,
    metadata => jsonb_build_object('provider', credential_delete.provider, 'name', credential_delete.name)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.credential_set (
  provider    text,
  name        text,
  secret      text,
  description text DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_set.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_set.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;
  select s.id into v_id from vault.secrets s where s.name = 'bs:cred:' || credential_set.provider || ':' || credential_set.name;
  if v_id is null then
    v_id := vault.create_secret(
      credential_set.secret,
      'bs:cred:' || credential_set.provider || ':' || credential_set.name,
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_id, credential_set.secret);
  end if;
  perform better_supabase.audit_event(
    event_type => 'credential.set',
    category => 'security',
    target_type => 'credential',
    record_id => credential_set.provider || ':' || credential_set.name,
    metadata => jsonb_build_object('provider', credential_set.provider, 'name', credential_set.name)
  );
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_ai_tool_approval (
  approval_id text,
  approved    boolean,
  reason      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."ai_tool_approvals";
  v_decision text := case when decide_ai_tool_approval.approved then 'approved' else 'denied' end;
begin
  select * into v_row from "better_supabase"."ai_tool_approvals" x where x."approval_id" = decide_ai_tool_approval.approval_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No approval %', decide_ai_tool_approval.approval_id using errcode = 'P0002', hint = 'AI_APPROVAL_NOT_FOUND';
  end if;
  if decide_ai_tool_approval.approved is null then
    raise exception 'Approve or deny' using errcode = '22023', hint = 'AI_APPROVAL_INVALID';
  end if;
  if v_row."decision" is not null then
    if v_row."decision" = v_decision then
      return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
    end if;
    raise exception 'Approval % was already %', v_row."approval_id", v_row."decision" using errcode = 'P0001', hint = 'AI_APPROVAL_DECIDED';
  end if;
  update "better_supabase"."ai_tool_approvals" x set
    "decision" = v_decision,
    "reason" = decide_ai_tool_approval.reason,
    "decided_by" = auth.uid(),
    "decided_at" = now()
  where x."approval_id" = v_row."approval_id"
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."chat_id", null, 'approval.decided', jsonb_build_object('approvalId', v_row."approval_id", 'decision', v_decision), false);
  perform better_supabase.audit_event(
    event_type => 'ai_tool_approval.decided',
    category => 'ai',
    target_type => 'ai_tool_approval',
    record_id => v_row."approval_id",
    target_label => v_row."tool",
    tenant => ((select c."organization_id" from "better_supabase"."ai_chats" c where c."id" = v_row."chat_id"))::uuid,
    metadata => jsonb_build_object('organizationId', (select c."organization_id" from "better_supabase"."ai_chats" c where c."id" = v_row."chat_id")::text, 'chatId', v_row."chat_id", 'approvalId', v_row."approval_id", 'tool', v_row."tool", 'decision', v_decision),
    idempotency_key => 'ai_tool_approval.decided:' || v_row."approval_id"
  );
  return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_connector_fingerprint (
  server_id   uuid,
  fingerprint text,
  approved    boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  if not found then
    return false;
  end if;
  perform better_supabase.audit_event(
    event_type => 'connector.fingerprint_decided',
    category => 'integration',
    target_type => 'connector',
    record_id => v_server."id"::text,
    target_label => v_server."name",
    tenant => (v_server."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_server."organization_id"::text, 'serverId', v_server."id", 'name', v_server."name", 'fingerprint', decide_connector_fingerprint.fingerprint, 'approved', decide_connector_fingerprint.approved)
  );
  return true;
end;
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
  update "better_supabase"."invitations" i set "declined_at" = now() where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex') and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
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
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if invitee_email is null then
    return false;
  end if;
  update "better_supabase"."invitations" i set "declined_at" = now() where i."id" = invitation_id and lower(i."email") = invitee_email and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
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
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_agent (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'agent.deleted',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_provider_key (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_provider_keys" x where x."id" = delete_ai_provider_key.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_provider_keys" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'ai_provider_key.deleted',
    category => 'security',
    target_type => 'ai_provider_key',
    record_id => v_row."id"::text,
    target_label => v_row."provider" || '/' || v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_announcement (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = delete_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform better_supabase.audit_event(
    event_type => 'announcement.deleted',
    category => 'configuration',
    target_type => 'announcement',
    record_id => delete_announcement.id::text,
    metadata => jsonb_build_object('announcementId', delete_announcement.id)
  );
  end if;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_connector_server (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'connector.deleted',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  return v_grants;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_flag (
  key text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  delete from "better_supabase"."flags" x where x."key" = delete_flag.key;
  if not found then
    return false;
  end if;
  perform better_supabase.audit_event(
    event_type => 'flag.deleted',
    category => 'configuration',
    target_type => 'flag',
    record_id => delete_flag.key,
    metadata => jsonb_build_object('key', delete_flag.key)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_organization (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.delete'), false) then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  delete from "public"."organizations" where "id" = organization;
  if not found then
    return false;
  end if;
  delete from "public"."memberships" where "organization_id" = organization;
  perform better_supabase.audit_event(
    event_type => 'organization.deleted',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('mode', 'hard')
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_add_message (
  conversation uuid,
  input        jsonb,
  author_type  text,
  author       uuid,
  direction    text
)
  RETURNS better_supabase.inbox_messages
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_mentions uuid[];
  v_reopened boolean := false;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = inbox_add_message.conversation for update;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = v_conv."inbox_id";
  if input ? 'external_id' then
    select * into v_msg from "better_supabase"."inbox_messages" m
    where m."conversation_id" = v_conv."id" and m."external_id" = input ->> 'external_id';
    if found then
      return v_msg;
    end if;
  end if;
  if length(btrim(coalesce(input ->> 'body', ''))) = 0 and coalesce(jsonb_array_length(input -> 'attachments'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_mentions
  from jsonb_array_elements_text(coalesce(input -> 'mentions', '[]'::jsonb)) e(raw)
  cross join lateral (select e.raw::uuid as x) u
  where coalesce(better_supabase.can_user(u.x, 'tenant', v_conv."tenant_id", 'inbox.read'), false);
  insert into "better_supabase"."inbox_messages" ("tenant_id", "conversation_id", "direction", "kind", "author_type", "author_id", "body", "format", "attachments", "mentions", "external_id", "reply_to", "metadata")
  values (
    v_conv."tenant_id", v_conv."id", inbox_add_message.direction, v_kind, inbox_add_message.author_type, inbox_add_message.author,
    coalesce(input ->> 'body', ''), coalesce(input ->> 'format', 'text'), coalesce(input -> 'attachments', '[]'::jsonb), v_mentions,
    input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_msg;
  insert into "better_supabase"."inbox_mentions" ("message_id", "user_id", "tenant_id")
  select v_msg."id", x, v_msg."tenant_id" from unnest(v_mentions) x
  on conflict do nothing;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv."status" in ('resolved', 'snoozed');
    update "better_supabase"."conversations" set
      "last_message_at" = v_msg."created_at",
      "last_message_preview" = left(v_msg."body", 140),
      "first_response_at" = case
        when "first_response_at" is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_msg."created_at"
        else "first_response_at" end,
      "status" = case when v_reopened then 'open' else "status" end,
      "snoozed_until" = case when v_reopened then null else "snoozed_until" end,
      "resolved_at" = case when v_reopened then null else "resolved_at" end
    where "id" = v_conv."id"
    returning * into v_conv;
    if v_reopened then
      insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'reopened', (select auth.uid()), jsonb_build_object('by', 'contact'));
      null;
    end if;
  end if;
  if inbox_add_message.author is not null and inbox_add_message.author_type = 'agent' then
    insert into "better_supabase"."conversation_participants" ("conversation_id", "user_id") values (v_conv."id", inbox_add_message.author)
    on conflict do nothing;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    null;
    if v_conv."bot_mode" = 'bot' then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_bot', payload => jsonb_build_object('conversation_id', v_conv."id", 'message_id', v_msg."id", 'thread_id', v_conv."thread_id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox:' || v_conv."id"::text, dedupe_running => false);
    end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_msg."body", 140),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.message:' || v_msg."id"::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_msg."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox."channel" <> 'in_app' then
    insert into "better_supabase"."message_deliveries" ("tenant_id", "message_id", "channel")
    values (v_msg."tenant_id", v_msg."id", v_inbox."channel")
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_outbound', payload => jsonb_build_object('message_id', v_msg."id", 'conversation_id', v_conv."id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox-out:' || v_msg."id"::text, dedupe_running => false);
    end if;
  end if;
  if cardinality(v_mentions) > 0 then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.mention',
      'tenant', v_conv."tenant_id",
      'actor', inbox_add_message.author,
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_msg."body", 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_msg."id"::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_msg."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return v_msg;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.install_agent (
  tenant    uuid,
  agent_id  uuid,
  installed boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'ai_chat.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."organization_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      perform better_supabase.audit_event(
    event_type => 'agent.uninstalled',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read'))))) or x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "organization_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    perform better_supabase.audit_event(
    event_type => 'agent.installed',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
  end if;
  return v_count > 0;
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
begin
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  if tenant is null then
    raise exception 'Platform invitations need platform roles: sql.modules.access.model ''catalog'' with platform assignments, or sql.modules.invitations.options.platformRoles under ''provider''' using errcode = '0A000', hint = 'INVITATION_SCOPE_UNSUPPORTED';
  end if;
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "public"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invitee_role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and not better_supabase.can_assign(tenant, (invitee_role)::text) then
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
  values (tenant, lower(btrim(invitee_email)), invitee_role, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
  returning * into created;
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

CREATE OR REPLACE FUNCTION better_supabase.leave_organization (
  organization uuid
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
  delete from "public"."memberships" where "organization_id" = organization and "user_id" = me;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, me, 'left';
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'organization.member_left',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', me)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_agent (
  id         uuid,
  visibility text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)
    or (v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.share'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'agent.published',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug", 'visibility', publish_agent.visibility)
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_workflow_version (
  version  uuid,
  compiled jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_errors jsonb;
begin
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.publish'), false))) then
    raise exception 'You may not publish this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if compiled is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role may store a compiled form' using errcode = '42501', hint = 'WORKFLOW_COMPILED_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    if compiled is not null then
      update "better_supabase"."workflow_versions" x set "compiled" = compiled
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set "status" = 'published', "compiled" = compiled, "published_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'workflow.published',
    category => 'configuration',
    target_type => 'workflow_version',
    record_id => v_row."id"::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row."definition_id", 'versionId', v_row."id", 'version', v_row."version"),
    idempotency_key => 'workflow.published:' || v_row."id"::text
  );
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_connector_grant (
  server_id      uuid,
  owner          uuid,
  credential_ref jsonb,
  scopes         text[]                   DEFAULT '{}'::text[],
  expires_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_old "better_supabase"."connector_grants"%rowtype;
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = record_connector_grant.server_id;
  if not found then
    raise exception 'connector % not found', record_connector_grant.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."organization_id", 'ai_chat.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "better_supabase"."connector_grants" ("user_id", "server_id", "organization_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."organization_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'connector_grant.created',
    category => 'integration',
    target_type => 'connector_grant',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'grantId', v_row."id", 'serverId', v_row."server_id", 'userId', v_row."user_id")
  );
  return jsonb_build_object('grant', jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at"), 'replaced', case when v_old."id" is null then null else jsonb_build_object('id', v_old."id", 'user_id', v_old."user_id", 'server_id', v_old."server_id", 'organization_id', v_old."organization_id", 'credential_ref', v_old."credential_ref", 'scopes', v_old."scopes", 'expires_at', v_old."expires_at", 'granted_at', v_old."granted_at", 'revoked_at', v_old."revoked_at") end);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_inbound (
  input jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact "better_supabase"."contacts"%rowtype;
  v_conv "better_supabase"."conversations"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_created boolean := false;
  v_duplicate boolean := false;
  v_message jsonb := coalesce(input -> 'message', '{}'::jsonb);
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from "better_supabase"."inboxes" where "id" = (input ->> 'inbox_id')::uuid;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if v_contact_input ? 'external_id' and not v_contact_input ? 'identity' then
    v_contact_input := v_contact_input || jsonb_build_object('identity', jsonb_build_object('channel', coalesce(v_contact_input ->> 'channel', v_inbox."channel"), 'external_id', v_contact_input ->> 'external_id'));
  end if;
  select * into v_conv from "better_supabase"."conversations"
  where "inbox_id" = v_inbox."id" and "thread_id" = input ->> 'thread_id'
  for update;
  if not found then
    v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
    insert into "better_supabase"."conversations" ("tenant_id", "inbox_id", "contact_id", "subject", "bot_mode", "thread_id", "metadata")
    values (v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', v_inbox."bot_mode", input ->> 'thread_id', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_conv;
    v_created := true;
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), jsonb_build_object('by', 'channel'));
    null;
  end if;
  if v_message ? 'external_id' then
    v_duplicate := exists (select 1 from "better_supabase"."inbox_messages" m where m."conversation_id" = v_conv."id" and m."external_id" = v_message ->> 'external_id');
  end if;
  v_msg := "better_supabase"."inbox_add_message"(
    v_conv."id",
    v_message - 'kind',
    case when coalesce(input ->> 'direction', 'inbound') = 'inbound' then 'contact' else coalesce(input ->> 'author_type', 'bot') end,
    null,
    coalesce(input ->> 'direction', 'inbound')
  );
  return jsonb_build_object(
    'conversation_id', v_conv."id",
    'message_id', v_msg."id",
    'contact_id', v_conv."contact_id",
    'tenant_id', v_conv."tenant_id",
    'created', v_created,
    'duplicate', v_duplicate
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_organization_setting()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_settings";
begin
  if tg_op = 'DELETE' then
    v_row := old;
    perform better_supabase.audit_event(
    event_type => 'organization_setting.reset',
    category => 'configuration',
    target_type => 'setting',
    record_id => v_row."key",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'key', v_row."key")
  );
  else
    v_row := new;
    perform better_supabase.audit_event(
    event_type => 'organization_setting.updated',
    category => 'configuration',
    target_type => 'setting',
    record_id => v_row."key",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'key', v_row."key")
  );
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_platform_setting()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."platform_settings";
begin
  if tg_op = 'DELETE' then
    v_row := old;
    perform better_supabase.audit_event(
    event_type => 'platform_setting.reset',
    category => 'configuration',
    target_type => 'setting',
    record_id => v_row."key",
    metadata => jsonb_build_object('key', v_row."key")
  );
  else
    v_row := new;
    perform better_supabase.audit_event(
    event_type => 'platform_setting.updated',
    category => 'configuration',
    target_type => 'setting',
    record_id => v_row."key",
    metadata => jsonb_build_object('key', v_row."key")
  );
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_push_device (
  token       text,
  platform    text,
  provider    text DEFAULT 'expo'::text,
  device_name text DEFAULT NULL::text,
  app_version text DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_new boolean;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if register_push_device.platform is null or register_push_device.platform not in ('ios', 'android', 'web') then
    raise exception 'Unknown push platform %', register_push_device.platform using errcode = '22023', hint = 'PUSH_PLATFORM';
  end if;
  if register_push_device.provider is null or register_push_device.provider not in ('expo', 'fcm', 'apns', 'webpush') then
    raise exception 'Unknown push provider %', register_push_device.provider using errcode = '22023', hint = 'PUSH_PROVIDER';
  end if;
  if register_push_device.token is null or length(register_push_device.token) not between 1 and 4096 then
    raise exception 'A push token is 1 to 4096 characters' using errcode = '22023', hint = 'PUSH_TOKEN';
  end if;
  insert into "better_supabase"."push_devices" as x ("user_id", "token", "platform", "provider", "device_name", "app_version")
  values (
    v_user,
    register_push_device.token,
    register_push_device.platform,
    register_push_device.provider,
    left(register_push_device.device_name, 200),
    left(register_push_device.app_version, 50)
  )
  on conflict ("token") do update set
    "user_id" = excluded."user_id",
    "platform" = excluded."platform",
    "provider" = excluded."provider",
    "device_name" = coalesce(excluded."device_name", x."device_name"),
    "app_version" = coalesce(excluded."app_version", x."app_version"),
    "last_seen_at" = now()
  returning x."id", (x.xmax = 0) into v_id, v_new;
  if v_new then
    perform better_supabase.audit_event(
    event_type => 'push.device_registered',
    category => 'security',
    target_type => 'push_device',
    record_id => v_id::text,
    metadata => jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text, 'platform', register_push_device.platform, 'provider', register_push_device.provider)
  );
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_member (
  organization uuid,
  member       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  current_role_value text;
begin
  if member = auth.uid() then
    raise exception 'Leave the organization instead' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to remove members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  select m."role"::text into current_role_value from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  delete from "public"."memberships" where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'removed';
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'organization.member_removed',
    category => 'membership',
    target_type => 'user',
    record_id => member::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', member)
  );
  return true;
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
begin
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
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
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
declare
  v_chat_id uuid;
  v_chat "better_supabase"."ai_chats";
begin
  update "better_supabase"."ai_chat_shares" x set "revoked_at" = now()
  where x."id" = revoke_ai_chat_share.id
    and x."revoked_at" is null
    and (
      coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or x."created_by" = (select auth.uid())
      or exists (select 1 from "better_supabase"."ai_chats" c where c."id" = x."chat_id" and c."owner_id" = (select auth.uid()))
    )
  returning x."chat_id" into v_chat_id;
  if v_chat_id is null then
    return false;
  end if;
  select * into v_chat from "better_supabase"."ai_chats" c where c."id" = v_chat_id;
  perform better_supabase.audit_event(
    event_type => 'ai_chat.share_revoked',
    category => 'ai',
    target_type => 'ai_chat_share',
    record_id => revoke_ai_chat_share.id::text,
    tenant => (v_chat."organization_id")::uuid,
    metadata => jsonb_build_object('chatId', v_chat."id", 'shareId', revoke_ai_chat_share.id, 'organizationId', v_chat."organization_id"::text, 'ownerId', v_chat."owner_id")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_api_key (
  key uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  found "better_supabase"."api_keys";
begin
  select * into found from "better_supabase"."api_keys" k where k."id" = revoke_api_key.key;
  if found."id" is null or not ((found."organization_id" is not null and coalesce(better_supabase.can('tenant', found."organization_id", 'api_keys.manage'), false)) or coalesce(found."user_id" = auth.uid(), false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'API key not found' using errcode = 'P0002', hint = 'API_KEY_NOT_FOUND';
  end if;
  update "better_supabase"."api_keys" k set "revoked_at" = now()
  where k."id" = found."id" and (k."revoked_at" is null or k."revoked_at" > now());
  perform better_supabase.audit_event(
    event_type => 'api_key.revoked',
    category => 'security',
    target_type => 'api_key',
    record_id => found."id"::text,
    target_label => found."name",
    tenant => (found."organization_id")::uuid,
    metadata => jsonb_build_object('keyId', found."id", 'organizationId', found."organization_id"::text, 'userId', found."user_id", 'name', found."name", 'publicId', found."public_id")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_connector_grant (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "better_supabase"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
  perform better_supabase.audit_event(
    event_type => 'connector_grant.revoked',
    category => 'integration',
    target_type => 'connector_grant',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'grantId', v_row."id", 'serverId', v_row."server_id", 'userId', v_row."user_id")
  );
  return jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at");
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
  update "better_supabase"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."organization_id"::text into tenant;
  if found then
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
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_api_key (
  key         uuid,
  public_id   text,
  secret_hash text,
  grace       interval DEFAULT '1 day'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  old "better_supabase"."api_keys";
  created "better_supabase"."api_keys";
begin
  select * into old from "better_supabase"."api_keys" k where k."id" = rotate_api_key.key for update;
  if old."id" is null or not ((old."organization_id" is not null and coalesce(better_supabase.can('tenant', old."organization_id", 'api_keys.manage'), false)) or coalesce(old."user_id" = auth.uid(), false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'API key not found' using errcode = 'P0002', hint = 'API_KEY_NOT_FOUND';
  end if;
  if old."revoked_at" is not null and old."revoked_at" <= now() then
    raise exception 'A revoked API key cannot be rotated' using errcode = '22023', hint = 'API_KEY_REVOKED';
  end if;
  if old."expires_at" is not null and old."expires_at" <= now() then
    raise exception 'An expired API key cannot be rotated' using errcode = '22023', hint = 'API_KEY_EXPIRED';
  end if;
  if grace is null or grace < interval '0' then
    raise exception 'grace must be zero or more' using errcode = '22023', hint = 'API_KEY_GRACE';
  end if;
  insert into "better_supabase"."api_keys" ("organization_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "rate_limit", "expires_at", "rotated_from")
  values (old."organization_id", old."user_id", old."name", old."prefix", rotate_api_key.public_id, rotate_api_key.secret_hash, old."scopes", old."rate_limit", old."expires_at", old."id")
  returning * into created;
  update "better_supabase"."api_keys" k set "revoked_at" = now() + grace where k."id" = old."id";
  perform better_supabase.audit_event(
    event_type => 'api_key.rotated',
    category => 'security',
    target_type => 'api_key',
    record_id => created."id"::text,
    target_label => created."name",
    tenant => (created."organization_id")::uuid,
    metadata => jsonb_build_object('keyId', created."id", 'organizationId', created."organization_id"::text, 'userId', created."user_id", 'name', created."name", 'publicId', created."public_id", 'previousKeyId', old."id")
  );
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."organization_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at",
    'state', case
      when created."revoked_at" is not null and created."revoked_at" <= now() then 'revoked'
      when created."expires_at" is not null and created."expires_at" <= now() then 'expired'
      when created."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = created."id" order by s."created_at" desc limit 1)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_agent (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'ai_chat.create'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("organization_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."organization_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'agent.saved',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_assistant_message (
  chat      uuid,
  message   jsonb,
  parent_id text,
  status    text  DEFAULT 'complete'::text,
  model     text  DEFAULT NULL::text,
  format    text  DEFAULT 'canonical'::text,
  native    jsonb DEFAULT NULL::jsonb,
  run       uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_id text := save_ai_assistant_message.message ->> 'id';
  v_role text := coalesce(save_ai_assistant_message.message ->> 'role', 'assistant');
  v_status text := coalesce(save_ai_assistant_message.status, 'complete');
  v_created boolean;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = save_ai_assistant_message.chat for update;
  if not found then
    raise exception 'No chat %', save_ai_assistant_message.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if nullif(v_id, '') is null or v_role = 'user'
    or jsonb_typeof(save_ai_assistant_message.message -> 'parts') is distinct from 'array' then
    raise exception 'A reply needs an id, a role other than user and parts' using errcode = '22023', hint = 'AI_MESSAGE_INVALID';
  end if;
  if save_ai_assistant_message.parent_id is not null and not exists (
    select 1 from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = save_ai_assistant_message.parent_id
  ) then
    raise exception 'No message %', save_ai_assistant_message.parent_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_messages" ("chat_id", "id", "parent_id", "owner_id", "role", "parts", "metadata", "format", "native", "model", "status")
  values (
    v_chat."id", v_id, save_ai_assistant_message.parent_id, v_chat."owner_id", v_role,
    save_ai_assistant_message.message -> 'parts',
    case when jsonb_typeof(save_ai_assistant_message.message -> 'metadata') = 'object' then save_ai_assistant_message.message -> 'metadata' else '{}'::jsonb end,
    coalesce(save_ai_assistant_message.format, 'canonical'), save_ai_assistant_message.native,
    save_ai_assistant_message.model, v_status
  )
  on conflict ("chat_id", "id") do update set
    "parts" = excluded."parts",
    "metadata" = excluded."metadata",
    "format" = excluded."format",
    "native" = excluded."native",
    "model" = coalesce(excluded."model", "better_supabase"."ai_messages"."model"),
    "status" = excluded."status"
  returning (xmax = 0) into v_created;
  delete from "better_supabase"."ai_message_sources" x where x."chat_id" = v_chat."id" and x."message_id" = v_id;
  insert into "better_supabase"."ai_message_sources" ("chat_id", "message_id", "source_id", "source_type", "url", "title", "provider_metadata")
  select distinct on (e ->> 'id') v_chat."id", v_id, e ->> 'id', coalesce(e ->> 'sourceType', 'url'), e ->> 'url', e ->> 'title', e -> 'providerMetadata'
  from jsonb_array_elements(save_ai_assistant_message.message -> 'parts') e
  where e ->> 'type' = 'source' and nullif(e ->> 'id', '') is not null and coalesce(e ->> 'sourceType', 'url') in ('url', 'document')
  order by e ->> 'id';
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_id, "last_message_at" = clock_timestamp(), "updated_at" = now() where x."id" = v_chat."id";
  if save_ai_assistant_message.run is not null then
    update "better_supabase"."ai_runs" x set "assistant_message_id" = v_id where x."id" = save_ai_assistant_message.run and x."chat_id" = v_chat."id";
  end if;
  if v_status = 'complete' then
    null;
  end if;
  perform "better_supabase"."ai_chat_notify"(v_chat."id", v_chat."owner_id", 'message.saved', jsonb_build_object('messageId', v_id), not v_chat."is_temporary");
  return jsonb_build_object('message_id', v_id, 'parent_id', save_ai_assistant_message.parent_id, 'created', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_provider_key (
  tenant         uuid,
  provider       text,
  credential_ref jsonb,
  name           text    DEFAULT 'default'::text,
  settings       jsonb   DEFAULT '{}'::jsonb,
  enabled        boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old jsonb;
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_provider_key.tenant, 'ai_chat.admin'), false)) then
    raise exception 'you may not manage provider keys here' using errcode = '42501', hint = 'AI_PROVIDER_KEY_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_ai_provider_key.credential_ref is not null and jsonb_typeof(save_ai_provider_key.credential_ref) <> 'null'
    and (jsonb_typeof(save_ai_provider_key.credential_ref -> 'tenant') is distinct from 'string' or (save_ai_provider_key.credential_ref ->> 'tenant') is distinct from (save_ai_provider_key.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_ai_provider_key.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  select x."credential_ref" into v_old from "better_supabase"."ai_provider_keys" x
  where x."organization_id" = save_ai_provider_key.tenant and x."provider" = save_ai_provider_key.provider and x."name" = coalesce(save_ai_provider_key.name, 'default')
  for update;
  insert into "better_supabase"."ai_provider_keys" ("organization_id", "provider", "name", "credential_ref", "settings", "enabled", "created_by")
  values (save_ai_provider_key.tenant, save_ai_provider_key.provider, coalesce(save_ai_provider_key.name, 'default'), save_ai_provider_key.credential_ref, coalesce(save_ai_provider_key.settings, '{}'), coalesce(save_ai_provider_key.enabled, true), auth.uid())
  on conflict ("organization_id", "provider", "name") do update set
    "credential_ref" = excluded."credential_ref",
    "settings" = excluded."settings",
    "enabled" = excluded."enabled",
    "updated_at" = now()
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'ai_provider_key.saved',
    category => 'security',
    target_type => 'ai_provider_key',
    record_id => v_row."id"::text,
    target_label => v_row."provider" || '/' || v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name")
  );
  return jsonb_build_object('key', jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at"), 'replaced', v_old);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_announcement (
  id     uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."announcements";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  perform better_supabase.audit_event(
    event_type => 'announcement.saved',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_connector_server (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai_chat.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_connector_server.fields -> 'credential_ref' is not null and jsonb_typeof(save_connector_server.fields -> 'credential_ref') <> 'null'
    and (jsonb_typeof(save_connector_server.fields -> 'credential_ref' -> 'tenant') is distinct from 'string' or (save_connector_server.fields -> 'credential_ref' ->> 'tenant') is distinct from (save_connector_server.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_connector_server.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  if save_connector_server.id is null then
    insert into "better_supabase"."connector_servers" ("organization_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."connector_servers" x where x."id" = save_connector_server.id and x."organization_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = coalesce(save_connector_server.fields ->> 'transport', x."transport"),
    "auth_type" = coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'connector.saved',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_flag (
  key        text,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  d jsonb := coalesce(definition, '{}');
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "rules", "rollout_percentage", "rollout_variant")
  values (
    save_flag.key,
    coalesce(d ->> 'type', 'boolean'),
    d ->> 'description',
    coalesce(d -> 'variants', '{"on": true, "off": false}'::jsonb),
    coalesce(d ->> 'default_variant', 'off'),
    coalesce((d ->> 'enabled')::boolean, true),
    coalesce(d -> 'rules', '[]'::jsonb),
    coalesce((d ->> 'rollout_percentage')::numeric, 0),
    d ->> 'rollout_variant'
  )
  on conflict ("key") do update set
    "type" = case when d ? 'type' then excluded."type" else x."type" end,
    "description" = case when d ? 'description' then excluded."description" else x."description" end,
    "variants" = case when d ? 'variants' then excluded."variants" else x."variants" end,
    "default_variant" = case when d ? 'default_variant' then excluded."default_variant" else x."default_variant" end,
    "enabled" = case when d ? 'enabled' then excluded."enabled" else x."enabled" end,
    "rules" = case when d ? 'rules' then excluded."rules" else x."rules" end,
    "rollout_percentage" = case when d ? 'rollout_percentage' then excluded."rollout_percentage" else x."rollout_percentage" end,
    "rollout_variant" = case when d ? 'rollout_variant' then excluded."rollout_variant" else x."rollout_variant" end,
    "updated_at" = now();
  perform better_supabase.audit_event(
    event_type => 'flag.saved',
    category => 'configuration',
    target_type => 'flag',
    record_id => save_flag.key,
    metadata => jsonb_build_object('key', save_flag.key)
  );
  return (select v from jsonb_array_elements("better_supabase"."flag_definitions"()) v where v ->> 'key' = save_flag.key);
end;
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
  if v_type is null or btrim(v_type) = '' then
    raise exception 'A notification needs a type' using errcode = '22023', hint = 'NOTIFICATION_TYPE_REQUIRED';
  end if;
  if not (v_priority = any(array['low', 'normal', 'high', 'urgent']::text[])) then
    raise exception 'Unknown notification priority' using errcode = '22023', hint = 'NOTIFICATION_PRIORITY_UNKNOWN';
  end if;
  if v_activity not in ('participating', 'all') then
    raise exception 'activity must be participating or all' using errcode = '22023', hint = 'NOTIFICATION_ACTIVITY_UNKNOWN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    if v_tenant is null or not coalesce(better_supabase.member_can(auth.uid(), v_tenant, 'notifications.send'), false) then
      raise exception 'Not allowed to send notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
    end if;
    v_actor := auth.uid();
  end if;
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
    insert into "better_supabase"."notification_events" ("type", "data", "organization_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', v_priority, v_key, auth.uid())
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
  null;
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_ai_tool_policy (
  tenant uuid,
  tool   text,
  policy text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_ai_tool_policy.tenant, 'ai_chat.admin'), false)) then
    raise exception 'You may not change tool policies here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if set_ai_tool_policy.policy is null then
    delete from "better_supabase"."ai_tool_policies" x where x."organization_id" = set_ai_tool_policy.tenant and x."tool" = set_ai_tool_policy.tool;
    perform better_supabase.audit_event(
    event_type => 'ai_tool_policy.set',
    category => 'ai',
    target_type => 'ai_tool_policy',
    record_id => set_ai_tool_policy.tool,
    tenant => (set_ai_tool_policy.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', set_ai_tool_policy.tenant::text, 'tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy)
  );
    return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', null);
  end if;
  insert into "better_supabase"."ai_tool_policies" ("organization_id", "tool", "policy")
  values (set_ai_tool_policy.tenant, set_ai_tool_policy.tool, set_ai_tool_policy.policy)
  on conflict ("organization_id", "tool") do update set "policy" = excluded."policy", "updated_at" = now();
  perform better_supabase.audit_event(
    event_type => 'ai_tool_policy.set',
    category => 'ai',
    target_type => 'ai_tool_policy',
    record_id => set_ai_tool_policy.tool,
    tenant => (set_ai_tool_policy.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', set_ai_tool_policy.tenant::text, 'tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy)
  );
  return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_conversation_status (
  conversation  uuid,
  status        text,
  snoozed_until timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = set_conversation_status.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if status = 'snoozed' and snoozed_until is null then
    raise exception 'snoozing needs snoozed_until' using errcode = '22023', hint = 'INBOX_SNOOZE_UNTIL';
  end if;
  v_before := v_conv."status";
  update "better_supabase"."conversations" set
    "status" = set_conversation_status.status,
    "snoozed_until" = case when set_conversation_status.status = 'snoozed' then set_conversation_status.snoozed_until end,
    "resolved_at" = case when set_conversation_status.status = 'resolved' then now() end
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from status then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'status', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_conversation_status.status));
    if status = 'resolved' then
      null;
    elsif v_before = 'resolved' then
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_flag_override (
  key     text,
  variant text,
  tenant  uuid DEFAULT NULL::uuid,
  member  uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if (tenant is null) = (member is null) then
    raise exception 'Pass a tenant or a member, not both' using errcode = '22023', hint = 'FLAGS_OVERRIDE_TARGET';
  end if;
  if variant is null then
    delete from "better_supabase"."flag_overrides" v
    where v."flag_key" = set_flag_override.key
      and v."organization_id" is not distinct from set_flag_override.tenant
      and v."user_id" is not distinct from set_flag_override.member;
    if not found then
      return false;
    end if;
    perform better_supabase.audit_event(
    event_type => 'flag.override_set',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member)
  );
    return true;
  end if;
  insert into "better_supabase"."flag_overrides" ("flag_key", "organization_id", "user_id", "variant")
  values (set_flag_override.key, set_flag_override.tenant, set_flag_override.member, set_flag_override.variant)
  on conflict ("flag_key", "organization_id", "user_id") do update set "variant" = excluded."variant";
  perform better_supabase.audit_event(
    event_type => 'flag.override_set',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member)
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
  v_chat "better_supabase"."ai_chats";
  v_leaf text;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_id uuid;
  v_created timestamptz;
begin
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = share_ai_chat.chat;
  if not found or v_chat."owner_id" is distinct from auth.uid() then
    raise exception 'No chat %', share_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.can('tenant', v_chat."organization_id", 'ai_chat.share'), false) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_chat."current_leaf_id");
  if v_leaf is null or not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_leaf) then
    raise exception 'Nothing to share yet' using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_chat_shares" ("chat_id", "token_hash", "leaf_id", "created_by")
  values (v_chat."id", encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_leaf, auth.uid())
  returning "id", "created_at" into v_id, v_created;
  perform better_supabase.audit_event(
    event_type => 'ai_chat.shared',
    category => 'ai',
    target_type => 'ai_chat_share',
    record_id => v_id::text,
    tenant => (v_chat."organization_id")::uuid,
    metadata => jsonb_build_object('chatId', v_chat."id", 'shareId', v_id, 'organizationId', v_chat."organization_id"::text, 'ownerId', v_chat."owner_id", 'leafId', v_leaf),
    idempotency_key => 'ai_chat.shared:' || v_id::text
  );
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf, 'created_at', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_conversation (
  inbox uuid,
  input jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact "better_supabase"."contacts"%rowtype;
  v_conv "better_supabase"."conversations"%rowtype;
  v_staff boolean;
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from "better_supabase"."inboxes" where "id" = start_conversation.inbox and "archived_at" is null;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  -- A signed-in caller who names no contact on a widget inbox is the
  -- visitor, staff included, so they can try their own widget.
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (select auth.uid()) is not null and not (input ? 'contact')
    and v_inbox."channel" = 'in_app' and coalesce((v_inbox."settings" ->> 'widget')::boolean, false) then
    v_staff := false;
    v_contact_input := jsonb_build_object(
      'user_id', (select auth.uid()),
      'name', v_contact_input ->> 'name',
      'email', coalesce((select auth.jwt()) ->> 'email', v_contact_input ->> 'email')
    );
  elsif coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_inbox."tenant_id", 'inbox.reply'), false) then
    v_staff := true;
    if jsonb_typeof(input -> 'contact') = 'string' then
      v_contact_input := jsonb_build_object('id', input ->> 'contact');
    end if;
    if v_contact_input = '{}'::jsonb then
      raise exception 'input.contact is required' using errcode = '22023', hint = 'CONTACT_REQUIRED';
    end if;
  else
    raise exception 'not allowed to open a conversation in this inbox' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
  insert into "better_supabase"."conversations" ("tenant_id", "inbox_id", "contact_id", "subject", "priority", "bot_mode", "thread_id", "assignee_id", "metadata")
  values (
    v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox."bot_mode"), input ->> 'thread_id',
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_conv."thread_id" is null then
    update "better_supabase"."conversations" set "thread_id" = 'inbox:' || "id"::text
    where "id" = v_conv."id"
    returning * into v_conv;
  end if;
  insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), '{}'::jsonb);
  null;
  if input ? 'message' then
    perform "better_supabase"."inbox_add_message"(
      v_conv."id",
      case when jsonb_typeof(input -> 'message') = 'string' then jsonb_build_object('body', input ->> 'message') else input -> 'message' end,
      case when v_staff then (case when (select auth.uid()) is null then 'bot' else 'agent' end) else 'contact' end,
      (select auth.uid()),
      case when v_staff then 'outbound' else 'inbound' end
    );
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.switch_organization (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if me is null or not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}') || jsonb_build_object('tenant_id', organization::text)
  where id = me;
  update "public"."memberships" set "last_used_at" = now() where "organization_id" = organization and "user_id" = me;
  null;
  return jsonb_build_object('organization_id', organization, 'refresh', true);
end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.transfer_ownership'), false)) then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (
    select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me and m."role" = 'owner'
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (former_role = any (array['owner', 'admin', 'member']::text[])) then
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
      when m."user_id" = new_owner then 'owner'
      else former_role
    end
  where m."organization_id" = organization
    and (m."user_id" = new_owner
      or (me is not null and me <> new_owner and m."user_id" = me and m."role" = 'owner'));
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, new_owner, 'owner';
    end if;
  end;
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

CREATE OR REPLACE FUNCTION better_supabase.unregister_push_device (
  token text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  delete from "better_supabase"."push_devices" x
  where x."token" = unregister_push_device.token
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."user_id" = v_user)
  returning x."id", x."user_id" into v_id, v_user;
  if v_id is null then
    return false;
  end if;
  perform better_supabase.audit_event(
    event_type => 'push.device_unregistered',
    category => 'security',
    target_type => 'push_device',
    record_id => v_id::text,
    metadata => jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text)
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
begin
  if invitee_email is not null and btrim(invitee_email) = '' then
    raise exception 'The email address is empty' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  select * into current_invite from "better_supabase"."invitations" i
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  for update;
  if current_invite."id" is null then
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
  if invitee_role is not null and not (invitee_role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and (
    not better_supabase.can_assign(tenant, current_invite."role"::text)
    or (invitee_role is not null and not better_supabase.can_assign(tenant, (invitee_role)::text))
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
      updated."role" := invitee_role;
    end if;
    update "better_supabase"."invitations" i
    set "email" = updated."email",
      "role" = updated."role"
    where i."id" = invitation_id
    returning * into updated;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select m."role", m."role"::text into previous, previous_assignable
  from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever sql.modules.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, (role)::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "public"."memberships" set "role" = role
  where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
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

CREATE OR REPLACE FUNCTION better_supabase.update_organization (
  organization uuid,
  attrs        jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.update'), false) then
    raise exception 'Not allowed to update the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if attrs ? 'slug' then
    case "better_supabase"."organization_slug_problem"(attrs ->> 'slug', organization)
      when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
      when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
      when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
      else null;
    end case;
  end if;
  update "public"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  perform better_supabase.audit_event(
    event_type => 'organization.updated',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', auth.uid())
  );
  return true;
end;
$function$;

CREATE TRIGGER bs_record_organization_setting
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.organization_settings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.record_organization_setting();

CREATE TRIGGER bs_record_platform_setting
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.platform_settings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.record_platform_setting();

REVOKE ALL ON FUNCTION "better_supabase"."record_organization_setting"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."record_platform_setting"() FROM PUBLIC;
