-- better-supabase upgrade: steps that run before the schema diff.

-- imports: version 1 to 2. An import run names its source instead of its kind (ADR 0141).
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'import_runs' and column_name = 'kind') then alter table "better_supabase"."import_runs" rename column "kind" to "source"; end if; end $$;
