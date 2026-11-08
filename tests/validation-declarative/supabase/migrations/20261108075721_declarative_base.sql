SET local check_function_bodies = off;

CREATE SCHEMA "better_supabase";

CREATE TABLE "better_supabase"."blocks" (
  "name"         text                     NOT NULL,
  "block"        text,
  "version"      integer                  NOT NULL,
  "mode"         text                     NOT NULL,
  "installed_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "blocks_pkey" PRIMARY KEY (name)
);

ALTER TABLE "better_supabase"."blocks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."memberships" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "role"            text                     NOT NULL DEFAULT 'member'::text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "invited_by"      uuid,
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "last_used_at"    timestamp with time zone,
  CONSTRAINT "memberships_organization_user_key" UNIQUE (organization_id, user_id),
  CONSTRAINT "memberships_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."memberships"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."memberships" FROM "anon";

CREATE TABLE "public"."organizations" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "name"        text                     NOT NULL,
  "slug"        text                     NOT NULL,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "created_by"  uuid,
  "disabled_at" timestamp with time zone,
  "deleted_at"  timestamp with time zone,
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "organizations_pkey" PRIMARY KEY (id),
  CONSTRAINT "organizations_slug_format" CHECK ((slug ~ '^[a-z0-9-]+$'::text))
);

ALTER TABLE "public"."organizations"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."organizations" FROM "anon";

