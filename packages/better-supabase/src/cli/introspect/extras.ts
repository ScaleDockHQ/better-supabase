import type { Queryable } from './typegen.ts';
import type {
  CatalogPolicy,
  CatalogTrigger,
  ExtrasFunction,
  ExtrasHook,
  ExtrasHookFunction,
  ExtrasTable,
  ForeignKeyAction,
  SnapshotBucket,
  SnapshotExtras,
} from './types.ts';

/**
 * Catalog details `@supabase/postgrest-typegen` leaves out: named unique and
 * CHECK constraints, foreign key actions, ordered primary keys, indexes,
 * policies, triggers, grants, buckets and the realtime publication.
 *
 * The SQL takes no bind parameters because the Management API endpoint only
 * accepts a query string; schema names are inlined as escaped literals.
 */
const literalArray = (values: readonly string[]): string =>
  `array[${values.map((value) => `'${value.replace(/'/g, "''")}'`).join(', ')}]::text[]`;

const RELATIONS = (schemas: string) => `
select c.oid::int8 as id, n.nspname as schema, c.relname as name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = any(${schemas}) and c.relkind in ('r', 'p', 'v', 'm', 'f')
  and not c.relispartition
order by 2, 3`;

const CONSTRAINTS = (schemas: string) => `
select con.conrelid::int8 as table_id, con.conname as name, con.contype as type,
  array(select a.attname from unnest(con.conkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum order by k.ord)::text[] as columns,
  con.confdeltype as on_delete, con.confupdtype as on_update,
  pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = any(${schemas}) and con.contype in ('p', 'u', 'f', 'c')
order by 1, 2`;

const INDEXES = (schemas: string) => `
select ix.indrelid::int8 as table_id, i.relname as name,
  ix.indisunique as unique, ix.indisprimary as primary,
  (ix.indpred is not null or 0 = any(ix.indkey::int2[])) as partial,
  array(select a.attname from unnest(ix.indkey::int2[]) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = ix.indrelid and a.attnum = k.attnum order by k.ord)::text[] as columns
from pg_index ix
join pg_class i on i.oid = ix.indexrelid
join pg_class c on c.oid = ix.indrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = any(${schemas})
order by 1, 2`;

const POLICIES = (schemas: string) => `
select c.oid::int8 as table_id, p.policyname as name,
  (p.permissive = 'PERMISSIVE') as permissive, p.roles::text[] as roles, lower(p.cmd) as command,
  p.qual as using_expr, p.with_check as check_expr,
  array(
    select distinct fn.nspname || '.' || pr.proname
    from pg_policy pol
    join pg_depend d on d.classid = 'pg_policy'::regclass and d.objid = pol.oid
      and d.refclassid = 'pg_proc'::regclass
    join pg_proc pr on pr.oid = d.refobjid
    join pg_namespace fn on fn.oid = pr.pronamespace
    where pol.polrelid = c.oid and pol.polname = p.policyname
    order by 1
  )::text[] as functions
from pg_policies p
join pg_namespace n on n.nspname = p.schemaname
join pg_class c on c.relnamespace = n.oid and c.relname = p.tablename
where p.schemaname = any(${schemas})
order by 1, 2`;

// Functions policies call (in any schema) and functions with `set` options
// other than `search_path`.
const FUNCTIONS = (schemas: string) => `
select n.nspname as schema, p.proname as name,
  pg_get_function_identity_arguments(p.oid) as signature,
  l.lanname as language, p.provolatile as volatility,
  p.prosecdef as security_definer, coalesce(p.proconfig, '{}')::text[] as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where p.oid in (
    select d.refobjid
    from pg_depend d
    join pg_policy pol on d.classid = 'pg_policy'::regclass and d.objid = pol.oid
    join pg_class c on c.oid = pol.polrelid
    join pg_namespace cn on cn.oid = c.relnamespace
    where d.refclassid = 'pg_proc'::regclass and cn.nspname = any(${schemas})
  )
  or (n.nspname = any(${schemas}) and exists (
    select 1 from unnest(p.proconfig) setting where setting not like 'search_path=%'
  ))
order by 1, 2, 3`;

