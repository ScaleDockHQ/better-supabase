-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- impersonation: version 2 to 3. The member a support session acts as is target_id: user references name their role.
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'support_sessions' and column_name = 'target_user_id') then alter table "better_supabase"."support_sessions" rename column "target_user_id" to "target_id"; end if; end $$;

-- impersonation: version 2 to 3. The member a support request is for is target_id: user references name their role.
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'support_requests' and column_name = 'target_user_id') then alter table "better_supabase"."support_requests" rename column "target_user_id" to "target_id"; end if; end $$;