CREATE TABLE "public"."profiles" (
  "user_id"                uuid                     NOT NULL,
  "display_name"           text,
  "created_at"             timestamp with time zone NOT NULL DEFAULT now(),
  "email"                  text,
  "username"               text,
  "full_name"              text,
  "first_name"             text,
  "last_name"              text,
  "avatar_url"             text,
  "active_organization_id" uuid,
  "active_team_id"         uuid,
  "onboarding"             jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "disabled_at"            timestamp with time zone,
  "updated_at"             timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "profiles_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "public"."profiles"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."profiles" FROM "anon";

CREATE TABLE "public"."projects" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "name"            text                     NOT NULL,
  "archived_at"     timestamp with time zone,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "projects_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."projects"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."projects" FROM "anon";

CREATE OR REPLACE FUNCTION better_supabase.acting_member()
  RETURNS uuid
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  header text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    return null;
  end if;
  header := nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-bsb-actor';
  return case when header ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then header::uuid end;
exception when others then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.actor_may_write()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.allocate_username (
  base    text,
  user_id uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 28);
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, 28);
  end if;
  if length(stem) < 3 then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www']) or exists (
    select 1 from "public"."profiles" p
    where lower(p."username") = candidate and p."user_id" is distinct from user_id
  ) loop
    n := n + 1;
    candidate := stem || n::text;
  end loop;
  return candidate;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.as_column_type (
  value  text,
  target anyelement
)
  RETURNS anyelement
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return value;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.backfill_profiles()
  RETURNS integer
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select count(*)::integer from auth.users u where "better_supabase"."sync_profile"(u.id)
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
  COST 1000
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
    and not exists (
      select 1 from unnest(better_supabase.role_permissions(can_assign_as.role)) k(key) where true
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

CREATE OR REPLACE FUNCTION better_supabase.column_default (
  relation text,
  name     text,
  target   anyelement
)
  RETURNS anyelement
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  result alias for $0;
  v_default text;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid) into v_default
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid = pg_catalog.to_regclass(column_default.relation) and a.attname = column_default.name and not a.attisdropped;
  if v_default is not null then
    execute 'select ' || v_default into result;
  end if;
  return result;
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
  insert into "public"."organizations" ("name", "slug", "created_by")
  select r."name", r."slug", owner
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  returning "id" into organization;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (organization, owner, 'owner');
  perform "better_supabase"."seed_tenant_defaults"(organization);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  null;
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
  select coalesce(
    (select m."organization_id"::text from "public"."memberships" m where m."organization_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "public"."memberships" m where m."organization_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "public"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
  )::uuid
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.delete'), false) then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  delete from "public"."organizations" where "id" = organization;
  if not found then
    return false;
  end if;
  delete from "public"."memberships" where "organization_id" = organization;
  null;
  return true;
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
      select 1 from "public"."memberships" m where m."organization_id" = old."organization_id" and m."role" = 'owner'
    ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_membership()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if not (current_user in ('anon', 'authenticated')) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new."role" is not distinct from old."role" then
    return new;
  end if;
  perform "better_supabase"."guard_membership_role"(
    new."organization_id", new."user_id", new."role"::text,
    case when tg_op = 'UPDATE' then old."organization_id" end,
    case when tg_op = 'UPDATE' then old."role"::text end
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_membership_role (
  target_tenant   uuid,
  target_member   uuid,
  target_role     text,
  previous_tenant uuid,
  previous_role   text
)
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if target_member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(target_tenant, target_role::text)
    or (previous_tenant is not null and not better_supabase.can_assign(previous_tenant, previous_role::text)) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_profile()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if current_user in ('authenticated', 'anon') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and (
    new."user_id" is distinct from old."user_id"
    or new."email" is distinct from old."email"
    or new."disabled_at" is distinct from old."disabled_at"
    or new."active_organization_id" is distinct from old."active_organization_id"
    or new."active_team_id" is distinct from old."active_team_id"
    or new."created_at" is distinct from old."created_at"
  ) then
    raise exception 'These profile columns are managed by the service' using errcode = '42501', hint = 'PROFILE_COLUMN_READONLY';
  end if;
  return new;
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
      and (has_organization_role.roles is null or m."role" = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."organization_id")
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_run()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_members (
  organization uuid
)
  RETURNS TABLE (
    user_id uuid,
    role    text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'members.read'), false) then
    raise exception 'Not allowed to list members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select m."user_id", m."role"::text
  from "public"."memberships" m
  where m."organization_id" = organization
  order by m."user_id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_my_organizations()
  RETURNS TABLE (
    id   uuid,
    name text,
    slug text,
    role text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select o."id", o."name", o."slug", m."role"::text
  from "public"."memberships" m
  join "public"."organizations" o on o."id" = m."organization_id"
  where m."user_id" = (select auth.uid()) and o."deleted_at" is null and o."disabled_at" is null
    and not better_supabase.tenant_disabled(o."id")
  order by o."name"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_used (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "public"."memberships" set "last_used_at" = now()
  where "organization_id" = organization and "user_id" = auth.uid();
  return found;
end;
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
        and better_supabase.role_grants(m."role", member_can.permission)
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
        and better_supabase.role_grants(m."role", member_can_while_deleting.permission)
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
    and (member_organization_ids.roles is null or m."role" = any (member_organization_ids.roles))
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
  select coalesce((
      select better_supabase.role_permissions(m."role") from "public"."memberships" m
      where m."organization_id" = member_permissions.tenant and m."user_id" = member_permissions.member
    ), '{}'::text[])
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
      'roles', jsonb_build_array(m."role")
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "public"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id")
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memo_get (
  key text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select nullif(pg_catalog.current_setting('better_supabase.memo.' || key, true), '')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memo_set (
  key   text,
  value text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select pg_catalog.set_config('better_supabase.memo.' || key, value, true)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_subject_refs (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_fn regproc;
begin
  for v_fn in
    select p.oid::regproc
    from pg_catalog.pg_proc p
    join pg_catalog.pg_description d on d.objoid = p.oid and d.classoid = 'pg_catalog.pg_proc'::regclass and d.objsubid = 0
    where d.description = 'better-supabase:subject-merge'
      -- Only the owner's functions, so a marked function in a schema another
      -- role can write to never runs with this function's rights.
      and p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)
    order by p.oid::regproc::text
  loop
    execute format('select %s($1, $2, $3)', v_fn) using subject_table, keep, drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mirror_profile_email()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "public"."profiles" set "email" = lower(new.email) where "user_id" = new.id and "email" is distinct from lower(new.email);
  return new;
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

CREATE OR REPLACE FUNCTION better_supabase.my_profile()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select to_jsonb(p) from "public"."profiles" p where p."user_id" = (select auth.uid())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.on_auth_user_created()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- A failure here would abort the sign-up. The user gets an account
  -- without a profile instead, and backfill_profiles() creates it later.
  begin
    perform "better_supabase"."sync_profile"(new.id);
  exception when others then
    raise warning 'No profile for user %: % (SQLSTATE %). Run backfill_profiles() once it is fixed.',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
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
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
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
  select m."role" from "public"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member
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
  select array[m."role"]::text[]
  from "public"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_overview (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_org jsonb;
  v_seats integer;
begin
  select to_jsonb(o) into v_org
  from "better_supabase"."list_my_organizations"() o
  where o.id = organization_overview.organization;
  if v_org is null then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  
  return jsonb_build_object(
    'id', v_org ->> 'id',
    'name', v_org ->> 'name',
    'slug', v_org -> 'slug',
    'role', v_org ->> 'role',
    'seats', v_seats,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', m.user_id, 'role', m.role,
        'roles', coalesce(to_jsonb(m) -> 'roles', jsonb_build_array(m.role)),
        'disabledAt', to_jsonb(m) -> 'disabled_at')
        order by m.user_id)
      from "better_supabase"."list_members"(organization_overview.organization) m
    ), '[]'::jsonb),
    'invitations', '[]'::jsonb
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_slug_problem (
  value               text,
  except_organization uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when value is null then null
    when length(value) < 2 or length(value) > 48 or value !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when false then 'reserved'
    when exists (
      select 1 from "public"."organizations" o
      where lower(o."slug"::text) = lower(value) and o."deleted_at" is null
        and o."id" is distinct from except_organization
    ) then 'taken'
  end
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

CREATE OR REPLACE FUNCTION better_supabase.permission_claims (
  user_id uuid,
  tenant  uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when permission_claims.tenant is null then '{}'::jsonb
    else coalesce(jsonb_strip_nulls(jsonb_build_object(permission_claims.tenant::text, to_jsonb(better_supabase.member_permissions(permission_claims.user_id, permission_claims.tenant)))), '{}'::jsonb)
  end
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
    and ((platform_can.member = auth.uid() and exists (
    select 1
    from jsonb_array_elements_text(
      case when jsonb_typeof(coalesce(auth.jwt() -> 'platform_permissions', auth.jwt() -> 'app_metadata' -> 'platform_permissions')) = 'array'
        then coalesce(auth.jwt() -> 'platform_permissions', auth.jwt() -> 'app_metadata' -> 'platform_permissions')
        else '[]'::jsonb end
    ) g(key)
    where better_supabase.permission_matches(g.key, platform_can.permission)
  )))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.raise_actor_readonly()
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.replace_equivalent_triggers (
  target          regclass,
  module_trigger  text,
  pattern         text,
  replace_trigger boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.module_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, module_trigger;
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_grants (
  role       text,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from unnest(better_supabase.role_permissions(role)) g(key)
    where better_supabase.permission_matches(g.key, permission)
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_permissions (
  role text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case role
    when 'owner' then array['*']::text[]
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.export', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'agents.*', 'ai_files.*', 'ai_keys.*', 'ai_schedules.*', 'connectors.*', 'knowledge.*', 'memory.*', 'tags.*', 'teams.*', 'subjects.*', 'custom_fields.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_entries.*', 'service_accounts.*', 'pipelines.*', 'option_sets.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'legal_entities.*', 'document_templates.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*', 'qualifications.*', 'risks.*', 'advisories.*', 'shifts.*', 'consents.*', 'waitlist.invite', 'accounting.*', 'observations.*', 'medications.*', 'care_plans.*', 'cases.*', 'inspections.*', 'meetings.*', 'maintenance.*', 'dam.*', 'lims.*', 'appraisals.*', 'warehouse.*', 'rfqs.*', 'tills.*', 'periods.*', 'deadlines.*', 'commissions.*', 'referrals.*', 'agent_checkout.*', 'clinical_decision_support.*', 'e_prescribing.*', 'manufacturing.*', 'banking.*', 'tax.*', 'funding.*', 'payroll_export.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'agents.read', 'agents.write', 'agents.publish', 'ai_files.upload', 'ai_keys.use', 'ai_schedules.write', 'connectors.read', 'connectors.use', 'knowledge.read', 'knowledge.write', 'memory.read', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_entries.track', 'leave.request', 'pipelines.read', 'option_sets.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'acknowledgements.acknowledge', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'shifts.read', 'shifts.request', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'legal_entities.read', 'document_templates.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read', 'risks.read', 'advisories.read', 'observations.read', 'observations.record', 'care_plans.read', 'cases.read', 'cases.create', 'manufacturing.read', 'manufacturing.produce', 'banking.read', 'banking.reconcile', 'tax.read', 'funding.read', 'funding.register']::text[]
    when 'viewer' then array['organization.read']::text[]
    else '{}'::text[]
  end
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

CREATE OR REPLACE FUNCTION better_supabase.seed_tenant_defaults (
  p_tenant   uuid,
  p_variants jsonb DEFAULT '{}'::jsonb,
  p_locale   text  DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  -- The default column is assigned directly; jsonb_populate_record copies the
  -- whole row, so it only serves other column names.
  if tg_nargs = 0 or tg_argv[0] = 'updated_at' then
    new.updated_at := now();
  else
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[0], now()));
  end if;
  return new;
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null or not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  -- The server's tenant resolver picks the tenant per request.
  update "public"."memberships" set "last_used_at" = now() where "organization_id" = organization and "user_id" = me;
  null;
  return jsonb_build_object('organization_id', organization, 'refresh', false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sync_profile (
  user_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  u auth.users;
  meta jsonb;
  created boolean := false;
  attempt integer := 0;
begin
  select * into u from auth.users where id = user_id;
  if not found then
    return false;
  end if;
  meta := coalesce(u.raw_user_meta_data, '{}');
  if not exists (select 1 from "public"."profiles" p where p."user_id" = user_id) then
    loop
      begin
        insert into "public"."profiles" ("user_id", "full_name", "first_name", "last_name", "avatar_url", "email", "username")
        values (user_id, coalesce(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), nullif(concat_ws(' ', nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), '')), '')), coalesce(nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1), '')), coalesce(nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), nullif(btrim(substr(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), length(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1)) + 1)), '')), nullif(btrim(coalesce(meta ->> 'avatar_url', meta ->> 'picture')), ''), lower(u.email), "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "public"."profiles" p where p."user_id" = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_sync"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using user_id;
      end if;
    end;
  end if;
  return created;
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
    and better_supabase.role_grants(m."role", tenant_ids_with.permission)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.track_updated_at (
  target          regclass,
  column_name     text     DEFAULT 'updated_at'::text,
  replace_trigger boolean  DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.replace_equivalent_triggers(
    target, 'bsb_updated_at', 'updated_at|moddatetime|touch', replace_trigger
  );
  execute format('drop trigger if exists bsb_updated_at on %s', target);
  execute format(
    'create trigger bsb_updated_at before update on %s for each row execute function better_supabase.set_updated_at(%L)',
    target,
    column_name
  );
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (former_role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
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
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.try_column_type (
  value  text,
  target anyelement
)
  RETURNS anyelement
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  result alias for $0;
begin
  result := value;
  return result;
exception when data_exception or check_violation then
  return null;
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
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select m."role", m."role"::text into previous, previous_assignable
  from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever blocks.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and coalesce(member = auth.uid(), false) then
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
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_my_profile (
  attrs jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  updated integer;
  v_caller uuid := (select auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_profile_update"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, v_caller;
    end if;
  end;
  update "public"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."user_id" = v_caller;
  get diagnostics updated = row_count;
  if updated > 0 then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_update"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using v_caller;
      end if;
    end;
  end if;
  return updated > 0;
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  update "public"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  null;
  return true;
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

CREATE OR REPLACE FUNCTION better_supabase.value_unsupported (
  label text
)
  RETURNS text
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  raise exception 'the app does not support the value %', label
    using errcode = '22023', hint = 'VALUE_UNSUPPORTED';
end;
$function$;

CREATE OR REPLACE FUNCTION public.projects_reject_archived_rename()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if old.archived_at is not null and new.name <> old.name then
    raise exception 'an archived project cannot be renamed';
  end if;
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."projects_reject_archived_rename"() FROM "anon", "authenticated", "service_role";

ALTER TABLE "public"."memberships"
  ADD CONSTRAINT "memberships_invited_by_fkey" FOREIGN KEY (invited_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "public"."memberships"
  ADD CONSTRAINT "memberships_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."organizations"
  ADD CONSTRAINT "organizations_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "public"."memberships"
  ADD CONSTRAINT "memberships_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

ALTER TABLE "public"."profiles"
  ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."projects"
  ADD CONSTRAINT "projects_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

CREATE VIEW "public"."my_organizations" WITH (security_invoker=true) AS  SELECT id,
    name,
    slug
   FROM public.organizations o
  WHERE (id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids));

REVOKE ALL ON TABLE "public"."my_organizations" FROM "anon";

CREATE INDEX memberships_user_id_idx ON public.memberships USING btree (user_id);

CREATE INDEX organizations_created_by_idx ON public.organizations USING btree (created_by);

CREATE UNIQUE INDEX organizations_slug_idx ON public.organizations USING btree (lower(slug))
  WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX organizations_slug_key ON public.organizations USING btree (lower(slug));

CREATE UNIQUE INDEX profiles_username_idx ON public.profiles USING btree (lower(username));

CREATE INDEX projects_organization_id_idx ON public.projects USING btree (organization_id);

CREATE TRIGGER bsb_profile_email
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.mirror_profile_email();

CREATE TRIGGER bsb_profile_sync
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.on_auth_user_created();

CREATE CONSTRAINT TRIGGER bsb_organization_owner
  AFTER DELETE OR UPDATE OF ROLE, organization_id ON public.memberships DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ensure_organization_owner();

CREATE TRIGGER bsb_organization_role_guard
  BEFORE INSERT OR UPDATE ON public.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.guard_membership();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON public.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_profile_guard
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.guard_profile();

CREATE TRIGGER projects_reject_archived_rename
  BEFORE UPDATE ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION public.projects_reject_archived_rename();

CREATE POLICY "bsb_memberships_read" ON "public"."memberships"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids))));

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

CREATE POLICY "bsb_organizations_select" ON "public"."organizations"
  FOR SELECT
  TO "authenticated"
  USING ((id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_profiles_read" ON "public"."profiles"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bsb_profiles_update" ON "public"."profiles"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "projects_member_delete" ON "public"."projects"
  FOR DELETE
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids('{owner,admin}'::text[]) AS member_organization_ids)));

CREATE POLICY "projects_member_insert" ON "public"."projects"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids('{owner,admin}'::text[]) AS member_organization_ids)));

