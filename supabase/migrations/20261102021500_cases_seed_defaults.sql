SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.seed_cases_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."seed_cases_defaults"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_cases_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into "better_supabase"."case_kinds" ("""tenant_id""", """key""", """name""", """prefix""", """effectiveness_after_days""", """requires_root_cause""", """requires_actions""", """requires_effectiveness""", """requires_revisions""")
  select p_tenant, 'nonconformity', 'Nonconformity', 'NC', null, true, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."""tenant_id""" = p_tenant and x."""key""" is not distinct from 'nonconformity');
  insert into "better_supabase"."case_kinds" ("""tenant_id""", """key""", """name""", """prefix""", """effectiveness_after_days""", """requires_root_cause""", """requires_actions""", """requires_effectiveness""", """requires_revisions""")
  select p_tenant, 'complaint', 'Complaint', 'CMP', null, true, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."""tenant_id""" = p_tenant and x."""key""" is not distinct from 'complaint');
  insert into "better_supabase"."case_kinds" ("""tenant_id""", """key""", """name""", """prefix""", """effectiveness_after_days""", """requires_root_cause""", """requires_actions""", """requires_effectiveness""", """requires_revisions""")
  select p_tenant, 'incident', 'Incident', 'INC', null, true, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."""tenant_id""" = p_tenant and x."""key""" is not distinct from 'incident');
  insert into "better_supabase"."case_kinds" ("""tenant_id""", """key""", """name""", """prefix""", """effectiveness_after_days""", """requires_root_cause""", """requires_actions""", """requires_effectiveness""", """requires_revisions""")
  select p_tenant, 'near_miss', 'Near miss', 'NM', null, true, false, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."""tenant_id""" = p_tenant and x."""key""" is not distinct from 'near_miss');
  insert into "better_supabase"."case_kinds" ("""tenant_id""", """key""", """name""", """prefix""", """effectiveness_after_days""", """requires_root_cause""", """requires_actions""", """requires_effectiveness""", """requires_revisions""")
  select p_tenant, 'observation', 'Observation', 'OBS', null, false, false, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."""tenant_id""" = p_tenant and x."""key""" is not distinct from 'observation');
  insert into "better_supabase"."case_kinds" ("""tenant_id""", """key""", """name""", """prefix""", """effectiveness_after_days""", """requires_root_cause""", """requires_actions""", """requires_effectiveness""", """requires_revisions""")
  select p_tenant, 'improvement', 'Improvement', 'IMP', null, false, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."""tenant_id""" = p_tenant and x."""key""" is not distinct from 'improvement');
  insert into "better_supabase"."case_kinds" ("""tenant_id""", """key""", """name""", """prefix""", """effectiveness_after_days""", """requires_root_cause""", """requires_actions""", """requires_effectiveness""", """requires_revisions""")
  select p_tenant, 'change', 'Change request', 'CHG', null, false, true, false, true
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."""tenant_id""" = p_tenant and x."""key""" is not distinct from 'change');
  insert into "better_supabase"."case_kinds" ("""tenant_id""", """key""", """name""", """prefix""", """effectiveness_after_days""", """requires_root_cause""", """requires_actions""", """requires_effectiveness""", """requires_revisions""")
  select p_tenant, 'finding', 'Audit finding', 'FND', null, true, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."""tenant_id""" = p_tenant and x."""key""" is not distinct from 'finding');
end;
$function$;

REVOKE ALL ON FUNCTION "api"."seed_cases_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."seed_cases_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_cases_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_cases_defaults"(uuid, text, text) TO "service_role";
