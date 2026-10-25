DROP POLICY "client_notes_delete" ON "public"."client_notes";

DROP POLICY "client_notes_insert" ON "public"."client_notes";

DROP POLICY "client_notes_update" ON "public"."client_notes";

DROP POLICY "projects_delete" ON "public"."projects";

DROP POLICY "projects_insert" ON "public"."projects";

DROP POLICY "projects_update" ON "public"."projects";

DROP POLICY "saved_views_delete" ON "public"."saved_views";

DROP POLICY "saved_views_insert" ON "public"."saved_views";

DROP POLICY "saved_views_update" ON "public"."saved_views";

DROP POLICY "tasks_delete" ON "public"."tasks";

DROP POLICY "tasks_insert" ON "public"."tasks";

DROP POLICY "tasks_update" ON "public"."tasks";

CREATE POLICY "client_notes_delete" ON "public"."client_notes"
  FOR DELETE
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "client_notes_insert" ON "public"."client_notes"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "client_notes_update" ON "public"."client_notes"
  FOR UPDATE
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH
    CHECK (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "projects_delete" ON "public"."projects"
  FOR DELETE
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "projects_insert" ON "public"."projects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "projects_update" ON "public"."projects"
  FOR UPDATE
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH
    CHECK (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "saved_views_delete" ON "public"."saved_views"
  FOR DELETE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "saved_views_insert" ON "public"."saved_views"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "saved_views_update" ON "public"."saved_views"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "tasks_delete" ON "public"."tasks"
  FOR DELETE
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "tasks_insert" ON "public"."tasks"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "tasks_update" ON "public"."tasks"
  FOR UPDATE
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH
    CHECK (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));
