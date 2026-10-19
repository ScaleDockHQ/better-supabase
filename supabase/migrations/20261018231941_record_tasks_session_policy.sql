CREATE POLICY "bs_session_active" ON "public"."tasks"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (( SELECT better_supabase.session_active() AS session_active))
  WITH CHECK (( SELECT better_supabase.session_active() AS session_active));
