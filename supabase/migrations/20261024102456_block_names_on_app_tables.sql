ALTER TABLE "public"."organizations"
  ADD COLUMN "stripe_customer_id" text;

ALTER TABLE "public"."organizations"
  ADD CONSTRAINT "organizations_stripe_customer_id_key" UNIQUE (stripe_customer_id);

CREATE UNIQUE INDEX organizations_slug_idx ON public.organizations USING btree (lower(slug));

CREATE POLICY "bsb_organizations_select" ON "public"."organizations"
  FOR SELECT
  TO "authenticated"
  USING ((id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));
