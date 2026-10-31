-- better-supabase upgrade: steps that run before the schema diff.

-- activities: version 2 to 3. The links' activity column is activity_id, after the activity entity (ADR 0152).
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'engagement_subjects' and column_name = 'engagement_id') then alter table "better_supabase"."engagement_subjects" rename column "engagement_id" to "activity_id"; end if; end $$;

-- activities: version 2 to 3. The recordings' activity column is activity_id (ADR 0152).
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'engagement_recordings' and column_name = 'engagement_id') then alter table "better_supabase"."engagement_recordings" rename column "engagement_id" to "activity_id"; end if; end $$;

-- activities: version 2 to 3. The notes' activity column is activity_id (ADR 0152).
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'engagement_notes' and column_name = 'engagement_id') then alter table "better_supabase"."engagement_notes" rename column "engagement_id" to "activity_id"; end if; end $$;

-- mail-sync: version 1 to 2. The threads' activity column is activity_id, after the activity entity (ADR 0152).
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'mail_threads' and column_name = 'engagement_id') then alter table "better_supabase"."mail_threads" rename column "engagement_id" to "activity_id"; end if; end $$;
