-- Attachments broadcast changed to attachments:<tenant> when a tenant's file
-- changes; the tenant's readers may join the topic.

CREATE OR REPLACE FUNCTION better_supabase.attachments_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row "better_supabase"."attachments"%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  if v_row."organization_id" is null then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'attachments:' || v_row."organization_id"::text, true);
  end if;
  return null;
end;
$function$;

CREATE TRIGGER bsb_attachments_changed AFTER INSERT OR DELETE OR UPDATE ON better_supabase.attachments FOR EACH ROW EXECUTE FUNCTION better_supabase.attachments_changed();

CREATE POLICY "bsb_attachments_receive" ON "realtime"."messages" FOR SELECT TO "authenticated" USING (((extension = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'attachments:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 13) IN ( SELECT (x.x)::text AS x
   FROM better_supabase.tenant_ids_with('attachments.read'::text) x(x)))));

REVOKE ALL ON FUNCTION "better_supabase"."attachments_changed"() FROM PUBLIC;
