-- better-supabase upgrade: steps pg-delta can't express (renames, backfills, expression changes).
-- Review them before you apply this migration; the module files hold everything else.
-- destructive: reviewed

-- impersonation: version 2 to 3. The member a support session acts as is target_id: user references name their role.
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'support_sessions' and column_name = 'target_user_id') then alter table "better_supabase"."support_sessions" rename column "target_user_id" to "target_id"; end if; end $$;

-- impersonation: version 2 to 3. The member a support request is for is target_id: user references name their role.
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'support_requests' and column_name = 'target_user_id') then alter table "better_supabase"."support_requests" rename column "target_user_id" to "target_id"; end if; end $$;

-- billing: version 4 to 5. Native subscription periods are period_starts_at and period_ends_at.
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'billing_native_subscriptions' and column_name = 'period_start') then alter table "better_supabase"."billing_native_subscriptions" rename column "period_start" to "period_starts_at"; end if; end $$;
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'billing_native_subscriptions' and column_name = 'period_end') then alter table "better_supabase"."billing_native_subscriptions" rename column "period_end" to "period_ends_at"; end if; end $$;

-- billing: version 4 to 5. The Stripe subscription's period end is period_ends_at.
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'billing_subscriptions' and column_name = 'period_end') then alter table "better_supabase"."billing_subscriptions" rename column "period_end" to "period_ends_at"; end if; end $$;

-- vercel-marketplace: version 2 to 3. Invoice periods are period_starts_at and period_ends_at: timestamp columns end in _at.
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'marketplace_invoices' and column_name = 'period_start') then alter table "better_supabase"."marketplace_invoices" rename column "period_start" to "period_starts_at"; end if; end $$;
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'marketplace_invoices' and column_name = 'period_end') then alter table "better_supabase"."marketplace_invoices" rename column "period_end" to "period_ends_at"; end if; end $$;

-- vercel-marketplace: version 2 to 3. Meter report periods are period_starts_at and period_ends_at: timestamp columns end in _at.
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'marketplace_meter_reports' and column_name = 'period_start') then alter table "better_supabase"."marketplace_meter_reports" rename column "period_start" to "period_starts_at"; end if; end $$;
do $$ begin if exists (select 1 from information_schema.columns where table_schema = 'better_supabase' and table_name = 'marketplace_meter_reports' and column_name = 'period_end') then alter table "better_supabase"."marketplace_meter_reports" rename column "period_end" to "period_ends_at"; end if; end $$;