/** Roles the hook checks care about: the one Auth calls it as, and the API roles. */
const HOOK_ROLES = literalArray([
  'supabase_auth_admin',
  'authenticated',
  'anon',
]);

// Auth hook functions by qualified name, with who may call them.
const HOOKS = (names: string) => `
select n.nspname as schema, p.proname as name,
  pg_get_function_identity_arguments(p.oid) as signature,
  l.lanname as language, p.provolatile as volatility,
  p.prosecdef as security_definer, coalesce(p.proconfig, '{}')::text[] as config,
  array(select r.rolname::text from pg_roles r
    where r.rolname = any(${HOOK_ROLES}) and has_function_privilege(r.oid, p.oid, 'execute')
    order by 1) as execute,
  exists(select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where a.grantee = 0 and a.privilege_type = 'EXECUTE') as public_execute,
  array(select r.rolname::text from pg_roles r
    where r.rolname = any(${HOOK_ROLES}) and has_schema_privilege(r.oid, n.oid, 'usage')
    order by 1) as schema_usage
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname || '.' || p.proname = any(${names})
order by 1, 2, 3`;

const TRIGGERS = (schemas: string) => `
select t.tgrelid::int8 as table_id, t.tgname as name,
  pn.nspname || '.' || p.proname as function,
  case when t.tgtype & 2 = 2 then 'before' when t.tgtype & 64 = 64 then 'instead of' else 'after' end as timing,
  array_remove(array[
    case when t.tgtype & 4 = 4 then 'insert' end,
    case when t.tgtype & 16 = 16 then 'update' end,
    case when t.tgtype & 8 = 8 then 'delete' end,
    case when t.tgtype & 32 = 32 then 'truncate' end
  ], null)::text[] as events,
  case when t.tgtype & 1 = 1 then 'row' else 'statement' end as level
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
join pg_namespace pn on pn.oid = p.pronamespace
where not t.tgisinternal and n.nspname = any(${schemas})
order by 1, 2`;

const GRANTS = (schemas: string) => `
select c.oid::int8 as table_id, g.grantee as role,
  array_agg(g.privilege_type::text order by g.privilege_type)::text[] as privileges
from information_schema.role_table_grants g
join pg_namespace n on n.nspname = g.table_schema
join pg_class c on c.relnamespace = n.oid and c.relname = g.table_name
where g.table_schema = any(${schemas}) and g.grantee in ('anon', 'authenticated', 'service_role')
group by 1, 2
order by 1, 2`;

const BUCKETS = `
select id, public, file_size_limit, allowed_mime_types
from storage.buckets
order by id`;

const REALTIME = `
select schemaname || '.' || tablename as name
from pg_publication_tables
where pubname = 'supabase_realtime'
order by 1`;

// Settings for every database and for this one; the database's own win.
const ROLE_SETTINGS = `
select r.rolname as role, s.setconfig as config
from pg_catalog.pg_db_role_setting s
join pg_catalog.pg_roles r on r.oid = s.setrole
where r.rolname in ('authenticator', 'anon', 'authenticated')
  and s.setdatabase in (0, (select oid from pg_catalog.pg_database where datname = current_database()))
order by s.setdatabase`;

const HAS_TABLE = (qualified: string) =>
  `select to_regclass('${qualified}') is not null as present`;

const ACTIONS: Record<string, ForeignKeyAction> = {
  a: 'no action',
  r: 'restrict',
  c: 'cascade',
  n: 'set null',
  d: 'set default',
};

interface ConstraintRow {
  table_id: number | string;
  name: string;
  type: 'p' | 'u' | 'f' | 'c';
  columns: string[];
  on_delete: string;
  on_update: string;
  definition: string;
}

