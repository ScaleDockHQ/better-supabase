SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_scheduler()
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
  v_found boolean := false;
begin
  if v_jobs is not null then
    execute pg_catalog.format('select exists (select 1 from %s where jobname = ''better-supabase-maintenance'')', v_jobs) into v_found;
  end if;
  return case when v_found then 'pg_cron' else 'none' end;
end;
$function$;

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
  insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
  select p_tenant, 'nonconformity', 'Nonconformity', 'NC', null, true, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'nonconformity');
  insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
  select p_tenant, 'complaint', 'Complaint', 'CMP', null, true, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'complaint');
  insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
  select p_tenant, 'incident', 'Incident', 'INC', null, true, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'incident');
  insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
  select p_tenant, 'near_miss', 'Near miss', 'NM', null, true, false, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'near_miss');
  insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
  select p_tenant, 'observation', 'Observation', 'OBS', null, false, false, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'observation');
  insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
  select p_tenant, 'improvement', 'Improvement', 'IMP', null, false, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'improvement');
  insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
  select p_tenant, 'change', 'Change request', 'CHG', null, false, true, false, true
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'change');
  insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "effectiveness_after_days", "requires_root_cause", "requires_actions", "requires_effectiveness", "requires_revisions")
  select p_tenant, 'finding', 'Audit finding', 'FND', null, true, true, false, false
  where not exists (select 1 from "better_supabase"."case_kinds" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'finding');
end;
$function$;

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
  insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
  select p_tenant, 'default', 'Default 5x5', '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb, '[{"value":1,"label":"Insignificant"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb, '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb, 'product', (not exists (select 1 from "better_supabase"."risk_matrices" d where d."tenant_id" = p_tenant and d."is_default"))
  where not exists (select 1 from "better_supabase"."risk_matrices" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'default');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_tax_defaults (
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
  if p_locale = any (array['nl']) then
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'NL21', 'BTW hoog 21%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'NL21');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'NL9', 'BTW laag 9%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'NL9');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'NL0', 'BTW 0%', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'NL0');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'NLVRIJ', 'Vrijgesteld van BTW', 'exempt'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'NLVRIJ');
  end if;
  if p_locale = any (array['nl']) then
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'NL21' limit 1), 2100
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'NL21' limit 1));
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'NL9' limit 1), 900
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'NL9' limit 1));
  end if;
  if p_locale = any (array['de']) then
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'DE19', 'Umsatzsteuer 19%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'DE19');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'DE7', 'Umsatzsteuer 7%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'DE7');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'DE0', 'Umsatzsteuer 0%', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'DE0');
  end if;
  if p_locale = any (array['de']) then
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'DE19' limit 1), 1900
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'DE19' limit 1));
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'DE7' limit 1), 700
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'DE7' limit 1));
  end if;
  if p_locale = any (array['fr']) then
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'FR20', 'TVA 20%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'FR20');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'FR10', 'TVA 10%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'FR10');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'FR55', 'TVA 5,5%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'FR55');
    insert into "better_supabase"."tax_codes" ("tenant_id", "code", "name", "type")
    select p_tenant, 'FR0', 'TVA 0%', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" is not distinct from 'FR0');
  end if;
  if p_locale = any (array['fr']) then
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR20' limit 1), 2000
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR20' limit 1));
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR10' limit 1), 1000
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR10' limit 1));
    insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps")
    select p_tenant, (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR55' limit 1), 550
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."tenant_id" = p_tenant and x."tax_code_id" is not distinct from (select x."id" from "better_supabase"."tax_codes" x where x."tenant_id" = p_tenant and x."code" = 'FR55' limit 1));
  end if;
end;
$function$;

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.appraisal_competencies DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "appraisal_competency", "event_prefix": "appraisal_competency"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.appraisal_review_ratings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "appraisal_review_rating", "event_prefix": "appraisal_review_rating"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bin_slots DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "bin_slot", "event_prefix": "bin_slot"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.prescriptions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "prescription", "event_prefix": "prescription"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.putaway_rules DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "putaway_rule", "event_prefix": "putaway_rule"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.variant_sizes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "variant_size", "event_prefix": "variant_size"}');
