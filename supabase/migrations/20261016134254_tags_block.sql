SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."taggings" (
  "tenant_id"    uuid                     NOT NULL,
  "tag_id"       uuid                     NOT NULL,
  "subject_type" text                     NOT NULL,
  "subject_id"   text                     NOT NULL,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "taggings_pkey" PRIMARY KEY (tag_id, subject_type, subject_id)
);

ALTER TABLE "better_supabase"."taggings"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."tags" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "kind"        text                     NOT NULL,
  "name"        text                     NOT NULL,
  "slug"        text                     NOT NULL,
  "color"       text,
  "description" text,
  "rank"        text                     COLLATE pg_catalog."C" NOT NULL DEFAULT 'V'::text,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "tags_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 80))),
  CONSTRAINT "tags_pkey" PRIMARY KEY (id),
  CONSTRAINT "tags_tenant_id_kind_slug_key" UNIQUE (tenant_id, kind, slug)
);

ALTER TABLE "better_supabase"."tags"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.create_tag (
  tenant      uuid,
  kind        text,
  name        text,
  color       text,
  description text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_tag"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.delete_tag (
  tag_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_tag"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_tags (
  tenant uuid,
  kind   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_tags"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.rank_tag (
  tag_id uuid,
  rank   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rank_tag"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.subject_tags (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_tags"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.tag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."tag"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.untag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."untag"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.update_tag (
  tag_id uuid,
  name   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_tag"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.create_tag (
  tenant      uuid,
  kind        text,
  name        text,
  color       text,
  description text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g'));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  select max(t."rank" collate "C") into v_last from "better_supabase"."tags" t
    where t."tenant_id" = create_tag.tenant and t."kind" = create_tag.kind;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."tags" ("tenant_id", "kind", "name", "slug", "color", "description", "rank", "created_at")
  values (create_tag.tenant, create_tag.kind, create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now())
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_tag (
  tag_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  delete from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_tags (
  tenant uuid,
  kind   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = list_tags.tenant
      and (list_tags.kind is null or t."kind" = list_tags.kind)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rank_tag (
  tag_id uuid,
  rank   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_tag.rank is null or rank_tag.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'TAG_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = rank_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" set "rank" = rank_tag.rank, "updated_at" = now() where "id" = rank_tag.tag_id;
  return true;
end;
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
    when 'owner' then array['*']
    when 'admin' then array[
      'customers.read', 'customers.write', 'reports.read',
      'organization.read', 'organization.update',
      'members.read', 'members.invite', 'members.remove', 'members.update_role',
      'billing.read', 'billing.manage', 'audit.read',
      'settings.read', 'settings.update', 'settings.manage',
      'api_keys.manage', 'api_keys.own',
      'comments.read', 'comments.create', 'comments.moderate', 'activity.read',
      'tags.read', 'tags.manage',
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish', 'workflow.admin',
      'inbox.read', 'inbox.reply', 'inbox.assign', 'inbox.manage',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_chat.admin',
      'ai.read', 'ai.create', 'ai.share', 'ai.admin'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'tags.read', 'onboarding.read', 'usage.read', 'usage.record', 'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'inbox.read', 'inbox.reply',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share',
      'ai.read', 'ai.create', 'ai.share'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_tags (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case subject_tags.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'customers.read'), false)
    else false
  end) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (case tag.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'customers.read'), false)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when 'customer' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.untag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (case untag.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'customers.read'), false)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings"
      where "tenant_id" = untag.tenant
        and "tag_id" = untag.tag_id
        and "subject_type" = untag.subject_type
        and "subject_id" = untag.subject_id;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_tag (
  tag_id uuid,
  name   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = update_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" t set "name" = coalesce(update_tag.name, t."name"), "updated_at" = now() where t."id" = update_tag.tag_id;
  null;
  return true;
end;
$function$;

ALTER TABLE "better_supabase"."taggings"
  ADD CONSTRAINT "taggings_tag_id_fkey" FOREIGN KEY (tag_id) REFERENCES better_supabase.tags(id) ON DELETE CASCADE;

REVOKE ALL ON FUNCTION "api"."create_tag"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_tag"(uuid, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_tag"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_tag"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_tags"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_tags"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rank_tag"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rank_tag"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."subject_tags"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."subject_tags"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."tag"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."tag"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."untag"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."untag"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_tag"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_tag"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_tag"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_tag"(uuid, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_tag"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_tag"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_tags"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_tags"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rank_tag"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rank_tag"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."subject_tags"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."subject_tags"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."tag"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tag"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."untag"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."untag"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_tag"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_tag"(uuid, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."taggings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."taggings" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."tags" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."tags" TO "service_role";
