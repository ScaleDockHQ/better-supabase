do $bsb_block_names$
begin
  if to_regclass('better_supabase.blocks') is not null then
    update better_supabase.blocks set name = 'grants', updated_at = now()
      where name = 'data-api-grants'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'grants');
    update better_supabase.blocks set name = 'bulk', updated_at = now()
      where name = 'bulk-actions'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'bulk');
    update better_supabase.blocks set name = 'passes', updated_at = now()
      where name = 'admission-passes'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'passes');
    update better_supabase.blocks set name = 'flags', updated_at = now()
      where name = 'feature-flags'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'flags');
    update better_supabase.blocks set name = 'identities', updated_at = now()
      where name = 'linked-identities'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'identities');
    update better_supabase.blocks set name = 'sessions', updated_at = now()
      where name = 'session-revocation'
        and not exists (select 1 from better_supabase.blocks b where b.name = 'sessions');
  end if;
end
$bsb_block_names$;
