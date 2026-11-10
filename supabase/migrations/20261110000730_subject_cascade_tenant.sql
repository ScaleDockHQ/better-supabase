SET local check_function_bodies = off;

DROP TRIGGER "bsb_attachments_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_reactions_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_attachments_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bsb_reactions_product_cascade" ON "better_supabase"."products";

CREATE OR REPLACE FUNCTION better_supabase.attachments_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
  v_tenant text := case when tg_nargs > 2 then to_jsonb(old) ->> tg_argv[2] end;
begin
  if v_tenant is null then
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
  v_tenant text := case when tg_nargs > 2 then to_jsonb(old) ->> tg_argv[2] end;
begin
  if v_tenant is null then
    delete from "better_supabase"."conversations" c where c."kind" = 'subject' and c."subject_type" = v_type and c."subject_id" = v_id;
  else
    delete from "better_supabase"."conversations" c where c."kind" = 'subject' and c."subject_type" = v_type and c."subject_id" = v_id and c."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reactions_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
  v_tenant text := case when tg_nargs > 2 then to_jsonb(old) ->> tg_argv[2] end;
begin
  if v_tenant is null then
    delete from "better_supabase"."reactions" r where r."subject_type" = v_type and r."subject_id" = v_id;
  else
    delete from "better_supabase"."reactions" r where r."subject_type" = v_type and r."subject_id" = v_id and r."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE TRIGGER bsb_attachments_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachments_subject_deleted('product_variant', 'id', 'tenant_id');

CREATE TRIGGER bsb_reactions_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_subject_deleted('product_variant', 'id', 'tenant_id');

CREATE TRIGGER bsb_attachments_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachments_subject_deleted('product', 'id', 'tenant_id');

CREATE TRIGGER bsb_reactions_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_subject_deleted('product', 'id', 'tenant_id');