interface IndexRow {
  table_id: number | string;
  name: string;
  unique: boolean;
  primary: boolean;
  partial: boolean;
  columns: string[];
}

interface PolicyRow {
  table_id: number | string;
  name: string;
  permissive: boolean;
  roles: string[];
  command: CatalogPolicy['command'];
  using_expr: string | null;
  check_expr: string | null;
  functions: string[] | null;
}

interface FunctionRow {
  schema: string;
  name: string;
  signature: string;
  language: string;
  volatility: 'i' | 's' | 'v';
  security_definer: boolean;
  config: string[] | null;
}

const VOLATILITY: Record<
  FunctionRow['volatility'],
  ExtrasFunction['volatility']
> = {
  i: 'immutable',
  s: 'stable',
  v: 'volatile',
};

/** `['statement_timeout=5s']` as `{ statement_timeout: '5s' }`. */
function settingsOf(config: readonly string[] | null): Record<string, string> {
  const settings: Record<string, string> = {};
  for (const entry of config ?? []) {
    const at = entry.indexOf('=');
    if (at > 0) settings[entry.slice(0, at)] = entry.slice(at + 1);
  }
  return settings;
}

interface HookRow extends FunctionRow {
  execute: string[];
  public_execute: boolean;
  schema_usage: string[];
}

/** A hook function to introspect: `[auth.hook.<hook>]` pointing at `schema.name`. */
export interface HookTarget {
  readonly hook: string;
  readonly schema: string;
  readonly name: string;
}

const functionOf = (row: FunctionRow): ExtrasFunction => ({
  schema: row.schema,
  name: row.name,
  signature: row.signature,
  language: row.language,
  volatility: VOLATILITY[row.volatility],
  securityDefiner: row.security_definer,
  settings: settingsOf(row.config),
});

/** The functions behind Auth hooks, in any schema, with their ACLs. */
export async function readHooks(
  db: Queryable,
  targets: readonly HookTarget[],
): Promise<ExtrasHook[]> {
  if (targets.length === 0) return [];
  const found = await rows<HookRow>(
    db,
    HOOKS(literalArray(targets.map((t) => `${t.schema}.${t.name}`))),
  );
  return targets.map((target) => ({
    hook: target.hook,
    schema: target.schema,
    name: target.name,
    functions: found
      .filter((row) => row.schema === target.schema && row.name === target.name)
      .map((row): ExtrasHookFunction => ({
        ...functionOf(row),
        execute: row.execute,
        publicExecute: row.public_execute,
        schemaUsage: row.schema_usage,
      })),
  }));
}

interface TriggerRow {
  table_id: number | string;
  name: string;
  function: string;
  timing: CatalogTrigger['timing'];
  events: CatalogTrigger['events'][number][];
  level: CatalogTrigger['level'];
}

interface GrantRow {
  table_id: number | string;
  role: string;
  privileges: string[];
}

interface BucketRow {
  id: string;
  public: boolean;
  file_size_limit: number | string | null;
  allowed_mime_types: string[] | null;
}

async function rows<R>(db: Queryable, sql: string): Promise<R[]> {
  return (await db.query(sql)).rows as R[];
}

/** Rows from a table owned by another Supabase service, if it exists. */
async function serviceRows<R>(
  db: Queryable,
  qualified: string,
  sql: string,
): Promise<R[]> {
  const [probe] = await rows<{ present: boolean }>(db, HAS_TABLE(qualified));
  return probe?.present ? rows<R>(db, sql) : [];
}

function groupById<T extends { table_id: number | string }>(
  list: readonly T[],
): Map<number, T[]> {
  const map = new Map<number, T[]>();
  for (const row of list) {
    const id = Number(row.table_id);
    const entry = map.get(id);
    if (entry) entry.push(row);
    else map.set(id, [row]);
  }
  return map;
}

