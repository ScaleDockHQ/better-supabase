SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.seed_risks_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."seed_risks_defaults"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_risks_defaults (
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
  insert into "better_supabase"."risk_matrices" ("""tenant_id""", """key""", """name""", """likelihood_levels""", """impact_levels""", """bands""", """scoring""", """is_default""")
  select p_tenant, 'default', 'Default 5x5', '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb, '[{"value":1,"label":"Insignificant"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb, '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb, 'product', (not exists (select 1 from "better_supabase"."risk_matrices" d where d."""tenant_id""" = p_tenant and d."""is_default"""))
  where not exists (select 1 from "better_supabase"."risk_matrices" x where x."""tenant_id""" = p_tenant and x."""key""" is not distinct from 'default');
end;
$function$;

REVOKE ALL ON FUNCTION "api"."seed_risks_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."seed_risks_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_risks_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_risks_defaults"(uuid, text, text) TO "service_role";
