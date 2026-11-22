import type { Pool } from "pg";

import type { PgQueryable } from "../db.ts";
import type { PgDelta } from "../in-stack-diff.ts";

import { CliError } from "../core/errors.ts";

export interface TableRef {
  readonly schema: string;
  readonly name: string;
}

/** `schema.table`, the key of every count and signature map. */
export const tableKey = (table: TableRef): string =>
  `${table.schema}.${table.name}`;

/**
 * Tables whose rows change on their own (cron history, the HTTP queue,
 * partitions of realtime.messages), and storage.objects, which the storage
 * restore recreates through the Storage API.
 */
const NOISE = String.raw`^(cron\.job_run_details|net\..*|realtime\.messages.*|storage\.objects|storage\.s3_multipart.*|_analytics\..*|_realtime\..*|auth\.(audit_log_entries|sessions|refresh_tokens|flow_state|one_time_tokens))$`;

/** `comment:(<id>)` and `acl:(<id>).<role>`: facts that hang off another object. */
const SATELLITE = /^(?:comment|acl):\((.*)\)(?:\.[^)]*)?$/u;

const noise = new RegExp(NOISE, "u");

/**
 * A pgmq queue or its archive: a table `pgmq.create` makes, so the restore
 * recreates it and copies its rows.
 */
export const isQueueTable = (key: string): boolean => /^pgmq\.[qa]_/u.test(key);

/**
 * The extension-owned tables a restore leaves alone: CREATE EXTENSION fills
 * them, and pg_dump leaves out their rows. pgmq queues are the exception.
 */
export function leaveAlone(
  ...sets: readonly ReadonlySet<string>[]
): ReadonlySet<string> {
  return new Set(
    sets.flatMap((set) => [...set]).filter((key) => !isQueueTable(key)),
  );
}

const isNoiseTable = (table: TableRef): boolean => noise.test(tableKey(table));

interface SignatureRow {
  readonly schema: string;
  readonly name: string;
  readonly sig: string;
}

/**
 * A signature per table, `<row count>:<md5 of the sorted row hashes>`, so a
 * table the seeds updated shows up as well as one they filled. Partitioned
 * parents are left out: their rows belong to the children.
 */
export async function tableSignatures(
  client: PgQueryable,
): Promise<ReadonlyMap<string, string>> {
  const { rows } = await client.query<SignatureRow>(`
    select n.nspname as schema, c.relname as name,
      (xpath('/row/c/text()', query_to_xml(format(
        'select count(*)::text || '':'' || coalesce(md5(string_agg(md5(t::text), '''' order by md5(t::text))), '''') as c from %I.%I t',
        n.nspname, c.relname), false, true, '')))[1]::text as sig
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'r'
      and n.nspname not in ('pg_catalog', 'information_schema')
      and n.nspname not like 'pg\\_%'
    order by 1, 2`);

  return new Map(
    rows
      .filter((row) => !isNoiseTable(row))
      .map((row) => [tableKey(row), row.sig]),
  );
}

/**
 * The tables whose signature differs from `before`, or that `before` lacks, and
 * hold rows.
 */
export function changedTables(
  before: ReadonlyMap<string, string>,
  after: ReadonlyMap<string, string>,
  skip: ReadonlySet<string> = new Set(),
): readonly TableRef[] {
  return [...after]
    .filter(([key, sig]) => before.get(key) !== sig && !skip.has(key))
    .filter(([, sig]) => !sig.startsWith("0:"))
    .map(([key]) => {
      const dot = key.indexOf(".");

      return { schema: key.slice(0, dot), name: key.slice(dot + 1) };
    });
}

/**
 * Tables that held rows in `before` and now differ, so a restore must clear
 * them first.
 */
export function tablesToClear(
  before: ReadonlyMap<string, string>,
  changed: readonly TableRef[],
): readonly TableRef[] {
  return changed.filter((table) => {
    const sig = before.get(tableKey(table));

    return sig !== undefined && !sig.startsWith("0:");
  });
}

export function rowCounts(
  signatures: ReadonlyMap<string, string>,
  tables: readonly TableRef[],
): Record<string, number> {
  return Object.fromEntries(
    tables.map((table) => [
      tableKey(table),
      Number(signatures.get(tableKey(table))?.split(":")[0] ?? 0),
    ]),
  );
}

const quote = (name: string): string => `"${name.replaceAll('"', '""')}"`;

export const quoted = (table: TableRef): string =>
  `${quote(table.schema)}.${quote(table.name)}`;

