SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."replace_equivalent_triggers"(regclass, text, text, boolean);

DROP TABLE "better_supabase"."block_modules";

CREATE TABLE "better_supabase"."modules" (
  "name"         text                     NOT NULL,
  "version"      integer                  NOT NULL,
  "mode"         text                     NOT NULL,
  "installed_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "modules_pkey" PRIMARY KEY (name)
);

ALTER TABLE "better_supabase"."modules"
  ENABLE ROW LEVEL SECURITY;

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

REVOKE ALL ON FUNCTION "better_supabase"."replace_equivalent_triggers"(regclass, text, text, boolean) FROM PUBLIC;

GRANT SELECT ON TABLE "better_supabase"."modules" TO "service_role";
