/**
 * Prefixes of the names the library builds outside the module files (realtime
 * broadcast triggers, tenant checks, state transitions, JSON Schema checks).
 */
const LEGACY_PREFIXES = [
  "bs_broadcast_",
  "bs_same_tenant_",
  "bs_transition_",
  "bs_json_",
] as const;

const LEGACY_NAME = /\bbs_[a-z0-9_]+/g;

/** The `bs_` object names in installed module SQL, before 0.15 renamed them. */
export function legacyPrefixNames(text: string): readonly string[] {
  return [...new Set(text.match(LEGACY_NAME))].toSorted();
}

const array = (values: readonly string[]): string =>
  `array[${values.map((value) => `'${value.replaceAll("'", "''")}'`).join(", ")}]::text[]`;

/**
 * Renames the installed `bs_` triggers, policies, constraints, indexes and
 * functions to `bsb_`, so the module files' `drop ... if exists bsb_x` replace
 * them instead of adding a second copy. Only the names in `names` and the
 * runtime prefixes are renamed, and only while the new name is free, so the
 * step can run again.
 */
export function legacyPrefixSql(names: readonly string[]): string {
  return `do $bsb_rename$
declare
  v_names constant text[] := ${array(names)};
  v_prefixes constant text[] := ${array(LEGACY_PREFIXES)};
  r record;
begin
  for r in
    select t.tgname as name, t.tgrelid::regclass::text as rel
    from pg_trigger t
    where not t.tgisinternal
      and (t.tgname = any (v_names) or exists (select 1 from unnest(v_prefixes) x where starts_with(t.tgname, x)))
      and not exists (select 1 from pg_trigger u where u.tgrelid = t.tgrelid and u.tgname = 'bsb_' || substr(t.tgname, 4))
  loop
    begin
      execute format('alter trigger %I on %s rename to %I', r.name, r.rel, 'bsb_' || substr(r.name, 4));
    exception when insufficient_privilege then
      raise warning 'better-supabase: rename % to bsb_% by hand; the migration role does not own it', r.name, substr(r.name, 4);
    end;
  end loop;

  for r in
    select p.polname as name, p.polrelid::regclass::text as rel
    from pg_policy p
    where (p.polname = any (v_names) or exists (select 1 from unnest(v_prefixes) x where starts_with(p.polname, x)))
      and not exists (select 1 from pg_policy q where q.polrelid = p.polrelid and q.polname = 'bsb_' || substr(p.polname, 4))
  loop
    begin
      execute format('alter policy %I on %s rename to %I', r.name, r.rel, 'bsb_' || substr(r.name, 4));
    exception when insufficient_privilege then
      raise warning 'better-supabase: rename % to bsb_% by hand; the migration role does not own it', r.name, substr(r.name, 4);
    end;
  end loop;

  for r in
    select c.conname as name, c.conrelid::regclass::text as rel
    from pg_constraint c
    where c.conrelid <> 0
      and (c.conname = any (v_names) or exists (select 1 from unnest(v_prefixes) x where starts_with(c.conname, x)))
      and not exists (select 1 from pg_constraint d where d.conrelid = c.conrelid and d.conname = 'bsb_' || substr(c.conname, 4))
  loop
    begin
      execute format('alter table %s rename constraint %I to %I', r.rel, r.name, 'bsb_' || substr(r.name, 4));
    exception when insufficient_privilege then
      raise warning 'better-supabase: rename % to bsb_% by hand; the migration role does not own it', r.name, substr(r.name, 4);
    end;
  end loop;

  for r in
    select n.nspname as schema, i.relname as name
    from pg_class i
    join pg_namespace n on n.oid = i.relnamespace
    where i.relkind in ('i', 'I')
      and (i.relname = any (v_names) or exists (select 1 from unnest(v_prefixes) x where starts_with(i.relname, x)))
      and not exists (select 1 from pg_constraint c where c.conindid = i.oid)
      and to_regclass(format('%I.%I', n.nspname, 'bsb_' || substr(i.relname, 4))) is null
  loop
    begin
      execute format('alter index %I.%I rename to %I', r.schema, r.name, 'bsb_' || substr(r.name, 4));
    exception when insufficient_privilege then
      raise warning 'better-supabase: rename % to bsb_% by hand; the migration role does not own it', r.name, substr(r.name, 4);
    end;
  end loop;

  for r in
    select f.oid::regprocedure::text as fn, f.proname as name
    from pg_proc f
    join pg_namespace n on n.oid = f.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema')
      and (f.proname = any (v_names) or exists (select 1 from unnest(v_prefixes) x where starts_with(f.proname, x)))
      and not exists (
        select 1 from pg_proc g
        where g.pronamespace = f.pronamespace and g.proname = 'bsb_' || substr(f.proname, 4)
          and g.proargtypes = f.proargtypes
      )
  loop
    begin
      execute format('alter function %s rename to %I', r.fn, 'bsb_' || substr(r.name, 4));
    exception when insufficient_privilege then
      raise warning 'better-supabase: rename % to bsb_% by hand; the migration role does not own it', r.name, substr(r.name, 4);
    end;
  end loop;
end
$bsb_rename$;`;
}

/**
 * Creates `better_supabase.blocks` and copies the rows of the 0.14
 * `better_supabase.modules` table into it, so the schema diff that drops the
 * old table loses no installed versions.
 */
export const legacyBlocksTableSql: string = `create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
do $bsb_blocks$
begin
  if to_regclass('better_supabase.modules') is not null then
    insert into better_supabase.blocks (name, version, mode, installed_at, updated_at)
    select name, version, mode, installed_at, updated_at from better_supabase.modules
    on conflict (name) do nothing;
  end if;
end
$bsb_blocks$;`;
