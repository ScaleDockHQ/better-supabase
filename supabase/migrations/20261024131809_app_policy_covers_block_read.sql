DROP POLICY "bsb_organizations_select" ON "public"."organizations";

DROP POLICY "organizations_member_select" ON "public"."organizations";

CREATE POLICY "organizations_member_select" ON "public"."organizations"
  FOR SELECT
  TO "authenticated"
  USING (((id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id)) OR (id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids))));
