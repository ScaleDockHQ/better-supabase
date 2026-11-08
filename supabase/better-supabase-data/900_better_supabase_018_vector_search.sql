-- better-supabase module: vector-search
-- @bsb-block-data vector-search
-- @bsb-hash sha256:cfcaa1f72f5d1d9b30f596a383bf91fbf64bb93f905ab2c6671ace0ee33c67c4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "vector" with schema "extensions";

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_index i
    join pg_catalog.pg_class c on c.oid = i.indexrelid
    join pg_catalog.pg_am am on am.oid = c.relam
    join pg_catalog.pg_opclass oc on oc.oid = i.indclass[0]
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
    where i.indrelid = '"public"."notes"'::regclass
      and a.attname = 'embedding'
      and am.amname in ('hnsw', 'ivfflat')
      and oc.opcname = 'vector_cosine_ops'
  ) then
    raise notice '%', 'notes.embedding has no hnsw or ivfflat index with vector_cosine_ops, so search_notes scans the table';
  end if;
end;
$$;

insert into better_supabase.blocks (name, version, mode)
values ('vector-search', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
