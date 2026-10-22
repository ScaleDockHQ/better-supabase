-- better-supabase upgrade: steps that run before the schema diff.

-- Moves the installed blocks 0.15 renamed to their new names.
do $bsb_block_names$
begin
  if to_regclass('better_supabase.blocks') is not null then
    update better_supabase.blocks set name = 'timeline', updated_at = now()
      where name = 'activity'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'timeline');
    update better_supabase.blocks set name = 'ai-keys', updated_at = now()
      where name = 'ai-providers'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'ai-keys');
    update better_supabase.blocks set name = 'ai-schedules', updated_at = now()
      where name = 'ai-tasks'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'ai-schedules');
    update better_supabase.blocks set name = 'bulk-actions', updated_at = now()
      where name = 'bulk'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'bulk-actions');
    update better_supabase.blocks set name = 'compliance', updated_at = now()
      where name = 'controls'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'compliance');
    update better_supabase.blocks set name = 'activities', updated_at = now()
      where name = 'engagements'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'activities');
    update better_supabase.blocks set name = 'feature-flags', updated_at = now()
      where name = 'flags'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'feature-flags');
    update better_supabase.blocks set name = 'data-api-grants', updated_at = now()
      where name = 'grants'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'data-api-grants');
    update better_supabase.blocks set name = 'queue', updated_at = now()
      where name = 'jobs'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'queue');
    update better_supabase.blocks set name = 'contacts', updated_at = now()
      where name = 'parties'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'contacts');
    update better_supabase.blocks set name = 'admission-passes', updated_at = now()
      where name = 'passes'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'admission-passes');
    update better_supabase.blocks set name = 'automations', updated_at = now()
      where name = 'rules'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'automations');
    update better_supabase.blocks set name = 'service-accounts', updated_at = now()
      where name = 'service-principals'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'service-accounts');
    update better_supabase.blocks set name = 'session-revocation', updated_at = now()
      where name = 'sessions'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'session-revocation');
    update better_supabase.blocks set name = 'goals', updated_at = now()
      where name = 'targets'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'goals');
    update better_supabase.blocks set name = 'tasks', updated_at = now()
      where name = 'work-items'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'tasks');
    update better_supabase.blocks set name = 'workflow-editor', updated_at = now()
      where name = 'workflow-builder'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'workflow-editor');
    update better_supabase.blocks set name = 'workflow-sdk', updated_at = now()
      where name = 'workflow-sdk-world'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'workflow-sdk');
  end if;
end
$bsb_block_names$;

-- catalog: version 1 to 2. The collections table is product_collections, so it doesn't read as the collections block's table.
do $$ begin if to_regclass('"better_supabase"."collections"') is not null and to_regclass('"better_supabase"."product_collections"') is null then alter table "better_supabase"."collections" rename to "product_collections"; end if; end $$;

-- hiring: version 1 to 2. The jobs table is job_openings, so it doesn't read as the queue block's jobs.
do $$ begin if to_regclass('"better_supabase"."jobs"') is not null and to_regclass('"better_supabase"."job_openings"') is null then alter table "better_supabase"."jobs" rename to "job_openings"; end if; end $$;