/** Reads the extras for `schemas`. Queries run one after another. */
export async function readExtras(
  db: Queryable,
  schemas: readonly string[],
  hooks: readonly HookTarget[] = [],
): Promise<SnapshotExtras> {
  const list = literalArray(schemas);
  const relations = await rows<{
    id: number | string;
    schema: string;
    name: string;
  }>(db, RELATIONS(list));
  const constraints = groupById(
    await rows<ConstraintRow>(db, CONSTRAINTS(list)),
  );
  const indexes = groupById(await rows<IndexRow>(db, INDEXES(list)));
  const policies = groupById(await rows<PolicyRow>(db, POLICIES(list)));
  const triggers = groupById(await rows<TriggerRow>(db, TRIGGERS(list)));
  const grants = groupById(await rows<GrantRow>(db, GRANTS(list)));
  const buckets = await serviceRows<BucketRow>(db, 'storage.buckets', BUCKETS);
  const realtime = await serviceRows<{ name: string }>(
    db,
    'pg_catalog.pg_publication_tables',
    REALTIME,
  );
  const functions = await rows<FunctionRow>(db, FUNCTIONS(list));
  const roleSettings: Record<string, Record<string, string>> = {};
  for (const row of await rows<{ role: string; config: string[] | null }>(
    db,
    ROLE_SETTINGS,
  )) {
    Object.assign((roleSettings[row.role] ??= {}), settingsOf(row.config));
  }

  const tables = relations.map((relation): ExtrasTable => {
    const id = Number(relation.id);
    const own = constraints.get(id) ?? [];
    const ownIndexes = indexes.get(id) ?? [];
    const uniques = own
      .filter((con) => con.type === 'u')
      .map((con) => ({ name: con.name, columns: con.columns }));
    const constraintNames = new Set(own.map((con) => con.name));
    for (const index of ownIndexes) {
      if (
        index.unique &&
        !index.primary &&
        !index.partial &&
        !constraintNames.has(index.name)
      ) {
        uniques.push({ name: index.name, columns: index.columns });
      }
    }
    return {
      id,
      schema: relation.schema,
      name: relation.name,
      primaryKey: own.find((con) => con.type === 'p')?.columns ?? [],
      uniques,
      foreignKeys: own
        .filter((con) => con.type === 'f')
        .map((con) => ({
          name: con.name,
          onDelete: ACTIONS[con.on_delete] ?? 'no action',
          onUpdate: ACTIONS[con.on_update] ?? 'no action',
        })),
      checks: own
        .filter((con) => con.type === 'c')
        .map((con) => ({ name: con.name, definition: con.definition })),
      indexes: ownIndexes.map((index) => ({
        name: index.name,
        columns: index.columns,
        unique: index.unique,
        primary: index.primary,
        partial: index.partial,
      })),
      policies: (policies.get(id) ?? []).map((policy) => ({
        name: policy.name,
        command: policy.command,
        roles: policy.roles,
        permissive: policy.permissive,
        using: policy.using_expr,
        check: policy.check_expr,
        functions: policy.functions ?? [],
      })),
      triggers: (triggers.get(id) ?? []).map((trigger) => ({
        name: trigger.name,
        timing: trigger.timing,
        events: trigger.events,
        level: trigger.level,
        function: trigger.function,
      })),
      grants: (grants.get(id) ?? []).map((grant) => ({
        role: grant.role,
        privileges: grant.privileges,
      })),
    };
  });

  return {
    tables,
    buckets: buckets.map((row): SnapshotBucket => ({
      id: row.id,
      public: row.public,
      fileSizeLimit:
        row.file_size_limit === null ? null : Number(row.file_size_limit),
      allowedMimeTypes: row.allowed_mime_types,
    })),
    realtime: realtime.map((row) => row.name),
    roleSettings,
    functions: functions.map(functionOf),
    ...(hooks.length > 0 ? { hooks: await readHooks(db, hooks) } : {}),
  };
}
