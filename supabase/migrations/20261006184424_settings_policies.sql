DROP POLICY "organization_settings_delete" ON "better_supabase"."organization_settings";

DROP POLICY "organization_settings_insert" ON "better_supabase"."organization_settings";

DROP POLICY "organization_settings_read" ON "better_supabase"."organization_settings";

DROP POLICY "organization_settings_update" ON "better_supabase"."organization_settings";

CREATE POLICY "organization_settings_delete" ON "better_supabase"."organization_settings"
  FOR DELETE
  TO "authenticated"
  USING (COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.update'::text), false));

CREATE POLICY "organization_settings_insert" ON "better_supabase"."organization_settings"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.update'::text), false));

CREATE POLICY "organization_settings_read" ON "better_supabase"."organization_settings"
  FOR SELECT
  TO "authenticated"
  USING (COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.read'::text), false));

CREATE POLICY "organization_settings_update" ON "better_supabase"."organization_settings"
  FOR UPDATE
  TO "authenticated"
  USING (COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.update'::text), false))
  WITH CHECK (COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.update'::text), false));
