SET local check_function_bodies = off;

DROP INDEX "better_supabase"."attachments_object_idx";

ALTER TABLE "better_supabase"."attachments"
  DROP COLUMN "object_path";

ALTER TABLE "better_supabase"."attachments"
  ADD COLUMN "object_path" text;

-- Postgres 17 logical replication skips generated columns, so a trigger fills
-- object_path from now on; existing rows need it written once.
UPDATE "better_supabase"."attachments"
  SET "object_path" = "organization_id"::text || '/attachments/' || "id"::text;

CREATE OR REPLACE FUNCTION better_supabase.attachment_object_path()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  select "organization_id"::text || '/attachments/' || "id"::text into new."object_path" from (select new.*) as r;
  return new;
end;
$function$;

CREATE VIEW "api"."notification_preferences" WITH (security_invoker=true) AS  SELECT id,
    user_id,
    organization_id,
    type,
    channel,
    enabled,
    created_at,
    updated_at
   FROM better_supabase.notification_preferences;

CREATE VIEW "api"."notification_recipients" WITH (security_invoker=true) AS  SELECT id,
    event_id,
    organization_id,
    user_id,
    read_at,
    dismissed_at,
    resolved_at,
    resolution,
    delivered_at,
    created_at
   FROM better_supabase.notification_recipients;

CREATE UNIQUE INDEX attachments_object_idx ON better_supabase.attachments USING btree (bucket, object_path);

CREATE TRIGGER bsb_attachments_object_path
  BEFORE INSERT OR UPDATE ON better_supabase.attachments
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachment_object_path();

COMMENT ON COLUMN "better_supabase"."attachments"."object_path" IS 'better-supabase path: {organization_id}/attachments/{id}';

REVOKE ALL ON FUNCTION "better_supabase"."attachment_object_path"() FROM PUBLIC;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "api"."notification_preferences" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "api"."notification_preferences" TO "service_role";

GRANT SELECT ON TABLE "api"."notification_recipients" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "api"."notification_recipients" TO "service_role";
