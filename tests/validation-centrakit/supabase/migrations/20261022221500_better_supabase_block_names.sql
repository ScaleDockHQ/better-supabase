-- better-supabase upgrade: the module data migration before this one wrote
-- rows under the block names 0.15 renamed. Move them again, or drop them when
-- the new name already has a row.
do $bsb_block_names$
declare
  v_pair text[];
begin
  if to_regclass('better_supabase.blocks') is null then
    return;
  end if;
  foreach v_pair slice 1 in array array[
    ['access', 'permissions'],
    ['jobs', 'queue'],
    ['number-sequences', 'numbering'],
    ['sessions', 'session-revocation'],
    ['support-sessions', 'impersonation'],
    ['tenant', 'memberships']
  ] loop
    if exists (select 1 from better_supabase.blocks b where b.name = v_pair[2]) then
      delete from better_supabase.blocks where name = v_pair[1];
    else
      update better_supabase.blocks set name = v_pair[2], updated_at = now()
        where name = v_pair[1];
    end if;
  end loop;
end
$bsb_block_names$;
