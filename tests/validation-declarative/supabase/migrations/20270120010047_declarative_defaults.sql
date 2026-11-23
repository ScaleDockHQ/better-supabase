SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."declared_defaults" (
  "kind"     text    NOT NULL,
  "subject"  text    NOT NULL,
  "key"      text    NOT NULL,
  "position" integer NOT NULL DEFAULT 0,
  "value"    jsonb   NOT NULL,
  CONSTRAINT "declared_defaults_pkey" PRIMARY KEY (kind, subject, key)
);

ALTER TABLE "better_supabase"."declared_defaults"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION better_supabase.declared_defaults_of (
  kind    text,
  subject text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_agg(d.value order by d.position, d.key)
  from better_supabase.declared_defaults d
  where d.kind = declared_defaults_of.kind and d.subject = declared_defaults_of.subject
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
    when 'permissions.explain' then 'members.read'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
  end
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."declared_defaults_of"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."declared_defaults_of"(text, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."declared_defaults" TO "service_role";