CREATE POLICY "projects_member_select" ON "public"."projects"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "projects_member_update" ON "public"."projects"
  FOR UPDATE
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids('{owner,admin}'::text[]) AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids('{owner,admin}'::text[]) AS member_organization_ids)));

COMMENT ON COLUMN "public"."memberships"."invited_by" IS 'The member who sent the invitation.';

REVOKE ALL ON FUNCTION "better_supabase"."acting_member"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."acting_member"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."actor_may_write"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."actor_may_write"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."allocate_username"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."allocate_username"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."as_column_type"(text, anyelement) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."as_column_type"(text, anyelement) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."backfill_profiles"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."backfill_profiles"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can"(text, uuid, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can_assign"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_assign"(uuid, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can_assign_as"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_assign_as"(uuid, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."can_user"(uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_user"(uuid, text, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."cap_allows"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cap_allows"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."column_default"(text, text, anyelement) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."create_organization"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_organization"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."current_tenant_id"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."current_tenant_id"() TO "anon", "authenticated", "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."delete_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ensure_organization_owner"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."guard_membership"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."guard_profile"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."has_organization_role"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."has_organization_role"(uuid, text[]) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_run"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_run"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."is_platform"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."is_platform"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."leave_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."leave_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_members"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_members"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_my_organizations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_my_organizations"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_used"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_used"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."member_can"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_can"(uuid, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."member_can_while_deleting"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_can_while_deleting"(uuid, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."member_organization_ids"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_organization_ids"(text[]) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."member_permissions"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_permissions"(uuid, uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."membership_claims"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."membership_claims"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."merge_subject_refs"(text, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."mirror_profile_email"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."my_permissions"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."my_permissions"(uuid, text[]) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."my_profile"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."my_profile"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."on_auth_user_created"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."operation_permission"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."operation_permission"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_member_role"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_member_role"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_member_roles"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_member_roles"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_overview"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_overview"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_slug_problem"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_slug_problem"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."permission_claims"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_claims"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."permission_claims"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_claims"(uuid, uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."permission_matches"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_matches"(text, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."platform_can"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."platform_can"(uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."raise_actor_readonly"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."raise_actor_readonly"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."replace_equivalent_triggers"(regclass, text, text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."role_grants"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."role_grants"(text, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."role_permissions"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."role_permissions"(text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."scope_permissions"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."scope_permissions"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_tenant_defaults"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_tenant_defaults"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."switch_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."switch_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sync_profile"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sync_profile"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_disabled"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_disabled"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_ids_with"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_ids_with"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."track_updated_at"(regclass, text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."transfer_ownership"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."transfer_ownership"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."try_column_type"(text, anyelement) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."try_column_type"(text, anyelement) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_member_role"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_member_role"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_my_profile"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_my_profile"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_organization"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_organization"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."user_disabled"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."user_disabled"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."value_unsupported"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."value_unsupported"(text) TO "anon", "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "public"."projects_reject_archived_rename"() TO PUBLIC;

REVOKE ALL ON FUNCTION "public"."projects_reject_archived_rename"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."projects_reject_archived_rename"() TO "postgres";

GRANT USAGE ON SCHEMA "better_supabase" TO "anon", "authenticated", "service_role", "supabase_auth_admin";

GRANT SELECT ON TABLE "better_supabase"."blocks" TO "service_role";

REVOKE ALL ON TABLE "public"."memberships" FROM "authenticated";

GRANT MAINTAIN, SELECT ON TABLE "public"."memberships" TO "authenticated";

REVOKE ALL ON TABLE "public"."memberships" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."memberships" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."memberships" TO "service_role";

REVOKE ALL ON TABLE "public"."organizations" FROM "authenticated";

GRANT MAINTAIN, SELECT ON TABLE "public"."organizations" TO "authenticated";

REVOKE ALL ON TABLE "public"."organizations" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."organizations" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."organizations" TO "service_role";

REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

GRANT MAINTAIN, SELECT ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ON TABLE "public"."profiles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "service_role";

REVOKE ALL ON TABLE "public"."projects" FROM "authenticated";

GRANT DELETE, INSERT, MAINTAIN, SELECT, UPDATE ON TABLE "public"."projects" TO "authenticated";

REVOKE ALL ON TABLE "public"."projects" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."projects" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."projects" TO "service_role";

REVOKE ALL ON TABLE "public"."my_organizations" FROM "authenticated";

GRANT MAINTAIN, SELECT ON TABLE "public"."my_organizations" TO "authenticated";

REVOKE ALL ON TABLE "public"."my_organizations" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."my_organizations" TO "postgres";

REVOKE ALL ON TABLE "public"."my_organizations" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."my_organizations" TO "service_role";
