-- better-supabase module: legal-entities
-- @bsb-block-data legal-entities
-- @bsb-hash sha256:9bddd9d57680031f0c336b79b09dffee3d2bd1bb5f4d6aee95a8758c88bb05ec
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

do $$
begin
  if exists (
    select 1 from "better_supabase"."invoices" x
    join "better_supabase"."legal_entities" d on d."tenant_id" = x."tenant_id" and d."is_default" and x.legal_entity_id = d."id"
    join "better_supabase"."invoices" y on y."tenant_id" = x."tenant_id" and y.legal_entity_id is null and (x."number" = y."number" or x."identifier" = y."identifier") and x."direction" is not distinct from y."direction" and x."kind" is not distinct from y."kind"
  ) then
    raise warning 'invoices holds numbers twice for the default legal entity and for documents without one; list them with legal_entities_disable_check and renumber one of each pair'
      using hint = 'LEGAL_ENTITY_NUMBER_DUPLICATE';
  end if;
end $$;
do $$
begin
  if exists (
    select 1 from "better_supabase"."quotes" x
    join "better_supabase"."legal_entities" d on d."tenant_id" = x."tenant_id" and d."is_default" and x.legal_entity_id = d."id"
    join "better_supabase"."quotes" y on y."tenant_id" = x."tenant_id" and y.legal_entity_id is null and (x."number" = y."number") and x."revision" is not distinct from y."revision"
  ) then
    raise warning 'quotes holds numbers twice for the default legal entity and for documents without one; list them with legal_entities_disable_check and renumber one of each pair'
      using hint = 'LEGAL_ENTITY_NUMBER_DUPLICATE';
  end if;
end $$;
do $$
begin
  if exists (
    select 1 from "better_supabase"."orders" x
    join "better_supabase"."legal_entities" d on d."tenant_id" = x."tenant_id" and d."is_default" and x.legal_entity_id = d."id"
    join "better_supabase"."orders" y on y."tenant_id" = x."tenant_id" and y.legal_entity_id is null and (x."number" = y."number" or x."invoice_number" = y."invoice_number")
  ) then
    raise warning 'orders holds numbers twice for the default legal entity and for documents without one; list them with legal_entities_disable_check and renumber one of each pair'
      using hint = 'LEGAL_ENTITY_NUMBER_DUPLICATE';
  end if;
end $$;
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