/** `setval` calls that put every used sequence back where the build left it. */
export async function sequenceSql(client: PgQueryable): Promise<string> {
  const { rows } = await client.query<{
    schemaname: string;
    sequencename: string;
    last_value: string;
  }>(`
    select schemaname, sequencename, last_value::text
    from pg_sequences
    where last_value is not null
      and schemaname not in ('pg_catalog', 'information_schema')
    order by 1, 2`);

  return rows
    .map(
      (row) =>
        `select pg_catalog.setval('${quote(row.schemaname).replaceAll("'", "''")}.${quote(row.sequencename).replaceAll("'", "''")}', ${row.last_value}, true);`,
    )
    .join("\n");
}

/**
 * Moves every `xid8` or `xid` value of the restored tables that is ahead of the
 * restoring transaction back to its id. The rows keep the build database's
 * transaction ids, which a fresh stack has not reached, so an outbox consumer
 * would wait for its counter to catch up before it saw a new event.
 */
export function xidSql(tables: readonly TableRef[]): string {
  if (tables.length === 0) {
    return "";
  }

  const list = tables
    .map((table) => `'${quoted(table).replaceAll("'", "''")}'`)
    .join(", ");

  return `do $$
declare
  col record;
begin
  for col in
    select a.attrelid::regclass as tbl, a.attname, a.atttypid = 'pg_catalog.xid8'::regtype as wide
    from pg_catalog.pg_attribute a
    where a.attrelid = any (array[${list}]::regclass[])
      and a.atttypid in ('pg_catalog.xid8'::regtype, 'pg_catalog.xid'::regtype)
      and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
  loop
    if col.wide then
      execute format('update %s set %I = pg_catalog.pg_current_xact_id() where %I > pg_catalog.pg_current_xact_id()', col.tbl, col.attname, col.attname);
    else
      execute format('update %s set %I = pg_catalog.xid(pg_catalog.pg_current_xact_id()) where pg_catalog.age(%I) < 0', col.tbl, col.attname, col.attname);
    end if;
  end loop;
end;
$$;
`;
}

export type Fingerprint = Readonly<Record<string, string>>;

/**
 * A digest per kind of object the diff engine could miss: policies, triggers,
 * grants, function bodies and extensions. It is stored with the artifact and
 * recomputed after a restore.
 */
export async function catalogFingerprint(
  client: PgQueryable,
): Promise<Fingerprint> {
  const { rows } = await client.query<{ kind: string; digest: string }>(`
    select kind, md5(string_agg(x, E'\\n' order by x)) as digest from (
      select 'policies' as kind, schemaname || '.' || tablename || '.' || policyname || ' ' || cmd || ' ' || permissive
        || ' ' || roles::text || ' ' || coalesce(qual, '') || ' ' || coalesce(with_check, '') as x
        from pg_policies
      union all
      select 'triggers', tgrelid::regclass::text || ' ' || pg_get_triggerdef(oid)
        from pg_trigger where not tgisinternal
      union all
      select 'grants', table_schema || '.' || table_name || ' ' || grantee || ' ' || privilege_type
        from information_schema.role_table_grants
        where table_schema not in ('pg_catalog', 'information_schema')
      union all
      select 'functions', p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname not in ('pg_catalog', 'information_schema') and p.prokind in ('f', 'p')
      union all
      select 'extensions', extname || ' ' || extversion from pg_extension
    ) facts group by kind order by kind`);

  return Object.fromEntries(rows.map((row) => [row.kind, row.digest]));
}

/** The kinds whose digests differ. */
export function fingerprintDiff(
  expected: Fingerprint,
  actual: Fingerprint,
): readonly string[] {
  return [...new Set([...Object.keys(expected), ...Object.keys(actual)])]
    .filter((kind) => expected[kind] !== actual[kind])
    .toSorted();
}

/**
 * Tables an extension created. CREATE EXTENSION refills them, and pg_dump
 * leaves their data out unless the extension marks it, so the restore skips
 * them.
 */
export async function extensionTables(
  client: PgQueryable,
): Promise<ReadonlySet<string>> {
  const { rows } = await client.query<TableRef>(`
    select n.nspname as schema, c.relname as name
    from pg_depend d
    join pg_class c on c.oid = d.objid and d.classid = 'pg_class'::regclass
    join pg_namespace n on n.oid = c.relnamespace
    where d.deptype = 'e' and c.relkind = 'r'`);

  return new Set(rows.map(tableKey));
}

