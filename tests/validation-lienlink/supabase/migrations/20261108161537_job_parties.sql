set lock_timeout = '5s';

SET local check_function_bodies = off;

DROP POLICY "bsb_attachments_select" ON "storage"."objects";

CREATE TABLE "public"."job_parties" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "job_id"          uuid                     NOT NULL,
  "organization_id" uuid                     NOT NULL,
  "name"            text                     NOT NULL,
  "role"            text                     NOT NULL DEFAULT 'owner'::text,
  "email"           text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "job_parties_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."job_parties"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."job_parties" FROM "anon";

CREATE OR REPLACE FUNCTION better_supabase.attachment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return attachment_subject_readable.subject_type is null or case attachment_subject_readable.subject_type
    when 'job' then exists (select 1 from "public"."jobs" s where s."id"::text = attachment_subject_readable.subject_id and s."organization_id" = attachment_subject_readable.tenant)
    else false
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachments_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'public.jobs' then array['job'] else '{}'::text[] end) loop
    update "better_supabase"."attachments" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

ALTER TABLE "public"."job_parties"
  ADD CONSTRAINT "job_parties_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES better_supabase.organizations(id) ON DELETE CASCADE;

ALTER TABLE "public"."jobs"
  ADD CONSTRAINT "jobs_id_organization_id_key" UNIQUE (id, organization_id);

ALTER TABLE "public"."job_parties"
  ADD CONSTRAINT "job_parties_job_id_organization_id_fkey" FOREIGN KEY (job_id, organization_id) REFERENCES public.jobs(id, organization_id) ON DELETE CASCADE;

CREATE INDEX job_parties_job_id_idx ON public.job_parties USING btree (job_id);

CREATE INDEX job_parties_organization_id_idx ON public.job_parties USING btree (organization_id);

CREATE POLICY "job_parties_member_delete" ON "public"."job_parties"
  FOR DELETE
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "job_parties_member_insert" ON "public"."job_parties"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "job_parties_member_select" ON "public"."job_parties"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "job_parties_member_update" ON "public"."job_parties"
  FOR UPDATE
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_attachments_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING
    (((bucket_id = 'attachments'::text) AND better_supabase.attachment_object_allowed(bucket_id, name, 'select'::text) AND better_supabase.attachment_object_visible(bucket_id,
    name)));

COMMENT ON FUNCTION "better_supabase"."attachments_subject_merge"(text, text, text) IS 'better-supabase:subject-merge';

COMMENT ON TABLE "public"."jobs" IS '@bsb subject type=job';

REVOKE ALL ON FUNCTION "better_supabase"."attachments_subject_merge"(text, text, text) FROM PUBLIC;

REVOKE ALL ON TABLE "public"."job_parties" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."job_parties" TO "authenticated";

REVOKE ALL ON TABLE "public"."job_parties" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."job_parties" TO "postgres";

REVOKE ALL ON TABLE "public"."job_parties" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."job_parties" TO "service_role";
