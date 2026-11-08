ALTER TABLE "better_supabase"."inbox_conversations"
  ADD CONSTRAINT "conversations_team_fkey" FOREIGN KEY (team_id) REFERENCES better_supabase.teams(id) ON DELETE SET NULL;
