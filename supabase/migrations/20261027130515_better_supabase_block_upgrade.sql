-- better-supabase upgrade: steps that run before the schema diff.

-- flags: version 3 to 4. Flag lifecycle: rollout_variant becomes rollout_variants, weighted splits (an existing variant moves over with weight 100), rollouts can follow a schedule, rules can name shared segments, and every save records a revision that restore_flag() brings back. save_flag() takes a message.
do $$
begin
  if exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = to_regclass('"better_supabase"."flags"') and a.attname = 'rollout_variant' and not a.attisdropped
  ) then
    alter table "better_supabase"."flags" add column if not exists "rollout_variants" jsonb not null default '[]'::jsonb check (jsonb_typeof("rollout_variants") = 'array');
    update "better_supabase"."flags" set "rollout_variants" = jsonb_build_array(jsonb_build_object('variant', rollout_variant, 'weight', 100))
    where rollout_variant is not null;
    alter table "better_supabase"."flags" drop column rollout_variant;
  end if;
end;
$$;
