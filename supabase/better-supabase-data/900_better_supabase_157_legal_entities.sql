-- better-supabase module: legal-entities
-- @bsb-block-data legal-entities
-- @bsb-hash sha256:554e83d4f0e0e4927b9c408be639d1509213d3f7ebdb117b40653a5dddbf2252
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

do $$
declare
  v_constraint name;
begin
  if to_regclass('"better_supabase"."field_values"') is null then
    return;
  end if;
  for v_constraint in
    select c.conname from pg_constraint c
    where c.conrelid = '"better_supabase"."field_values"'::regclass and c.contype = 'u'
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = c.conrelid and a.attnum = any (c.conkey))
        @> array['tenant_id', 'subject_type', 'subject_id', 'definition_id']
      and cardinality(c.conkey) = 4
  loop
    execute format('alter table "better_supabase"."field_values" drop constraint %I', v_constraint);
  end loop;
end $$;

insert into better_supabase.blocks (name, version, mode)
values ('legal-entities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
