-- better-supabase upgrade: steps that run before the schema diff.

-- Moves the installed blocks 0.15 renamed to their new names.
do $bsb_block_names$
begin
  if to_regclass('better_supabase.blocks') is not null then
    update better_supabase.blocks set name = 'permissions', updated_at = now()
      where name = 'access'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'permissions');
    update better_supabase.blocks set name = 'queue', updated_at = now()
      where name = 'jobs'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'queue');
    update better_supabase.blocks set name = 'numbering', updated_at = now()
      where name = 'number-sequences'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'numbering');
    update better_supabase.blocks set name = 'session-revocation', updated_at = now()
      where name = 'sessions'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'session-revocation');
    update better_supabase.blocks set name = 'impersonation', updated_at = now()
      where name = 'support-sessions'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'impersonation');
    update better_supabase.blocks set name = 'memberships', updated_at = now()
      where name = 'tenant'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'memberships');
  end if;
end
$bsb_block_names$;
