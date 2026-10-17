DROP POLICY "bs_notification_preferences_own" ON "better_supabase"."notification_preferences";

DROP POLICY "bs_notification_subscriptions_own" ON "better_supabase"."notification_subscriptions";

DROP POLICY "user_settings_own" ON "better_supabase"."user_settings";

CREATE POLICY "bs_notification_preferences_own_delete" ON "better_supabase"."notification_preferences"
  FOR DELETE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bs_notification_preferences_own_insert" ON "better_supabase"."notification_preferences"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with))) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bs_notification_preferences_own_read" ON "better_supabase"."notification_preferences"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bs_notification_preferences_own_update" ON "better_supabase"."notification_preferences"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with))) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bs_notification_subscriptions_own_delete" ON "better_supabase"."notification_subscriptions"
  FOR DELETE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bs_notification_subscriptions_own_insert" ON "better_supabase"."notification_subscriptions"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with))) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bs_notification_subscriptions_own_read" ON "better_supabase"."notification_subscriptions"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bs_notification_subscriptions_own_update" ON "better_supabase"."notification_subscriptions"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS
    tenant_ids_with))) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "user_settings_own_delete" ON "better_supabase"."user_settings"
  FOR DELETE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "user_settings_own_insert" ON "better_supabase"."user_settings"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "user_settings_own_read" ON "better_supabase"."user_settings"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "user_settings_own_update" ON "better_supabase"."user_settings"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));
