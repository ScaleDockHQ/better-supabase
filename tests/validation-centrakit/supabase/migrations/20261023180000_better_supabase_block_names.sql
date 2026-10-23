-- The sessions block keeps its 0.14 name. Move its row back, or drop the
-- 0.15 row when the 0.14 name already has one.
do $bsb_block_names$
begin
  if to_regclass('better_supabase.blocks') is null then
    return;
  end if;
  if exists (select 1 from better_supabase.blocks b where b.name = 'sessions') then
    delete from better_supabase.blocks where name = 'session-revocation';
  else
    update better_supabase.blocks set name = 'sessions', updated_at = now()
      where name = 'session-revocation';
  end if;
end
$bsb_block_names$;
