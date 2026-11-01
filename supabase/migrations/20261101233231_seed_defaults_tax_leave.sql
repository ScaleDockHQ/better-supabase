SET local check_function_bodies = off;

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
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'NL21', 'BTW hoog 21%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'NL21');
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'NL9', 'BTW laag 9%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'NL9');
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'NL0', 'BTW 0%', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'NL0');
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'NLVRIJ', 'Vrijgesteld van BTW', 'exempt'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'NLVRIJ');
  end if;
  if p_locale = any (array['nl']) then
    insert into "better_supabase"."tax_rates" ("""tenant_id""", """tax_code_id""", """rate_bps""")
    select p_tenant, (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'NL21' limit 1), 2100
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."""tenant_id""" = p_tenant and x."""tax_code_id""" is not distinct from (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'NL21' limit 1));
    insert into "better_supabase"."tax_rates" ("""tenant_id""", """tax_code_id""", """rate_bps""")
    select p_tenant, (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'NL9' limit 1), 900
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."""tenant_id""" = p_tenant and x."""tax_code_id""" is not distinct from (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'NL9' limit 1));
  end if;
  if p_locale = any (array['de']) then
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'DE19', 'Umsatzsteuer 19%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'DE19');
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'DE7', 'Umsatzsteuer 7%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'DE7');
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'DE0', 'Umsatzsteuer 0%', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'DE0');
  end if;
  if p_locale = any (array['de']) then
    insert into "better_supabase"."tax_rates" ("""tenant_id""", """tax_code_id""", """rate_bps""")
    select p_tenant, (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'DE19' limit 1), 1900
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."""tenant_id""" = p_tenant and x."""tax_code_id""" is not distinct from (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'DE19' limit 1));
    insert into "better_supabase"."tax_rates" ("""tenant_id""", """tax_code_id""", """rate_bps""")
    select p_tenant, (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'DE7' limit 1), 700
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."""tenant_id""" = p_tenant and x."""tax_code_id""" is not distinct from (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'DE7' limit 1));
  end if;
  if p_locale = any (array['fr']) then
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'FR20', 'TVA 20%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'FR20');
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'FR10', 'TVA 10%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'FR10');
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'FR55', 'TVA 5,5%', 'sales'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'FR55');
    insert into "better_supabase"."tax_codes" ("""tenant_id""", """code""", """name""", """type""")
    select p_tenant, 'FR0', 'TVA 0%', 'zero'
    where not exists (select 1 from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" is not distinct from 'FR0');
  end if;
  if p_locale = any (array['fr']) then
    insert into "better_supabase"."tax_rates" ("""tenant_id""", """tax_code_id""", """rate_bps""")
    select p_tenant, (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'FR20' limit 1), 2000
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."""tenant_id""" = p_tenant and x."""tax_code_id""" is not distinct from (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'FR20' limit 1));
    insert into "better_supabase"."tax_rates" ("""tenant_id""", """tax_code_id""", """rate_bps""")
    select p_tenant, (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'FR10' limit 1), 1000
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."""tenant_id""" = p_tenant and x."""tax_code_id""" is not distinct from (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'FR10' limit 1));
    insert into "better_supabase"."tax_rates" ("""tenant_id""", """tax_code_id""", """rate_bps""")
    select p_tenant, (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'FR55' limit 1), 550
    where not exists (select 1 from "better_supabase"."tax_rates" x where x."""tenant_id""" = p_tenant and x."""tax_code_id""" is not distinct from (select x."""id""" from "better_supabase"."tax_codes" x where x."""tenant_id""" = p_tenant and x."""code""" = 'FR55' limit 1));
  end if;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."seed_tax_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_tax_defaults"(uuid, text, text) TO "service_role";