/**
 * Pgmq queues are tables the extension creates when `pgmq.create` runs, and
 * they belong to the extension, so the diff engine never sees them. The restore
 * recreates each queue by name.
 */
export async function pgmqQueues(
  client: PgQueryable,
): Promise<readonly string[]> {
  const found = await client.query<{ found: string | null }>(
    "select to_regclass('pgmq.meta')::text as found",
  );

  if (found.rows[0]?.found === null || found.rows[0] === undefined) {
    return [];
  }

  const { rows } = await client.query<{
    queue_name: string;
    is_partitioned: boolean;
    is_unlogged: boolean;
  }>(
    "select queue_name, is_partitioned, is_unlogged from pgmq.meta order by 1",
  );

  const partitioned = rows.find((row) => row.is_partitioned);

  if (partitioned !== undefined) {
    throw new CliError(
      "failed",
      `The pgmq queue ${partitioned.queue_name} is partitioned, and baseline cannot recreate it. Use unpartitioned queues in migrations and seeds, or skip the baseline.`,
    );
  }

  return rows.map((row) =>
    row.is_unlogged ? `unlogged:${row.queue_name}` : row.queue_name,
  );
}

/**
 * The triggers on queue tables, as statements; the diff engine does not see
 * them either.
 */
export async function queueTriggers(
  client: PgQueryable,
): Promise<readonly string[]> {
  const { rows } = await client.query<{ statement: string }>(`
    select pg_get_triggerdef(t.oid) || ';' as statement
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal and n.nspname = 'pgmq' and c.relname ~ '^[qa]_'
    order by 1`);

  return rows.map((row) => row.statement);
}

/** `pgmq.create` calls for the queues in `after` that `before` lacks. */
export function queueSql(
  before: readonly string[],
  after: readonly string[],
  triggers: readonly string[] = [],
): string {
  const had = new Set(before);

  const created = after
    .filter((queue) => !had.has(queue))
    .map((queue) => {
      const unlogged = queue.startsWith("unlogged:");
      const name = unlogged ? queue.slice("unlogged:".length) : queue;

      return `select pgmq.${unlogged ? "create_unlogged" : "create"}('${name.replaceAll("'", "''")}');`;
    })
    .join("\n");

  return [created, ...triggers].filter((part) => part !== "").join("\n");
}

export async function serverVersion(client: PgQueryable): Promise<string> {
  const { rows } = await client.query<{ server_version: string }>(
    "select current_setting('server_version') as server_version",
  );

  return rows[0]?.server_version ?? "";
}

export interface Extracted {
  readonly facts: Awaited<ReturnType<PgDelta["extract"]>>["factBase"];
  readonly pgVersion: string;
}

/** The profile that sees platform objects too: the migrations edit them. */
export async function extractCatalog(
  delta: PgDelta,
  pool: Pool,
): Promise<{
  readonly extracted: Extracted;
  readonly planOptions: Parameters<PgDelta["plan"]>[2];
}> {
  const profile = await delta.resolveProfile(pool, delta.rawProfile, {
    restrictToApplier: false,
    skipBaseline: true,
  });

  const result = await profile.extract(pool);

  return {
    extracted: { facts: result.factBase, pgVersion: result.pgVersion },
    planOptions: profile.planOptions,
  };
}

/**
 * The SQL that turns the first catalog into the second, one statement per
 * action.
 */
export function planSql(
  delta: PgDelta,
  from: Extracted,
  to: Extracted,
  options: Parameters<PgDelta["plan"]>[2],
): { readonly sql: string; readonly actions: number } {
  const plan = delta.plan(from.facts, to.facts, options);

  // CREATE EXTENSION already sets the comments and grants of its members, and
  // the stack's superuser owns them, so the postgres role could not restate them.
  const members = new Set(
    to.facts.edges
      .filter((edge) => edge.kind === "memberOfExtension")
      .map((edge) => delta.encodeId(edge.from)),
  );

  const ofMember = (id: Parameters<PgDelta["encodeId"]>[0]): boolean => {
    const target = SATELLITE.exec(delta.encodeId(id))?.[1];

    return target !== undefined && members.has(target);
  };

  const kept = plan.actions.filter(
    (action) => ![...action.produces, ...action.consumes].some(ofMember),
  );

  const sql = kept
    .map((action) => {
      const statement = action.sql.trim();

      return statement.endsWith(";") ? statement : `${statement};`;
    })
    .join("\n\n");

  return { sql, actions: kept.length };
}
