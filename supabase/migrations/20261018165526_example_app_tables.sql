CREATE TABLE "public"."projects" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "name"            text                     NOT NULL,
  "budget_minor"    bigint                   NOT NULL DEFAULT 0,
  "currency"        text                     NOT NULL DEFAULT 'EUR'::text,
  "lead_id"         uuid,
  "label_id"        uuid,
  CONSTRAINT "projects_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."projects"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."projects" FROM "anon";

CREATE TABLE "public"."saved_views" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  "name"       text                     NOT NULL,
  "filters"    jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT "saved_views_pkey" PRIMARY KEY (id),
  "user_id"    uuid                     DEFAULT auth.uid()
);

ALTER TABLE "public"."saved_views"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."saved_views" FROM "anon";

ALTER TABLE "public"."projects"
  ADD CONSTRAINT "projects_label_id_fkey" FOREIGN KEY (label_id) REFERENCES better_supabase.tags(id) ON DELETE SET NULL;

ALTER TABLE "public"."projects"
  ADD CONSTRAINT "projects_lead_id_fkey" FOREIGN KEY (lead_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "public"."projects"
  ADD CONSTRAINT "projects_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

CREATE INDEX projects_label_id_idx ON public.projects USING btree (label_id);

CREATE INDEX projects_lead_id_idx ON public.projects USING btree (lead_id);

CREATE INDEX projects_organization_id_idx ON public.projects USING btree (organization_id);

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON public.saved_views
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at();

CREATE POLICY "projects_delete" ON "public"."projects"
  FOR DELETE
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "projects_insert" ON "public"."projects"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "projects_select" ON "public"."projects"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "projects_update" ON "public"."projects"
  FOR UPDATE
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

REVOKE ALL ON TABLE "public"."projects" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."projects" TO "authenticated";

REVOKE ALL ON TABLE "public"."projects" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."projects" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."projects" TO "service_role";

REVOKE ALL ON TABLE "public"."saved_views" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."saved_views" TO "authenticated";

REVOKE ALL ON TABLE "public"."saved_views" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."saved_views" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."saved_views" TO "service_role";

ALTER TABLE "public"."saved_views"
  ADD CONSTRAINT "saved_views_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX saved_views_user_id_idx ON public.saved_views USING btree (user_id);

CREATE POLICY "saved_views_delete" ON "public"."saved_views"
  FOR DELETE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "saved_views_insert" ON "public"."saved_views"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "saved_views_select" ON "public"."saved_views"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "saved_views_update" ON "public"."saved_views"
  FOR UPDATE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));
